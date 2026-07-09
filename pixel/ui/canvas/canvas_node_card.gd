class_name PFCanvasNodeCard
extends Node2D

## M3 画布轻节点卡。
## contract: 02-contracts/PROJECT-FORMAT.md §4；只保存 graph/node 引用，节点逻辑从 graphs 读取。

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")

const CARD_SIZE := Vector2(220, 116)
const HEADER_HEIGHT := 32
const PADDING := 12
const BACKGROUND := Color(0.13, 0.145, 0.155, 0.98)
const HEADER := Color(0.22, 0.27, 0.3, 1.0)
const BORDER := Color(0.56, 0.64, 0.66, 1.0)
const GHOST_BORDER := Color(0.8, 0.36, 0.36, 1.0)
const EDGE_ERROR_BORDER := Color(0.94, 0.5, 0.22, 1.0)
const BADGE_BACKGROUND := Color(0.12, 0.08, 0.06, 0.92)
const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
const PORT_HIT_RADIUS := 10.0

var item_id := ""
var graph_id := ""
var node_id := ""
var locked := false

var _node_type := ""
var _display_name := "Missing Node"
var _summary := ""
var _input_count := 0
var _output_count := 0
var _input_ports: Array[String] = []
var _output_ports: Array[String] = []
var _visible_input_ports: Array[String] = []
var _visible_output_ports: Array[String] = []
var _is_ghost := false
var _has_edge_error := false
var _status_badge := ""
var _font: Font = null


func setup_from_data(data: Dictionary) -> void:
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	locked = bool(data.get("locked", false))
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_resolve_graph_node()
	queue_redraw()


func to_canvas_data() -> Dictionary:
	return {
		"id": item_id,
		"type": "node",
		"graph_id": graph_id,
		"node_id": node_id,
		"position": [int(round(position.x)), int(round(position.y))],
		"z_index": z_index,
		"collapsed": false,
		"locked": locked,
	}


func get_canvas_bounds() -> Rect2:
	return Rect2(position, CARD_SIZE)


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func is_graph_node() -> bool:
	return not graph_id.is_empty() and not node_id.is_empty()


func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
	var count := _input_count if is_input else _output_count
	if count <= 0:
		return position + Vector2(0.0 if is_input else CARD_SIZE.x, CARD_SIZE.y * 0.5)
	var index := _port_index(port_name, is_input)
	if index < 0:
		index = 0
	return position + _port_position(index, count, is_input)


func _graph_port_at_world(world_position: Vector2) -> Dictionary:
	var input_hit := _port_hit_at_world(world_position, true)
	if not input_hit.is_empty():
		return input_hit
	return _port_hit_at_world(world_position, false)


func _draw() -> void:
	_font = ThemeDB.fallback_font if _font == null else _font
	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
	draw_rect(rect, BACKGROUND, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(CARD_SIZE.x, HEADER_HEIGHT)), HEADER, true)
	draw_rect(rect, _border_color(), false, 1.4)
	_draw_ports()
	if _font == null:
		return
	draw_string(
		_font,
		Vector2(PADDING, 22),
		_display_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_SIZE.x - PADDING * 2,
		16,
		Color(0.92, 0.94, 0.94, 1.0)
	)
	_draw_status_badge()
	draw_string(
		_font,
		Vector2(PADDING, 54),
		_node_type,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_SIZE.x - PADDING * 2,
		13,
		Color(0.66, 0.72, 0.74, 1.0)
	)
	draw_string(
		_font,
		Vector2(PADDING, 82),
		_summary,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_SIZE.x - PADDING * 2,
		13,
		Color(0.82, 0.84, 0.82, 1.0)
	)


func _draw_ports() -> void:
	for index in range(_input_count):
		draw_circle(_port_position(index, _input_count, true), 5.0, PORT_IN)
	for index in range(_output_count):
		draw_circle(_port_position(index, _output_count, false), 5.0, PORT_OUT)


func _port_position(index: int, count: int, is_input: bool) -> Vector2:
	var usable_height := CARD_SIZE.y - HEADER_HEIGHT - PADDING * 2
	var y := HEADER_HEIGHT + PADDING + usable_height * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else CARD_SIZE.x, y)


func _port_index(port_name: String, is_input: bool) -> int:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	return ports.find(port_name)


func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	var count := ports.size()
	for index in range(count):
		var anchor := position + _port_position(index, count, is_input)
		if anchor.distance_to(world_position) <= PORT_HIT_RADIUS:
			return {"port_name": ports[index], "is_input": is_input, "port_index": index}
	return {}


func _resolve_graph_node() -> void:
	var node_data := _find_node_data()
	_node_type = String(node_data.get("type", "missing"))
	_summary = _summarize_params(node_data.get("params", {}))
	_has_edge_error = _graph_has_edge_error()
	_status_badge = ""

	var registry := NodeRegistryScript.new()
	var node: PFNode = registry.create(_node_type)
	if node == null:
		_is_ghost = true
		_display_name = Strings.GRAPH_NODE_MISSING_DISPLAY % _node_type
		_summary = Strings.GRAPH_NODE_GHOST_SUMMARY
		_input_count = 0
		_output_count = 0
		_input_ports = []
		_output_ports = []
		_visible_input_ports = []
		_visible_output_ports = []
		_status_badge = Strings.GRAPH_NODE_BADGE_MISSING
		return

	_display_name = node.get_display_name()
	_input_ports = _port_names(node.get_input_ports())
	_output_ports = _port_names(node.get_output_ports())
	_visible_input_ports = _visible_input_ports_for_node(_node_type, _input_ports)
	_visible_output_ports = _output_ports.duplicate()
	_input_count = _visible_input_ports.size()
	_output_count = _visible_output_ports.size()
	_is_ghost = false
	if _has_edge_error:
		_status_badge = Strings.GRAPH_NODE_BADGE_EDGE_ERROR


func _visible_input_ports_for_node(node_type: String, port_names: Array[String]) -> Array[String]:
	# M3 画布 MVP 只折叠视觉入口；graph edge 仍保留原始命名端口。
	if node_type == "ai_generate" and not port_names.is_empty():
		return ["in"]
	return port_names.duplicate()


func _port_names(port_specs: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for port_spec in port_specs:
		result.append(String(port_spec.get("name", "")))
	return result


func _find_node_data() -> Dictionary:
	var graph_data := ProjectService.get_graph_data(graph_id)
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node_data: Dictionary = raw_node
		if String(node_data.get("id", "")) == node_id:
			return node_data
	return {"id": node_id, "type": "missing", "params": {}}


func _graph_has_edge_error() -> bool:
	if graph_id.is_empty() or node_id.is_empty():
		return false
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		return false
	var graph: PFGraph = GraphScript.from_json(graph_data)
	return not graph.validate_edges_for_node(node_id).is_empty()


func _border_color() -> Color:
	if _is_ghost:
		return GHOST_BORDER
	if _has_edge_error:
		return EDGE_ERROR_BORDER
	return BORDER


func _draw_status_badge() -> void:
	if _status_badge.is_empty() or _font == null:
		return
	var badge_size := Vector2(72, 18)
	var badge_rect := Rect2(Vector2(CARD_SIZE.x - PADDING - badge_size.x, 8), badge_size)
	draw_rect(badge_rect, BADGE_BACKGROUND, true)
	draw_rect(badge_rect, _border_color(), false, 1.0)
	draw_string(
		_font,
		badge_rect.position + Vector2(5, 13),
		_status_badge,
		HORIZONTAL_ALIGNMENT_LEFT,
		badge_rect.size.x - 10,
		11,
		_border_color()
	)


func _summarize_params(params: Variant) -> String:
	if not (params is Dictionary):
		return ""
	var source: Dictionary = params
	if source.has("items"):
		var lines := String(source["items"]).split("\n", false)
		return "%d objects" % lines.size()
	if source.has("width") and source.has("height"):
		return "%dx%d px" % [int(source["width"]), int(source["height"])]
	if source.has("provider_id"):
		return "%s seed %d" % [String(source["provider_id"]), int(source.get("seed", 0))]
	return ""
