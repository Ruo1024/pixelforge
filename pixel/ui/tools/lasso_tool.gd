class_name PFLassoTool
extends PFTool

## 套索选区工具。
## 左键追加多边形顶点，右键闭合；核心填充由 PFSelection.polygon 负责。

var _points: Array[Vector2i] = []
var _hover_pos := Vector2i.ZERO


func get_id() -> String:
	return "lasso"


func get_name() -> String:
	return "Lasso"


func get_hotkey() -> String:
	return "L"


func get_cursor_shape() -> int:
	return Input.CURSOR_CROSS


func on_deactivate() -> void:
	_points.clear()


func on_mouse_press(image_pos: Vector2i, button: MouseButton, modifiers: int) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_points.append(_clamp_image_pos(image_pos))
		_hover_pos = _clamp_image_pos(image_pos)
	elif button == MOUSE_BUTTON_RIGHT:
		_close_polygon(modifiers)


func on_mouse_move(image_pos: Vector2i) -> void:
	_hover_pos = _clamp_image_pos(image_pos)


func draw_overlay(canvas: Control, target: Dictionary) -> void:
	super.draw_overlay(canvas, target)
	if _points.is_empty():
		return
	for index in range(_points.size() - 1):
		canvas.draw_line(
			_image_to_screen(canvas, target, Vector2(_points[index])),
			_image_to_screen(canvas, target, Vector2(_points[index + 1])),
			Color(1.0, 0.88, 0.2, 1.0),
			1.5
		)
	canvas.draw_line(
		_image_to_screen(canvas, target, Vector2(_points.back())),
		_image_to_screen(canvas, target, Vector2(_hover_pos)),
		Color(0.7, 1.0, 0.45, 1.0),
		1.0
	)


func needs_redraw() -> bool:
	return super.needs_redraw() or not _points.is_empty()


func _close_polygon(modifiers: int) -> void:
	if _points.size() < 3:
		_points.clear()
		return
	var selection := SelectionScript.polygon(_source_size, _points)
	_points.clear()
	_commit_selection(_combine_with_current(selection, modifiers))


func _clamp_image_pos(pos: Vector2i) -> Vector2i:
	if _source_size.x <= 0 or _source_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i(clampi(pos.x, 0, _source_size.x - 1), clampi(pos.y, 0, _source_size.y - 1))
