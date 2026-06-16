class_name PFRectangleTool
extends PFTool

## 矩形选区工具。
## 拖拽期间只绘制预览框；松开鼠标时提交真实 PFSelection，便于撤销。

var _start_pos := Vector2i.ZERO
var _end_pos := Vector2i.ZERO
var _is_dragging := false


func get_id() -> String:
	return "rectangle"


func get_name() -> String:
	return "Rectangle Select"


func get_hotkey() -> String:
	return "M"


func get_cursor_shape() -> int:
	return Input.CURSOR_CROSS


func on_deactivate() -> void:
	_is_dragging = false


func on_mouse_press(image_pos: Vector2i, button: MouseButton, _modifiers: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	_start_pos = image_pos
	_end_pos = image_pos
	_is_dragging = true


func on_mouse_move(image_pos: Vector2i) -> void:
	if _is_dragging:
		_end_pos = image_pos


func on_mouse_release(image_pos: Vector2i, button: MouseButton, modifiers: int) -> void:
	if button != MOUSE_BUTTON_LEFT or not _is_dragging:
		return
	_is_dragging = false
	_end_pos = image_pos
	var rect := _rect_from_points(_start_pos, _end_pos)
	var selection := SelectionScript.rectangle(_source_size, rect)
	_commit_selection(_combine_with_current(selection, modifiers))


func draw_overlay(canvas: Control, target: Dictionary) -> void:
	super.draw_overlay(canvas, target)
	if not _is_dragging:
		return
	var rect := _rect_from_points(_start_pos, _end_pos)
	var screen_rect := _image_rect_to_screen(canvas, target, rect)
	canvas.draw_rect(screen_rect, Color(1.0, 0.9, 0.2, 0.18), true)
	canvas.draw_rect(screen_rect, Color(1.0, 0.9, 0.2, 1.0), false, 1.0)
	var font := canvas.get_theme_default_font()
	if font != null:
		var font_size := maxi(11, canvas.get_theme_font_size("font_size", "Label") - 2)
		canvas.draw_string(
			font,
			screen_rect.position + Vector2(5, -4),
			"%dx%d" % [rect.size.x, rect.size.y],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(1.0, 0.95, 0.55, 1.0)
		)


func needs_redraw() -> bool:
	return super.needs_redraw() or _is_dragging


func _rect_from_points(a: Vector2i, b: Vector2i) -> Rect2i:
	var min_pos := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var max_pos := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	min_pos.x = clampi(min_pos.x, 0, maxi(0, _source_size.x - 1))
	min_pos.y = clampi(min_pos.y, 0, maxi(0, _source_size.y - 1))
	max_pos.x = clampi(max_pos.x, 0, maxi(0, _source_size.x - 1))
	max_pos.y = clampi(max_pos.y, 0, maxi(0, _source_size.y - 1))
	return Rect2i(min_pos, max_pos - min_pos + Vector2i.ONE)
