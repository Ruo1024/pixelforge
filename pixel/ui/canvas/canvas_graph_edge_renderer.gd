class_name PFCanvasGraphEdgeRenderer
extends RefCounted

## Graph 连线渲染 helper。
## contract: 02-contracts/GRAPH-SCHEMA.md §1；连线来自 graphs，不写入 canvas.json。

const EDGE_HIT_DISTANCE := 8.0
const SELECTED_EDGE_COLOR := Color(0.95, 0.86, 0.32, 1.0)
const INVALID_EDGE_COLOR := Color(0.96, 0.28, 0.22, 1.0)
const INVALID_SELECTED_EDGE_COLOR := Color(1.0, 0.42, 0.34, 1.0)
const RUN_OUTER_COLOR := Color(0.12, 0.95, 0.72, 0.28)
const RUN_INNER_COLOR := Color(0.48, 1.0, 0.92, 1.0)
const RUN_WARNING_COLOR := Color(1.0, 0.63, 0.15, 1.0)
const RUN_ERROR_COLOR := Color(1.0, 0.22, 0.19, 1.0)
const RUN_CANCELED_COLOR := Color(0.58, 0.62, 0.64, 1.0)

const GraphScript := preload("res://core/graph/pf_graph.gd")


static func draw(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	color: Color,
	selected_edge: Dictionary = {},
	run_edge_presenter: Variant = null,
	lod_percent: int = 100
) -> void:
	var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
	for graph_id in graph_items.keys():
		var graph_data := ProjectService.get_graph_data(String(graph_id))
		var graph: PFGraph = GraphScript.from_json(graph_data)
		var invalid_indices := _invalid_edge_indices(graph.validate_edges())
		var items_by_node: Dictionary = graph_items[graph_id]
		for index in range(graph.edges.size()):
			var edge_data := graph.edges[index]
			var is_invalid := invalid_indices.has(index)
			var edge_color := INVALID_EDGE_COLOR if is_invalid else color
			if _edge_matches(String(graph_id), edge_data, selected_edge):
				edge_color = INVALID_SELECTED_EDGE_COLOR if is_invalid else SELECTED_EDGE_COLOR
			var edge_width := 3.0 if is_invalid else 2.0
			_draw_edge_if_visible(
				canvas,
				graph,
				edge_data,
				items_by_node,
				edge_color,
				edge_width,
				run_edge_presenter,
				lod_percent
			)


static func hit_edge_at_screen(
	canvas: Control,
	items_by_id: Dictionary,
	batch_script: Script,
	node_script: Script,
	screen_position: Vector2
) -> Dictionary:
	var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
	for graph_id in graph_items.keys():
		var graph_data := ProjectService.get_graph_data(String(graph_id))
		var graph: PFGraph = GraphScript.from_json(graph_data)
		var items_by_node: Dictionary = graph_items[graph_id]
		for edge_data in graph.edges:
			var points := _edge_points(canvas, edge_data, items_by_node)
			if (
				points.size() > 1
				and _polyline_distance(points, screen_position) <= EDGE_HIT_DISTANCE
			):
				return {"graph_id": String(graph_id), "edge": edge_data}
	return {}


static func _draw_edge_if_visible(
	canvas: Control,
	graph: PFGraph,
	edge: Dictionary,
	items_by_node: Dictionary,
	color: Color,
	width: float,
	run_edge_presenter: Variant,
	lod_percent: int
) -> void:
	var from_data: Array = edge.get("from", ["", ""])
	var to_data: Array = edge.get("to", ["", ""])
	var from_node := String(from_data[0])
	var to_node := String(to_data[0])
	if not items_by_node.has(from_node) or not items_by_node.has(to_node):
		return
	var points := _edge_points(canvas, edge, items_by_node)
	if points.size() < 2:
		return
	canvas.draw_polyline(points, color, width, true)
	if run_edge_presenter == null:
		return
	var output_params := graph.get_node_params(to_node)
	var visual: Dictionary = run_edge_presenter.visual_for_edge(edge, output_params, lod_percent)
	_draw_run_visual(canvas, points, visual, color)


static func _draw_graph_edge(
	canvas: Control,
	from_item: Node,
	from_port: String,
	to_item: Node,
	to_port: String,
	color: Color,
	width: float
) -> void:
	var start_world: Variant = _edge_anchor_world(from_item, from_port, false)
	var end_world: Variant = _edge_anchor_world(to_item, to_port, true)
	if not (start_world is Vector2) or not (end_world is Vector2):
		return
	var start: Vector2 = canvas.world_to_screen(start_world)
	var end: Vector2 = canvas.world_to_screen(end_world)
	var points := _bezier_points(start, end)
	canvas.draw_polyline(points, color, width, true)


static func _draw_run_visual(
	canvas: Control, points: PackedVector2Array, visual: Dictionary, base_color: Color
) -> void:
	for command_value in _run_visual_commands(points, visual, base_color):
		var command: Dictionary = command_value
		match String(command.get("kind", "")):
			"polyline":
				canvas.draw_polyline(
					command["points"], command["color"], float(command["width"]), true
				)
			"dashes":
				_draw_dashed_path(canvas, command)
			"dot":
				canvas.draw_circle(
					command["position"], float(command["radius"]), command["color"], true
				)


static func _run_visual_commands(
	points: PackedVector2Array, visual: Dictionary, _base_color: Color
) -> Array:
	if points.size() < 2 or String(visual.get("state", "idle")) == "idle":
		return []
	var progress := clampf(float(visual.get("effect_progress", 0.0)), 0.0, 1.0)
	var phase_px := float(visual.get("phase_px", 0.0))
	if String(visual.get("render_mode", "polyline")) == "single_dot":
		var dot_position := points[0]
		var dot_radius := 3.5
		if bool(visual.get("advancing", false)):
			dot_position = _point_at_distance(points, phase_px)
		elif bool(visual.get("source_pulse", false)):
			dot_radius = 3.0 + (0.5 + 0.5 * sin(phase_px * TAU)) * 2.0
		return [
			{
				"kind": "dot",
				"position": dot_position,
				"radius": dot_radius,
				"color": _effect_color(visual, _effect_alpha(visual, progress)),
			}
		]
	match String(visual.get("effect", "static")):
		"source_pulse":
			var pulse := 0.5 + 0.5 * sin(phase_px * TAU)
			return [
				{
					"kind": "dot",
					"position": points[0],
					"radius": 3.0 + pulse * 2.0,
					"color": Color(RUN_INNER_COLOR, 0.5 + pulse * 0.5),
				}
			]
		"liquid_flow":
			return [
				{
					"kind": "polyline",
					"points": points,
					"color": RUN_OUTER_COLOR,
					"width": 8.0,
				},
				{
					"kind": "dashes",
					"points": points,
					"color": RUN_INNER_COLOR,
					"width": 2.5,
					"dash_on": 14.0,
					"dash_off": 10.0,
					"phase_px": phase_px,
				},
			]
		"success_fade", "warning_pulse", "error_pulse", "gray_fade", "static_warning":
			return [
				{
					"kind": "polyline",
					"points": points,
					"color": _effect_color(visual, _effect_alpha(visual, progress)),
					"width": 2.5,
				}
			]
	return []


static func _draw_dashed_path(canvas: Control, command: Dictionary) -> void:
	var points: PackedVector2Array = command["points"]
	var dash_on := float(command["dash_on"])
	var dash_off := float(command["dash_off"])
	var period := dash_on + dash_off
	var traveled := 0.0
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var length := start.distance_to(end)
		var segment_offset := 0.0
		while segment_offset < length:
			var cycle := fposmod(traveled + segment_offset - float(command["phase_px"]), period)
			var drawing := cycle < dash_on
			var until_boundary := (dash_on - cycle) if drawing else (period - cycle)
			var step := minf(until_boundary, length - segment_offset)
			if drawing and step > 0.0:
				canvas.draw_line(
					start.lerp(end, segment_offset / length),
					start.lerp(end, (segment_offset + step) / length),
					command["color"],
					float(command["width"]),
					true
				)
			segment_offset += maxf(step, 0.001)
		traveled += length


static func _effect_color(visual: Dictionary, alpha: float) -> Color:
	var color := RUN_INNER_COLOR
	if bool(visual.get("warning", false)):
		color = RUN_WARNING_COLOR
	elif bool(visual.get("error", false)):
		color = RUN_ERROR_COLOR
	elif bool(visual.get("gray_fade", false)):
		color = RUN_CANCELED_COLOR
	return Color(color, clampf(alpha, 0.0, 1.0))


static func _effect_alpha(visual: Dictionary, progress: float) -> float:
	if bool(visual.get("warning", false)) or bool(visual.get("error", false)):
		return sin(clampf(progress, 0.0, 1.0) * PI)
	return 1.0 - clampf(progress, 0.0, 1.0)


static func _point_at_distance(points: PackedVector2Array, distance: float) -> Vector2:
	var total := 0.0
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	if is_zero_approx(total):
		return points[0]
	var remaining := fposmod(distance, total)
	for index in range(points.size() - 1):
		var length := points[index].distance_to(points[index + 1])
		if remaining <= length:
			return points[index].lerp(points[index + 1], remaining / maxf(length, 0.001))
		remaining -= length
	return points[points.size() - 1]


static func _edge_points(
	canvas: Control, edge: Dictionary, items_by_node: Dictionary
) -> PackedVector2Array:
	var from_data: Array = edge.get("from", ["", ""])
	var to_data: Array = edge.get("to", ["", ""])
	var from_node := String(from_data[0])
	var to_node := String(to_data[0])
	if not items_by_node.has(from_node) or not items_by_node.has(to_node):
		return PackedVector2Array()
	var start_world: Variant = _edge_anchor_world(
		items_by_node[from_node], String(from_data[1]), false
	)
	var end_world: Variant = _edge_anchor_world(items_by_node[to_node], String(to_data[1]), true)
	if not (start_world is Vector2) or not (end_world is Vector2):
		return PackedVector2Array()
	return _bezier_points(canvas.world_to_screen(start_world), canvas.world_to_screen(end_world))


static func _bezier_points(start: Vector2, end: Vector2) -> PackedVector2Array:
	var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
	var control_a := start + Vector2(bend, 0.0)
	var control_b := end - Vector2(bend, 0.0)
	var points := PackedVector2Array()
	for index in range(17):
		var t := float(index) / 16.0
		points.append(_cubic_bezier(start, control_a, control_b, end, t))
	return points


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


static func _polyline_distance(points: PackedVector2Array, position: Vector2) -> float:
	var distance := INF
	for index in range(points.size() - 1):
		distance = minf(distance, _segment_distance(position, points[index], points[index + 1]))
	return distance


static func _segment_distance(position: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if is_zero_approx(length_squared):
		return position.distance_to(start)
	var t := clampf((position - start).dot(segment) / length_squared, 0.0, 1.0)
	return position.distance_to(start + segment * t)


static func _edge_matches(graph_id: String, edge: Dictionary, selected_edge: Dictionary) -> bool:
	return (
		graph_id == String(selected_edge.get("graph_id", ""))
		and edge == selected_edge.get("edge", {})
	)


static func _invalid_edge_indices(errors: Array[Dictionary]) -> Dictionary:
	var result := {}
	for error in errors:
		result[int(error.get("index", -1))] = true
	return result


static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var ab := a.lerp(b, t)
	var bc := b.lerp(c, t)
	var cd := c.lerp(d, t)
	var abbc := ab.lerp(bc, t)
	var bccd := bc.lerp(cd, t)
	return abbc.lerp(bccd, t)
