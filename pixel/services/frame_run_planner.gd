class_name PFFrameRunPlanner
extends RefCounted

const GraphScript := preload("res://core/graph/pf_graph.gd")


static func plan(graph_data: Dictionary, canvas_data: Dictionary, frame_id: String) -> Dictionary:
	var frame := _item(canvas_data, frame_id)
	if frame.is_empty() or String(frame.get("type", "")) != "frame":
		return _failure("frame_not_found")
	var graph_id := String(frame.get("graph_id", ""))
	if graph_id.is_empty() or graph_id != String(graph_data.get("id", "")):
		return _failure("frame_graph_mismatch")
	var member_node_ids := {}
	for raw_item in canvas_data.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		var raw_member_frame: Variant = item.get("frame_id", null)
		if raw_member_frame == null or String(raw_member_frame) != frame_id:
			continue
		if String(item.get("type", "")) == "node" and String(item.get("graph_id", "")) == graph_id:
			member_node_ids[String(item.get("node_id", ""))] = true
	var graph := GraphScript.from_json(graph_data)
	var targets: Array[String] = []
	var invalid_targets: Array[Dictionary] = []
	for node_id in member_node_ids:
		var node: PFNode = graph.get_node(String(node_id))
		if node == null:
			invalid_targets.append({"node_id": node_id, "reason": "node_not_found"})
		elif node.get_type() == "ai_generate":
			var issue := _generate_issue(graph, String(node_id))
			if issue.is_empty():
				targets.append(String(node_id))
			else:
				invalid_targets.append({"node_id": node_id, "reason": issue})
	if targets.is_empty():
		return {
			"ok": false,
			"code": "no_runnable_targets",
			"target_generate_ids": [],
			"invalid_targets": invalid_targets,
		}
	targets.sort()
	var included_nodes := {}
	var included_edges: Array[Dictionary] = []
	var request_count := 0
	var result_count := 0
	var known_cost := 0.0
	var cost_known := true
	for target_id in targets:
		var closure := _upstream_closure(graph, target_id)
		for node_id in closure:
			included_nodes[node_id] = true
		for edge in graph.edges:
			if (
				closure.has(_from_id(edge))
				and closure.has(_to_id(edge))
				and not included_edges.has(edge)
			):
				included_edges.append(edge.duplicate(true))
		var counts := _target_counts(graph, target_id)
		request_count += int(counts["requests"])
		result_count += int(counts["results"])
		if bool(counts["cost_known"]):
			known_cost += float(counts["cost"])
		else:
			cost_known = false
	var included_node_ids: Array = included_nodes.keys()
	included_node_ids.sort()
	return {
		"ok": true,
		"graph_id": graph_id,
		"frame_id": frame_id,
		"target_generate_ids": targets,
		"included_node_ids": included_node_ids,
		"included_edges": included_edges,
		"request_count": request_count,
		"result_count": result_count,
		"known_cost": known_cost if cost_known else -1.0,
		"invalid_targets": invalid_targets,
	}


static func _generate_issue(graph: PFGraph, target_id: String) -> String:
	var node: PFNode = graph.get_node(target_id)
	if node == null or node.is_ghost():
		return "node_unavailable"
	var connected_ports := {}
	for edge in graph.edges:
		if _to_id(edge) == target_id:
			connected_ports[String(edge.get("to", ["", ""])[1])] = true
	if not connected_ports.has("prompt") and not connected_ports.has("subjects"):
		return "missing_prompt"
	return ""


static func _upstream_closure(graph: PFGraph, target_id: String) -> Dictionary:
	var included := {target_id: true}
	var pending := [target_id]
	while not pending.is_empty():
		var current := String(pending.pop_back())
		for edge in graph.edges:
			if _to_id(edge) != current:
				continue
			var source := _from_id(edge)
			if not included.has(source):
				included[source] = true
				pending.append(source)
	return included


static func _target_counts(graph: PFGraph, target_id: String) -> Dictionary:
	var params := graph.get_node_params(target_id)
	var provider_id := String(params.get("provider_id", "mock"))
	var model_id := String(params.get("model_id", ""))
	var descriptor: Dictionary = ProviderService.get_model_descriptor(provider_id, model_id)
	if (
		descriptor.is_empty()
		and provider_id == ProviderService.AUTOMATION_PROVIDER
		and model_id == String(ProviderService.MOCK_MODEL_DESCRIPTOR["model_id"])
	):
		descriptor = ProviderService.MOCK_MODEL_DESCRIPTOR
	var max_batch := maxi(1, int(descriptor.get("capabilities", {}).get("max_batch", 1)))
	var results := maxi(1, int(params.get("batch_size", 1)))
	for edge in graph.edges:
		if _to_id(edge) != target_id or String(edge.get("to", ["", ""])[1]) != "subjects":
			continue
		var source_params := graph.get_node_params(_from_id(edge))
		var rows_value: Variant = source_params.get("rows", [])
		if rows_value is Array:
			results = 0
			for row in rows_value:
				if row is Dictionary and bool(row.get("enabled", true)):
					results += maxi(1, int(row.get("count", 1)))
	var requests := ceili(float(results) / float(max_batch))
	if provider_id == "mock":
		return {"requests": requests, "results": results, "cost": 0.0, "cost_known": true}
	return {
		"requests": requests,
		"results": results,
		"cost": -1.0,
		"cost_known": false,
	}


static func _item(canvas_data: Dictionary, item_id: String) -> Dictionary:
	for raw_item in canvas_data.get("items", []):
		if raw_item is Dictionary and String(raw_item.get("id", "")) == item_id:
			return raw_item
	return {}


static func _from_id(edge: Dictionary) -> String:
	return String(edge.get("from", ["", ""])[0])


static func _to_id(edge: Dictionary) -> String:
	return String(edge.get("to", ["", ""])[0])


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "code": code, "target_generate_ids": [], "invalid_targets": []}
