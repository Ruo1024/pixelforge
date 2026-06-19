class_name PFCanvasGraphEdgeInteraction
extends RefCounted

## Graph port drag/connect helper for PFInfiniteCanvas.
## contract: 02-contracts/GRAPH-SCHEMA.md §2；连接校验只委托 PFGraph。

const GraphScript := preload("res://core/graph/pf_graph.gd")


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


static func try_connect(start: Dictionary, end: Dictionary, changed: Callable) -> bool:
	var end_item: Node = end.get("item", null)
	if end_item == null:
		return false
	if String(start.get("graph_id", "")) != end_item.graph_id:
		return false
	if bool(start.get("is_input", false)) == bool(end.get("is_input", false)):
		return false

	var graph_id := String(start.get("graph_id", ""))
	var before := ProjectService.get_graph_data(graph_id)
	if before.is_empty():
		return false
	var graph: PFGraph = GraphScript.from_json(before)
	var endpoints := _resolve_endpoints(graph, start, end, end_item)
	if endpoints.is_empty():
		return false
	var result := graph.add_edge(
		endpoints["source_node"],
		endpoints["source_port"],
		endpoints["target_node"],
		endpoints["target_port"]
	)
	if not bool(result.get("ok", false)):
		return false

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
	return true


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
	canvas.draw_polyline(points, Color(0.72, 0.9, 0.95, 0.72), 2.0, true)


static func _resolve_endpoints(
	graph: PFGraph, start: Dictionary, end: Dictionary, end_item: Node
) -> Dictionary:
	if bool(start.get("is_input", false)):
		return _first_valid_connection(
			graph,
			end_item.node_id,
			[String(end.get("port_name", ""))],
			String(start.get("node_id", "")),
			_input_port_candidates(
				graph, String(start.get("node_id", "")), String(start.get("port_name", ""))
			)
		)
	return _first_valid_connection(
		graph,
		String(start.get("node_id", "")),
		[String(start.get("port_name", ""))],
		end_item.node_id,
		_input_port_candidates(graph, end_item.node_id, String(end.get("port_name", "")))
	)


static func _first_valid_connection(
	graph: PFGraph,
	source_node: String,
	source_ports: Array,
	target_node: String,
	target_ports: Array
) -> Dictionary:
	for source_port in source_ports:
		for target_port in target_ports:
			var result := graph.can_connect(
				source_node, String(source_port), target_node, String(target_port)
			)
			if bool(result.get("ok", false)):
				return {
					"source_node": source_node,
					"source_port": String(source_port),
					"target_node": target_node,
					"target_port": String(target_port),
				}
	return {}


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
