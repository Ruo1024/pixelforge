class_name PFCanvasGraphEdgeRenderer
extends RefCounted

## Graph 连线渲染 helper。
## contract: 02-contracts/GRAPH-SCHEMA.md §1；连线来自 graphs，不写入 canvas.json。


static func draw(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	color: Color
) -> void:
	var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
	for graph_id in graph_items.keys():
		var graph_data := ProjectService.get_graph_data(String(graph_id))
		var items_by_node: Dictionary = graph_items[graph_id]
		for edge in graph_data.get("edges", []):
			if edge is Dictionary:
				_draw_edge_if_visible(canvas, Dictionary(edge), items_by_node, color)


static func _draw_edge_if_visible(
	canvas: Control, edge: Dictionary, items_by_node: Dictionary, color: Color
) -> void:
	var from_data: Array = edge.get("from", ["", ""])
	var to_data: Array = edge.get("to", ["", ""])
	var from_node := String(from_data[0])
	var to_node := String(to_data[0])
	if not items_by_node.has(from_node) or not items_by_node.has(to_node):
		return
	_draw_graph_edge(
		canvas,
		items_by_node[from_node],
		String(from_data[1]),
		items_by_node[to_node],
		String(to_data[1]),
		color
	)


static func _draw_graph_edge(
	canvas: Control,
	from_item: Node,
	from_port: String,
	to_item: Node,
	to_port: String,
	color: Color
) -> void:
	var start_world: Variant = _edge_anchor_world(from_item, from_port, false)
	var end_world: Variant = _edge_anchor_world(to_item, to_port, true)
	if not (start_world is Vector2) or not (end_world is Vector2):
		return
	var start: Vector2 = canvas.world_to_screen(start_world)
	var end: Vector2 = canvas.world_to_screen(end_world)
	var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
	var control_a := start + Vector2(bend, 0.0)
	var control_b := end - Vector2(bend, 0.0)
	var points := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		points.append(_cubic_bezier(start, control_a, control_b, end, t))
	canvas.draw_polyline(points, color, 2.0, true)


static func _edge_anchor_world(item: Node, port_name: String, is_input: bool) -> Variant:
	if item.has_method("get_graph_port_anchor"):
		return item.get_graph_port_anchor(port_name, is_input)
	var bounds: Rect2 = item.get_canvas_bounds()
	return bounds.position + Vector2(0.0 if is_input else bounds.size.x, bounds.size.y * 0.5)


static func _graph_items_by_node(
	items_by_id: Dictionary, batch_script: Script, node_script: Script
) -> Dictionary:
	var graph_items := {}
	for item in items_by_id.values():
		if not _is_canvas_graph_item(item, batch_script, node_script):
			continue
		if item.graph_id.is_empty() or item.node_id.is_empty():
			continue
		if not graph_items.has(item.graph_id):
			graph_items[item.graph_id] = {}
		graph_items[item.graph_id][item.node_id] = item
	return graph_items


static func _is_canvas_graph_item(item: Node, batch_script: Script, node_script: Script) -> bool:
	return item.get_script() == batch_script or item.get_script() == node_script


static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	var cd := c.lerp(d, t)
	var abbc := ab.lerp(bc, t)
	var bccd := bc.lerp(cd, t)
	return abbc.lerp(bccd, t)
