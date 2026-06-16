class_name PFTool
extends RefCounted

## 像素选区工具基类。
## UI 层负责把画布坐标转换为图像像素坐标；工具只关心单张 Image 内的像素选区。

signal selection_committed(selection: PFSelection)

const SelectionScript := preload("res://core/pixel/selection.gd")

const MOD_SHIFT := 1
const MOD_ALT := 2
const MARCHING_ANTS_DASH := 5.0
const MARCHING_ANTS_SPEED := 18.0

var current_selection: PFSelection = null
var _source_image: Image = null
var _source_size := Vector2i.ZERO


func get_id() -> String:
	return "tool"


func get_name() -> String:
	return "Tool"


func get_hotkey() -> String:
	return ""


func get_cursor_shape() -> int:
	return Input.CURSOR_ARROW


func on_activate() -> void:
	pass


func on_deactivate() -> void:
	pass


func set_source_image(image: Image) -> void:
	_source_image = image
	_source_size = image.get_size() if image != null else Vector2i.ZERO
	if current_selection != null and current_selection.image_size != _source_size:
		set_current_selection(null)


func set_current_selection(selection: PFSelection) -> void:
	current_selection = selection.duplicate_selection() if selection != null else null


func clear_selection() -> void:
	current_selection = null


func has_selection() -> bool:
	return current_selection != null and not current_selection.is_empty()


func wants_keyboard_shortcut(keycode: Key) -> bool:
	return not get_hotkey().is_empty() and OS.find_keycode_from_string(get_hotkey()) == keycode


func on_mouse_press(_image_pos: Vector2i, _button: MouseButton, _modifiers: int) -> void:
	pass


func on_mouse_move(_image_pos: Vector2i) -> void:
	pass


func on_mouse_release(_image_pos: Vector2i, _button: MouseButton, _modifiers: int) -> void:
	pass


func draw_overlay(canvas: Control, target: Dictionary) -> void:
	if has_selection():
		_draw_selection_bbox(canvas, target, current_selection.get_bbox())


func needs_redraw() -> bool:
	return has_selection()


func _combine_with_current(new_selection: PFSelection, modifiers: int) -> PFSelection:
	if current_selection == null or current_selection.image_size != new_selection.image_size:
		return new_selection
	if modifiers & MOD_SHIFT:
		return current_selection.union_with(new_selection)
	if modifiers & MOD_ALT:
		return current_selection.subtract(new_selection)
	return new_selection


func _commit_selection(selection: PFSelection) -> void:
	current_selection = selection
	selection_committed.emit(selection)


func _draw_selection_bbox(canvas: Control, target: Dictionary, bbox: Rect2i) -> void:
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		return
	var screen_rect := _image_rect_to_screen(canvas, target, bbox)
	_draw_dashed_rect(canvas, screen_rect, Color.WHITE, Color.BLACK)


func _image_rect_to_screen(canvas: Control, target: Dictionary, rect: Rect2i) -> Rect2:
	var top_left := _image_to_screen(canvas, target, Vector2(rect.position))
	var bottom_right := _image_to_screen(canvas, target, Vector2(rect.position + rect.size))
	return Rect2(top_left, bottom_right - top_left).abs()


func _image_to_screen(canvas: Control, target: Dictionary, image_pos: Vector2) -> Vector2:
	var world_position := Vector2(target.get("world_position", Vector2.ZERO))
	var scale_factor := float(target.get("scale_factor", 1))
	return canvas.world_to_screen(world_position + image_pos * scale_factor)


func _draw_dashed_rect(canvas: Control, rect: Rect2, light: Color, dark: Color) -> void:
	var phase := fmod(Time.get_ticks_msec() * 0.001 * MARCHING_ANTS_SPEED, MARCHING_ANTS_DASH * 2.0)
	_draw_dashed_line(
		canvas, rect.position, rect.position + Vector2(rect.size.x, 0), light, dark, phase
	)
	_draw_dashed_line(
		canvas,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		light,
		dark,
		phase
	)
	_draw_dashed_line(
		canvas,
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
		light,
		dark,
		phase
	)
	_draw_dashed_line(
		canvas, rect.position + Vector2(0, rect.size.y), rect.position, light, dark, phase
	)


func _draw_dashed_line(
	canvas: Control, from: Vector2, to: Vector2, light: Color, dark: Color, phase: float
) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var cursor := -phase
	var draw_light := true
	while cursor < length:
		var start := maxf(cursor, 0.0)
		var end := minf(cursor + MARCHING_ANTS_DASH, length)
		if end > 0.0:
			canvas.draw_line(
				from + direction * start, from + direction * end, light if draw_light else dark, 1.0
			)
		cursor += MARCHING_ANTS_DASH
		draw_light = not draw_light
