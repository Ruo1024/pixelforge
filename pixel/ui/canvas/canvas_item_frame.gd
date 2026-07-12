class_name PFCanvasItemFrame
extends Node2D

## 显式阶段组的持久化与背景渲染。
## contract: PROJECT-FORMAT §4；成员只由 node.frame_id 表达，frame 不保存成员数组。

const DEFAULT_SIZE := Vector2(320, 240)
const DEFAULT_COLOR := Color(0.31, 0.44, 0.56, 1.0)
const UIFont := preload("res://ui/widgets/ui_font.gd")

var item_id := ""
var graph_id := ""
var title := ""
var frame_size := DEFAULT_SIZE
var frame_color := DEFAULT_COLOR
var locked := false
var _raw_data := {}


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", ""))
	graph_id = String(data.get("graph_id", ""))
	title = String(data.get("title", ""))
	frame_color = Color.from_string(String(data.get("color", "4f6f8fff")), DEFAULT_COLOR)
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	var raw_size: Variant = data.get("size", [DEFAULT_SIZE.x, DEFAULT_SIZE.y])
	frame_size = Vector2(maxf(1.0, float(raw_size[0])), maxf(1.0, float(raw_size[1]))).round()
	z_index = int(data.get("z_index", -1))
	queue_redraw()


func to_canvas_data() -> Dictionary:
	var result := _raw_data.duplicate(true)
	result["id"] = item_id
	result["type"] = "frame"
	result["graph_id"] = graph_id
	result["title"] = title
	result["color"] = frame_color.to_html()
	result["position"] = [int(round(position.x)), int(round(position.y))]
	result["size"] = [int(round(frame_size.x)), int(round(frame_size.y))]
	result["z_index"] = z_index
	result.erase("member_ids")
	return result


func get_canvas_bounds() -> Rect2:
	return Rect2(position, frame_size)


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func _draw() -> void:
	var local_rect := Rect2(Vector2.ZERO, frame_size)
	draw_rect(local_rect, Color(frame_color, 0.12), true)
	draw_rect(local_rect, Color(frame_color, 0.82), false, 2.0)
	var font: Font = UIFont.get_font()
	if font != null and not title.is_empty():
		draw_string(
			font,
			Vector2(12, 24),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			maxf(0.0, frame_size.x - 24.0),
			16,
			Color(frame_color, 1.0)
		)
