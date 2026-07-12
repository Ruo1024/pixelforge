class_name PFGraphMockRunner
extends RefCounted

## M3 最小 mock 节点链运行器。
## contract: 03-milestones/M3-开发规划.md G-2；只跑本地 mock 链并把 image_list 物化进 batch。

const IdUtil := preload("res://core/util/id_util.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")


func run_to_batch(
	graph: PFGraph,
	asset_library: Node,
	batch_node_id: String = "",
	replace_batch_assets: bool = false
) -> Dictionary:
	var setup_result := _validate_run_setup(graph, asset_library)
	if not bool(setup_result["ok"]):
		return setup_result

	var order_result := _topological_order(graph, batch_node_id)
	if not bool(order_result["ok"]):
		return order_result

	var inputs_by_node := {}
	var outputs_by_node := {}
	var materialized_asset_ids := []
	var context := GraphContextScript.new(asset_library)
	for node_id in order_result["order"]:
		var run_result := _run_node(
			graph,
			String(node_id),
			inputs_by_node,
			outputs_by_node,
			asset_library,
			context,
			batch_node_id,
			replace_batch_assets
		)
		if not bool(run_result["ok"]):
			return run_result
		for asset_id in run_result.get("asset_ids", []):
			materialized_asset_ids.append(asset_id)

	if materialized_asset_ids.is_empty():
		return _error("empty_batch", "No generated images reached a batch node")
	return {"ok": true, "asset_ids": materialized_asset_ids, "graph": graph.to_json()}


func materialize_provider_batch(
	graph: PFGraph,
	batch_node_id: String,
	images: Array,
	metadata: Array,
	asset_library: Node,
	replace_batch_assets: bool = false
) -> Dictionary:
	## M4-V1 adapter: async providers supply the generated images, while graph materialization
	## continues to use the same batch/provenance path as the mock runner.
	return _materialize_batch(
		graph, batch_node_id, images, metadata, asset_library, replace_batch_assets
	)


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
	batch_node_id: String,
	replace_batch_assets: bool
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
	var asset_ids := []
	if node.get_type() == "batch":
		if batch_node_id.is_empty() or batch_node_id == node_id:
			var materialized := _materialize_batch(
				graph,
				node_id,
				inputs.get("in", []),
				inputs.get("__metadata", []),
				asset_library,
				replace_batch_assets
			)
			if not bool(materialized["ok"]):
				return materialized
			asset_ids = materialized["asset_ids"]
			outputs = {"images": _image_array(inputs.get("in", [])), "assets": asset_ids}
	else:
		outputs = node.execute(inputs, graph.get_node_params(node_id), context)
		if outputs.has("__error"):
			return _error_from_node(outputs["__error"], node_id)

	outputs_by_node[node_id] = outputs
	_propagate_outputs(graph, node_id, inputs_by_node, outputs_by_node)
	return {"ok": true, "asset_ids": asset_ids}


func _materialize_batch(
	graph: PFGraph,
	node_id: String,
	value: Variant,
	metadata: Variant,
	asset_library: Node,
	replace_batch_assets: bool
) -> Dictionary:
	var images := _image_array(value)
	if images.is_empty():
		return _error("empty_images", "Batch node received no images")

	var metas := _metadata_array(metadata)
	var asset_ids := []
	for index in range(images.size()):
		var meta: Dictionary = metas[index] if index < metas.size() else {}
		var asset_id: String = asset_library.register_image(
			images[index],
			String(meta.get("name", "mock_%03d" % index)),
			_asset_meta(graph.id, meta)
		)
		asset_ids.append(asset_id)

	var params := graph.get_node_params(node_id)
	var existing: Array = [] if replace_batch_assets else _string_array(params.get("asset_ids", []))
	for asset_id in asset_ids:
		existing.append(asset_id)
	params["asset_ids"] = existing
	graph.set_node_params(node_id, params)
	return {"ok": true, "asset_ids": asset_ids}


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
		target_inputs[to_port] = _coerce_edge_value(
			outputs.get(from_port, null),
			node.get_output_port(from_port),
			graph,
			to_node_id,
			to_port
		)
		if from_port == "images" and outputs.has("metadata"):
			target_inputs["__metadata"] = outputs["metadata"]
		if from_port == "image":
			for key in ["__reference_asset_id", "__reference_content_sha256"]:
				if outputs.has(key):
					target_inputs[key] = outputs[key]
		inputs_by_node[to_node_id] = target_inputs


func _coerce_edge_value(
	value: Variant, source_port: Dictionary, graph: PFGraph, to_node_id: String, to_port: String
) -> Variant:
	var target := graph.get_node(to_node_id)
	if target == null:
		return value
	var target_port := target.get_input_port(to_port)
	if (
		String(source_port.get("type", "")) == "image"
		and String(target_port.get("type", "")) == "image_list"
	):
		return [value]
	return value


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


func _asset_meta(graph_id: String, meta: Dictionary) -> Dictionary:
	var provider := String(meta.get("provider", "mock"))
	return {
		"origin": "generated",
		"tags": [provider, "graph"],
		"provenance":
		{
			"provider": provider,
			"model": meta.get("model", "pixel_mock_v1"),
			"prompt": meta.get("prompt", ""),
			"seed": meta.get("seed", null),
			"cost": meta.get("cost", -1.0),
			"provider_meta": meta.get("provider_meta", {}),
			"parent_asset": null,
			"graph_id": graph_id,
			"reference_asset_id": meta.get("reference_asset_id", null),
			"reference_content_sha256": meta.get("reference_content_sha256", null),
			"created_at": IdUtil.utc_now_iso(),
		},
	}


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


func _string_array(value: Variant) -> Array:
	var result := []
	if value is Array:
		for item in value:
			var id := String(item)
			if not id.is_empty():
				result.append(id)
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
