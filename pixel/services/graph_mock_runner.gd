class_name PFGraphMockRunner
extends RefCounted

## B7-2 本地 mock 节点链运行器。
## 旧执行器只产生单次终态；唯一临时 adapter 把该终态写成 v2 result_slots。

const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")
const LegacyAdapterScript := preload("res://services/legacy_generation_v2_adapter.gd")


func run_to_batch(graph: PFGraph, asset_library: Node, batch_node_id: String = "") -> Dictionary:
	var setup_result := _validate_run_setup(graph, asset_library)
	if not bool(setup_result["ok"]):
		return setup_result

	var order_result := _topological_order(graph, batch_node_id)
	if not bool(order_result["ok"]):
		return order_result

	var inputs_by_node := {}
	var outputs_by_node := {}
	var materialized_slots: Array[Dictionary] = []
	var context := GraphContextScript.new(asset_library)
	for node_id in order_result["order"]:
		var run_result := _run_node(
			graph,
			String(node_id),
			inputs_by_node,
			outputs_by_node,
			asset_library,
			context,
			batch_node_id
		)
		if not bool(run_result["ok"]):
			return run_result
		for slot in run_result.get("result_slots", []):
			if slot is Dictionary:
				materialized_slots.append(Dictionary(slot).duplicate(true))

	if materialized_slots.is_empty():
		return _error("empty_batch", "No generated images reached a batch node")
	return {"ok": true, "result_slots": materialized_slots, "graph": graph.to_json()}


func materialize_provider_batch(
	graph: PFGraph, batch_node_id: String, images: Array, metadata: Array, asset_library: Node
) -> Dictionary:
	return _materialize_batch(graph, batch_node_id, images, metadata, asset_library)


func materialize_provider_mapping(
	graph: PFGraph,
	batch_node_id: String,
	request: Dictionary,
	mapped: Dictionary,
	asset_library: Node
) -> Dictionary:
	if graph == null or graph.get_node(batch_node_id) == null:
		return _error("missing_node", "Batch node is missing")
	var adapter_result: Dictionary = LegacyAdapterScript.new().materialize_provider_mapping(
		graph.id,
		_source_node_id_for_batch(graph, batch_node_id),
		graph.get_node_params(batch_node_id),
		request,
		mapped,
		asset_library
	)
	if not bool(adapter_result.get("ok", false)):
		return adapter_result
	if not graph.set_node_params(batch_node_id, adapter_result["batch_params"]):
		return _error("missing_node", "Batch node is missing")
	return {
		"ok": true,
		"result_slots": Array(adapter_result["result_slots"]).duplicate(true),
	}


func _validate_run_setup(graph: PFGraph, asset_library: Node) -> Dictionary:
	if graph == null:
		return _error("missing_graph", "Graph is required")
	if asset_library == null or not asset_library.has_method("register_image"):
		return _error("missing_asset_library", "AssetLibrary-compatible object is required")

	var edge_errors := graph.validate_edges()
	if not edge_errors.is_empty():
		return _error("invalid_edge", String(edge_errors[0]["message"]))
	return {"ok": true}


func _run_node(
	graph: PFGraph,
	node_id: String,
	inputs_by_node: Dictionary,
	outputs_by_node: Dictionary,
	asset_library: Node,
	context: PFGraphContext,
	batch_node_id: String
) -> Dictionary:
	var node := graph.get_node(node_id)
	if node == null:
		return _error("missing_node", "Graph node is missing")
	if node.is_ghost():
		return _error("ghost_node", "Cannot run graph with missing node type: %s" % node.get_type())

	var inputs: Dictionary = inputs_by_node.get(node_id, {})
	var required_inputs := _validate_required_inputs(node, node_id, inputs)
	if not bool(required_inputs["ok"]):
		return required_inputs
	var outputs := {}
	var result_slots: Array[Dictionary] = []
	if node.get_type() == "batch":
		if batch_node_id.is_empty() or batch_node_id == node_id:
			var materialized := _materialize_batch(
				graph, node_id, inputs.get("in", []), inputs.get("__metadata", []), asset_library
			)
			if not bool(materialized["ok"]):
				return materialized
			result_slots.assign(materialized["result_slots"])
			outputs = {
				"assets": BatchNodeScript.get_visible_asset_ids(graph.get_node_params(node_id))
			}
	else:
		outputs = node.execute(inputs, graph.get_node_params(node_id), context)
		if outputs.has("__error"):
			return _error_from_node(outputs["__error"], node_id)

	outputs_by_node[node_id] = outputs
	_propagate_outputs(graph, node_id, inputs_by_node, outputs_by_node)
	return {"ok": true, "result_slots": result_slots}


func _materialize_batch(
	graph: PFGraph, node_id: String, value: Variant, metadata: Variant, asset_library: Node
) -> Dictionary:
	var images := _image_array(value)
	var metas := _metadata_array(metadata)
	var terminal_items := _terminal_items(images, metas)
	if terminal_items.is_empty():
		return _error("empty_images", "Batch node received no images")

	var adapter_result: Dictionary = LegacyAdapterScript.new().materialize_terminal(
		graph.id,
		_source_node_id_for_batch(graph, node_id),
		graph.get_node_params(node_id),
		terminal_items,
		asset_library
	)
	if not bool(adapter_result.get("ok", false)):
		return adapter_result
	if not graph.set_node_params(node_id, adapter_result["batch_params"]):
		return _error("missing_node", "Batch node is missing")
	return {
		"ok": true,
		"result_slots": Array(adapter_result["result_slots"]).duplicate(true),
	}


func _propagate_outputs(
	graph: PFGraph, node_id: String, inputs_by_node: Dictionary, outputs_by_node: Dictionary
) -> void:
	var node := graph.get_node(node_id)
	var outputs: Dictionary = outputs_by_node.get(node_id, {})
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		if String(from_data[0]) != node_id:
			continue
		var to_data: Array = edge.get("to", ["", ""])
		var to_node_id := String(to_data[0])
		var from_port := String(from_data[1])
		var to_port := String(to_data[1])
		var target_inputs: Dictionary = inputs_by_node.get(to_node_id, {})
		var value: Variant = outputs.get(from_port, null)
		if from_port == "subjects" and value is Array:
			var source_rows: Array = Array(value).duplicate(true)
			for row in source_rows:
				if row is Dictionary:
					row["source_node_id"] = node_id
			value = source_rows
		target_inputs[to_port] = value
		if outputs.has("metadata"):
			target_inputs["__metadata"] = outputs["metadata"]
		if from_port == "assets":
			for key in [
				"__reference_images",
				"__reference_asset_id",
				"__reference_content_sha256",
				"__reference_asset_ids",
				"__reference_content_sha256s",
			]:
				if outputs.has(key):
					target_inputs[key] = outputs[key]
		inputs_by_node[to_node_id] = target_inputs


func _validate_required_inputs(node: PFNode, node_id: String, inputs: Dictionary) -> Dictionary:
	for port in node.get_input_ports():
		if not bool(port.get("required", false)):
			continue
		var port_name := String(port.get("name", ""))
		if port_name.is_empty():
			continue
		if not inputs.has(port_name) or _is_missing_input(inputs[port_name]):
			return _error(
				"missing_required_input", "Node %s requires input port %s" % [node_id, port_name]
			)
	return {"ok": true}


func _is_missing_input(value: Variant) -> bool:
	if value == null:
		return true
	if value is Array or value is PackedStringArray:
		return value.is_empty()
	if value is Dictionary:
		return value.is_empty()
	if value is String:
		return String(value).strip_edges().is_empty()
	return false


func _topological_order(graph: PFGraph, target_node_id: String = "") -> Dictionary:
	var included := _upstream_node_ids(graph, target_node_id)
	var indegree := {}
	var outgoing := {}
	for node_id in graph.nodes.keys():
		if not included.has(node_id):
			continue
		indegree[node_id] = 0
		outgoing[node_id] = []
	for edge in graph.edges:
		var from_id := _edge_node(edge, "from")
		var to_id := _edge_node(edge, "to")
		if included.has(from_id) and included.has(to_id):
			indegree[to_id] = int(indegree[to_id]) + 1
			outgoing[from_id].append(to_id)

	var ready := []
	for node_id in indegree.keys():
		if int(indegree[node_id]) == 0:
			ready.append(node_id)
	ready.sort()

	var order := []
	while not ready.is_empty():
		var current := String(ready.pop_front())
		order.append(current)
		for target_id in outgoing[current]:
			indegree[target_id] = int(indegree[target_id]) - 1
			if int(indegree[target_id]) == 0:
				ready.append(target_id)
		ready.sort()

	if order.size() != included.size():
		return _error("cycle", "Graph contains a cycle")
	return {"ok": true, "order": order}


func _upstream_node_ids(graph: PFGraph, target_node_id: String) -> Dictionary:
	if target_node_id.is_empty() or not graph.nodes.has(target_node_id):
		var all := {}
		for node_id in graph.nodes.keys():
			all[node_id] = true
		return all
	var included := {target_node_id: true}
	var pending := [target_node_id]
	while not pending.is_empty():
		var current := String(pending.pop_back())
		for edge in graph.edges:
			if _edge_node(edge, "to") != current:
				continue
			var source := _edge_node(edge, "from")
			if graph.nodes.has(source) and not included.has(source):
				included[source] = true
				pending.append(source)
	return included


func _source_node_id_for_batch(graph: PFGraph, batch_node_id: String) -> String:
	for edge in graph.edges:
		if _edge_node(edge, "to") != batch_node_id:
			continue
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[1]) == "in":
			return _edge_node(edge, "from")
	return ""


func _terminal_items(images: Array, metadata: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := maxi(images.size(), metadata.size())
	for index in range(count):
		var meta: Dictionary = metadata[index] if index < metadata.size() else {}
		var image: Variant = images[index] if index < images.size() else null
		if image is Image:
			result.append({"image": image, "metadata": meta})
		elif meta.get("error", null) is Dictionary:
			result.append({"image": null, "metadata": meta, "error": meta["error"]})
	return result


func _image_array(value: Variant) -> Array:
	var result := []
	if value is Image:
		result.append(value)
	elif value is Array:
		for item in value:
			if item is Image:
				result.append(item)
	return result


func _metadata_array(value: Variant) -> Array:
	var result := []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item)
	return result


func _edge_node(edge: Dictionary, key: String) -> String:
	var data: Array = edge.get(key, ["", ""])
	return String(data[0])


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}


func _error_from_node(error: Dictionary, node_id: String) -> Dictionary:
	var detail := error.duplicate(true)
	detail["code"] = String(detail.get("code", "node_error"))
	detail["message"] = String(detail.get("message", "Node failed"))
	detail["node_id"] = node_id
	return {"ok": false, "error": detail}
