class_name PFCanvasGraphClipboard
extends RefCounted

## Pure data helper for copying graph-bound canvas cards as one selection.
## Canvas layout and graph logic stay separate per PROJECT-FORMAT.md §4.

const IdUtil := preload("res://core/util/id_util.gd")
const PAYLOAD_VERSION := 1
const RUNTIME_FIELDS := [
	"execution_status",
	"execution_detail",
	"task_id",
	"request_id",
	"job_id",
	"progress",
	"progress_message",
	"running",
	"started_at",
	"finished_at",
	"last_error",
	"error_message",
	"outputs",
	"cached_outputs",
]


static func capture(
	graph_data: Dictionary, canvas_items: Array, selected_item_ids: Array
) -> Dictionary:
	var graph_id := String(graph_data.get("id", ""))
	if graph_id.is_empty():
		return _error("missing_graph_id")

	var selected_lookup := {}
	for selected_id_value in selected_item_ids:
		var selected_id := String(selected_id_value)
		if not selected_id.is_empty():
			selected_lookup[selected_id] = true

	var graph_nodes := {}
	for raw_node in graph_data.get("nodes", []):
		if raw_node is Dictionary:
			var node_id := String(raw_node.get("id", ""))
			if not node_id.is_empty():
				graph_nodes[node_id] = raw_node

	var captured_items: Array = []
	var captured_nodes: Array = []
	var selected_node_ids := {}
	var positions_by_node := {}
	var anchor := Vector2(INF, INF)
	for raw_item in canvas_items:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		var item_id := String(item.get("id", ""))
		var node_id := String(item.get("node_id", ""))
		if (
			not selected_lookup.has(item_id)
			or String(item.get("type", "")) != "node"
			or String(item.get("graph_id", "")) != graph_id
			or not graph_nodes.has(node_id)
			or selected_node_ids.has(node_id)
		):
			continue
		var position := _position(item.get("position", [0, 0]))
		anchor.x = minf(anchor.x, position.x)
		anchor.y = minf(anchor.y, position.y)
		captured_items.append(_without_runtime_fields(item))
		captured_nodes.append(_without_runtime_fields(graph_nodes[node_id], true))
		selected_node_ids[node_id] = true
		positions_by_node[node_id] = position

	if captured_items.is_empty():
		return _error("empty_selection")

	for item in captured_items:
		var item_position := _position(item.get("position", [0, 0])) - anchor
		item["position"] = _position_array(item_position)
		item["frame_id"] = null
	for node in captured_nodes:
		var node_position: Vector2 = positions_by_node[String(node.get("id", ""))] - anchor
		node["position"] = _position_array(node_position)

	var captured_edges: Array = []
	for raw_edge in graph_data.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge: Dictionary = raw_edge
		var from_id := _endpoint_node_id(edge.get("from", []))
		var to_id := _endpoint_node_id(edge.get("to", []))
		if selected_node_ids.has(from_id) and selected_node_ids.has(to_id):
			captured_edges.append(edge.duplicate(true))

	return {
		"ok": true,
		"version": PAYLOAD_VERSION,
		"graph_id": graph_id,
		"anchor": _position_array(anchor),
		"items": captured_items,
		"nodes": captured_nodes,
		"edges": captured_edges,
	}


static func instantiate(
	payload: Dictionary, target_position: Vector2, id_factory: Callable = Callable()
) -> Dictionary:
	if int(payload.get("version", 0)) != PAYLOAD_VERSION:
		return _error("unsupported_payload_version")
	var graph_id := String(payload.get("graph_id", ""))
	var source_items: Array = payload.get("items", [])
	var source_nodes: Array = payload.get("nodes", [])
	if graph_id.is_empty() or source_items.is_empty() or source_nodes.is_empty():
		return _error("invalid_payload")

	var forbidden_ids := {}
	for source_item in source_items:
		if source_item is Dictionary:
			forbidden_ids[String(source_item.get("id", ""))] = true
	for source_node in source_nodes:
		if source_node is Dictionary:
			forbidden_ids[String(source_node.get("id", ""))] = true

	var node_id_map := {}
	var nodes: Array = []
	for raw_node in source_nodes:
		if not (raw_node is Dictionary):
			continue
		var node: Dictionary = _without_runtime_fields(raw_node, true)
		var old_node_id := String(node.get("id", ""))
		if old_node_id.is_empty() or node_id_map.has(old_node_id):
			continue
		var new_node_id := _next_id(id_factory, forbidden_ids)
		forbidden_ids[new_node_id] = true
		node_id_map[old_node_id] = new_node_id
		node["id"] = new_node_id
		node["position"] = _position_array(
			target_position + _position(node.get("position", [0, 0]))
		)
		nodes.append(node)

	var item_id_map := {}
	var items: Array = []
	for raw_item in source_items:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = _without_runtime_fields(raw_item)
		var old_item_id := String(item.get("id", ""))
		var old_node_id := String(item.get("node_id", ""))
		if old_item_id.is_empty() or not node_id_map.has(old_node_id):
			continue
		var new_item_id := _next_id(id_factory, forbidden_ids)
		forbidden_ids[new_item_id] = true
		item_id_map[old_item_id] = new_item_id
		item["id"] = new_item_id
		item["node_id"] = node_id_map[old_node_id]
		item["graph_id"] = graph_id
		item["frame_id"] = null
		item["position"] = _position_array(
			target_position + _position(item.get("position", [0, 0]))
		)
		items.append(item)

	var edges: Array = []
	for raw_edge in payload.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge: Dictionary = raw_edge.duplicate(true)
		var from_endpoint := _endpoint(edge.get("from", []))
		var to_endpoint := _endpoint(edge.get("to", []))
		if not node_id_map.has(from_endpoint[0]) or not node_id_map.has(to_endpoint[0]):
			continue
		from_endpoint[0] = node_id_map[from_endpoint[0]]
		to_endpoint[0] = node_id_map[to_endpoint[0]]
		edge["from"] = from_endpoint
		edge["to"] = to_endpoint
		edges.append(edge)

	return {
		"ok": true,
		"graph_id": graph_id,
		"items": items,
		"nodes": nodes,
		"edges": edges,
		"item_id_map": item_id_map,
		"node_id_map": node_id_map,
	}


static func _without_runtime_fields(data: Dictionary, clean_params: bool = false) -> Dictionary:
	var result := data.duplicate(true)
	for field in RUNTIME_FIELDS:
		result.erase(field)
	if clean_params and result.get("params") is Dictionary:
		var params: Dictionary = result["params"]
		for field in RUNTIME_FIELDS:
			params.erase(field)
		result["params"] = params
	return result


static func _next_id(id_factory: Callable, forbidden_ids: Dictionary) -> String:
	for _attempt in range(64):
		var candidate := String(id_factory.call()) if id_factory.is_valid() else IdUtil.uuid_v4()
		if not candidate.is_empty() and not forbidden_ids.has(candidate):
			return candidate
	return IdUtil.uuid_v4()


static func _endpoint(value: Variant) -> Array:
	if not (value is Array):
		return ["", ""]
	var source: Array = value
	return [
		String(source[0]) if source.size() > 0 else "",
		String(source[1]) if source.size() > 1 else ""
	]


static func _endpoint_node_id(value: Variant) -> String:
	return String(_endpoint(value)[0])


static func _position(value: Variant) -> Vector2:
	if not (value is Array):
		return Vector2.ZERO
	var source: Array = value
	if source.size() < 2:
		return Vector2.ZERO
	return Vector2(float(source[0]), float(source[1])).round()


static func _position_array(value: Vector2) -> Array:
	return [int(round(value.x)), int(round(value.y))]


static func _error(code: String) -> Dictionary:
	return {"ok": false, "error": {"code": code}}
