class_name PFCanvasGraphEdgeInteraction
extends RefCounted

## Graph port drag/connect helper for PFInfiniteCanvas.
## contract: 02-contracts/GRAPH-SCHEMA.md §2；连接校验只委托 PFGraph。

const GraphScript := preload("res://core/graph/pf_graph.gd")
const SNAP_ZONE_GROW := 32.0


static func begin_drag(port_hit: Dictionary) -> Dictionary:
	var item: Node = port_hit.get("item", null)
	if item == null or item.graph_id.is_empty() or item.node_id.is_empty():
		return {}
	var port_name := String(port_hit.get("port_name", ""))
	if port_name.is_empty():
		return {}
	var is_input := bool(port_hit.get("is_input", false))
	return {
		"graph_id": item.graph_id,
		"node_id": item.node_id,
		"port_name": port_name,
		"is_input": is_input,
		"anchor": item.get_graph_port_anchor(port_name, is_input),
	}


static func try_connect(start: Dictionary, end: Dictionary, changed: Callable) -> Dictionary:
	var end_item: Node = end.get("item", null)
	if end_item == null:
		return _connect_result(false, "")
	if String(start.get("graph_id", "")) != end_item.graph_id:
		return _connect_result(false, "")
	if bool(start.get("is_input", false)) == bool(end.get("is_input", false)):
		return _connect_result(false, "")

	var graph_id := String(start.get("graph_id", ""))
	var before := ProjectService.get_graph_data(graph_id)
	if before.is_empty():
		return _connect_result(false, "")
	var graph: PFGraph = GraphScript.from_json(before)
	var endpoints := _resolve_connection(graph, start, end, end_item)
	if not bool(endpoints.get("ok", false)):
		return _connect_result(false, String(endpoints.get("reason", "")))
	var result := graph.add_edge(
		endpoints["source_node"],
		endpoints["source_port"],
		endpoints["target_node"],
		endpoints["target_port"]
	)
	if not bool(result.get("ok", false)):
		return _connect_result(false, String(result.get("reason", "")))

	var edge := {
		"from": [endpoints["source_node"], endpoints["source_port"]],
		"to": [endpoints["target_node"], endpoints["target_port"]],
	}
	var after := graph.to_json()
	UndoService.perform_action(
		"Connect graph ports",
		func() -> void:
			ProjectService.set_graph_data(graph_id, after)
			changed.call(),
		func() -> void:
			ProjectService.set_graph_data(graph_id, before)
			changed.call()
	)
	var connect_result := _connect_result(true, "")
	connect_result["edge"] = edge
	return connect_result


static func connect_at_screen(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	start: Dictionary,
	screen_position: Vector2,
	changed: Callable
) -> Dictionary:
	var end := snap_target(canvas, items_by_id, batch_script, node_script, start, screen_position)
	if end.is_empty():
		end = _target_at_screen(
			canvas, items_by_id, batch_script, node_script, start, screen_position, false
		)
	if end.is_empty():
		return _connect_result(false, "")
	return try_connect(start, end, changed)


static func update_drag_world(canvas: Control, screen_position: Vector2) -> Vector2:
	return canvas.screen_to_world(screen_position)


static func connection_preview(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	start: Dictionary,
	screen_position: Vector2
) -> Dictionary:
	var valid_target := _target_at_screen(
		canvas, items_by_id, batch_script, node_script, start, screen_position, true
	)
	if not valid_target.is_empty():
		return {
			"state": "valid",
			"reason": "",
			"anchor": valid_target.get("anchor", canvas.screen_to_world(screen_position)),
			"item_id": String(valid_target.get("item_id", "")),
			"port_name": String(valid_target.get("port_name", "")),
		}
	var target := _target_at_screen(
		canvas, items_by_id, batch_script, node_script, start, screen_position, false
	)
	if target.is_empty():
		return {"state": "none", "reason": ""}
	var graph_data := ProjectService.get_graph_data(String(start.get("graph_id", "")))
	if graph_data.is_empty():
		return {"state": "invalid", "reason": "Graph is unavailable"}
	var graph: PFGraph = GraphScript.from_json(graph_data)
	var target_item: Node = target.get("item", null)
	var connection := _resolve_connection(graph, start, target, target_item)
	return {
		"state": "valid" if bool(connection.get("ok", false)) else "invalid",
		"reason": String(connection.get("reason", "")),
		"anchor": target.get("anchor", canvas.screen_to_world(screen_position)),
		"item_id": String(target.get("item_id", "")),
		"port_name": String(target.get("port_name", "")),
	}


static func snap_target(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	start: Dictionary,
	screen_position: Vector2
) -> Dictionary:
	return _target_at_screen(
		canvas, items_by_id, batch_script, node_script, start, screen_position, true
	)


static func _target_at_screen(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	start: Dictionary,
	screen_position: Vector2,
	require_valid_connection: bool
) -> Dictionary:
	var graph_id := String(start.get("graph_id", ""))
	if graph_id.is_empty():
		return {}
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		return {}
	var graph: PFGraph = GraphScript.from_json(graph_data)
	var target_is_input := not bool(start.get("is_input", false))
	var pointer_world: Vector2 = canvas.screen_to_world(screen_position)
	var best: Dictionary = {}
	var best_distance: float = INF
	for raw_item in items_by_id.values():
		if not _is_graph_item(raw_item, batch_script, node_script):
			continue
		var item: Node = raw_item
		if item.graph_id != graph_id or item.node_id.is_empty():
			continue
		var snap_zone := _port_side_snap_zone(item, target_is_input)
		if not snap_zone.has_point(pointer_world):
			continue
		for port_name in _port_candidates(graph, item.node_id, target_is_input):
			var candidate := {
				"item": item,
				"item_id": item.item_id,
				"port_name": String(port_name),
				"is_input": target_is_input,
				"port_index": -1,
			}
			var connection := _resolve_connection(graph, start, candidate, item)
			if require_valid_connection and not bool(connection.get("ok", false)):
				continue
			var anchor: Vector2 = item.get_graph_port_anchor(String(port_name), target_is_input)
			var distance: float = canvas.world_to_screen(anchor).distance_to(screen_position)
			if distance < best_distance:
				candidate["anchor"] = anchor
				best = candidate
				best_distance = distance
	return best


static func delete_edge(selection: Dictionary, changed: Callable) -> Dictionary:
	var graph_id := String(selection.get("graph_id", ""))
	var edge: Dictionary = selection.get("edge", {})
	if graph_id.is_empty() or edge.is_empty():
		return _connect_result(false, "")
	var before := ProjectService.get_graph_data(graph_id)
	if before.is_empty():
		return _connect_result(false, "")
	var after := before.duplicate(true)
	var edges := []
	var removed := false
	var edge_key := _edge_key(edge)
	for raw_edge in before.get("edges", []):
		if raw_edge is Dictionary and _edge_key(raw_edge) == edge_key and not removed:
			removed = true
			continue
		edges.append(raw_edge)
	if not removed:
		return _connect_result(false, "")
	after["edges"] = edges
	UndoService.perform_action(
		"Delete graph edge",
		func() -> void:
			ProjectService.set_graph_data(graph_id, after)
			changed.call(),
		func() -> void:
			ProjectService.set_graph_data(graph_id, before)
			changed.call()
	)
	var result := _connect_result(true, "")
	result["edge"] = edge
	return result


static func draw_preview(
	canvas: Control, edge_renderer: Script, drag_state: Dictionary, drag_world: Vector2
) -> void:
	var start_world: Vector2 = drag_state.get("anchor", drag_world)
	var start: Vector2 = canvas.world_to_screen(start_world)
	var end: Vector2 = canvas.world_to_screen(drag_world)
	var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
	var direction := -1.0 if bool(drag_state.get("is_input", false)) else 1.0
	var control_a: Vector2 = start + Vector2(bend * direction, 0.0)
	var control_b: Vector2 = end - Vector2(bend * direction, 0.0)
	var points := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		points.append(edge_renderer._cubic_bezier(start, control_a, control_b, end, t))
	var preview_state := String(drag_state.get("preview_state", "none"))
	var preview_color := Color(0.72, 0.9, 0.95, 0.72)
	if preview_state == "valid":
		preview_color = Color(0.24, 0.9, 0.55, 0.9)
	elif preview_state == "invalid":
		preview_color = Color(0.95, 0.36, 0.3, 0.9)
	canvas.draw_polyline(points, preview_color, 2.0, true)


static func draw_edges(
	canvas: Control,
	edge_renderer: Script,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	color: Color,
	selected_edge: Dictionary,
	drag_state: Dictionary,
	drag_world: Vector2
) -> void:
	edge_renderer.draw(canvas, items_by_id, batch_script, node_script, color, selected_edge)
	if not drag_state.is_empty():
		draw_preview(canvas, edge_renderer, drag_state, drag_world)


static func _resolve_connection(
	graph: PFGraph, start: Dictionary, end: Dictionary, end_item: Node
) -> Dictionary:
	if bool(start.get("is_input", false)):
		return _first_connection_result(
			graph,
			end_item.node_id,
			[String(end.get("port_name", ""))],
			String(start.get("node_id", "")),
			_input_port_candidates(
				graph, String(start.get("node_id", "")), String(start.get("port_name", ""))
			)
		)
	return _first_connection_result(
		graph,
		String(start.get("node_id", "")),
		[String(start.get("port_name", ""))],
		end_item.node_id,
		_input_port_candidates(graph, end_item.node_id, String(end.get("port_name", "")))
	)


static func _first_connection_result(
	graph: PFGraph,
	source_node: String,
	source_ports: Array,
	target_node: String,
	target_ports: Array
) -> Dictionary:
	var first_reason := ""
	for source_port in source_ports:
		for target_port in target_ports:
			var result := graph.can_connect(
				source_node, String(source_port), target_node, String(target_port)
			)
			if bool(result.get("ok", false)):
				var connection := _connect_result(true, "")
				connection["source_node"] = source_node
				connection["source_port"] = String(source_port)
				connection["target_node"] = target_node
				connection["target_port"] = String(target_port)
				return connection
			if first_reason.is_empty():
				first_reason = String(result.get("reason", ""))
	return _connect_result(false, first_reason)


static func _input_port_candidates(graph: PFGraph, node_id: String, port_name: String) -> Array:
	var node := graph.get_node(node_id)
	if node == null:
		return []
	var exact := node.get_input_port(port_name)
	if not exact.is_empty():
		return [port_name]
	if port_name != "in":
		return [port_name]
	var ports := []
	for port in node.get_input_ports():
		ports.append(String(port.get("name", "")))
	return ports


static func _port_candidates(graph: PFGraph, node_id: String, is_input: bool) -> Array:
	var node := graph.get_node(node_id)
	if node == null:
		return []
	var specs := node.get_input_ports() if is_input else node.get_output_ports()
	var ports := []
	for port in specs:
		ports.append(String(port.get("name", "")))
	return ports


static func _is_graph_item(item: Variant, batch_script: Script, node_script: Script) -> bool:
	return item is Node and (item.get_script() == batch_script or item.get_script() == node_script)


static func _port_side_snap_zone(item: Node, is_input: bool) -> Rect2:
	var bounds: Rect2 = item.get_canvas_bounds()
	var side_bounds := bounds
	side_bounds.size.x = bounds.size.x * 0.5
	if not is_input:
		side_bounds.position.x += bounds.size.x * 0.5
	return side_bounds.grow(SNAP_ZONE_GROW)


static func _edge_key(edge: Dictionary) -> String:
	var from_data := _edge_endpoint(edge.get("from", []))
	var to_data := _edge_endpoint(edge.get("to", []))
	return "%s/%s>%s/%s" % [from_data[0], from_data[1], to_data[0], to_data[1]]


static func _edge_endpoint(value: Variant) -> Array:
	var endpoint := ["", ""]
	if not (value is Array):
		return endpoint
	var source: Array = value
	if source.size() >= 1:
		endpoint[0] = String(source[0])
	if source.size() >= 2:
		endpoint[1] = String(source[1])
	return endpoint


static func _connect_result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}
