class_name PFCleanupGridOverlay
extends Control

## 清洗手动模式网格 overlay。
## 职责：在选中 sprite 上绘制可拖拽网格，并把拖动后的 offset 回传给检查器。

signal grid_changed(scale: float, offset: Vector2)

const GRID_COLOR := Color(0.15, 0.95, 0.78, 0.65)
const GRID_MAJOR_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const FILL_COLOR := Color(0.15, 0.95, 0.78, 0.08)
const MIN_SCREEN_STEP := 6.0

var canvas: Control = null
var world_bounds := Rect2()
var grid_scale := 4.0
var grid_offset := Vector2.ZERO
var overlay_active := false

var _dragging := false
var _drag_start_world := Vector2.ZERO
var _drag_start_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func set_canvas(owner: Control) -> void:
	canvas = owner


func configure(bounds: Rect2, scale: float, offset: Vector2, active: bool) -> void:
	world_bounds = bounds
	grid_scale = maxf(1.0, scale)
	grid_offset = _normalized_offset(offset)
	overlay_active = active and world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP if overlay_active else Control.MOUSE_FILTER_IGNORE
	visible = overlay_active
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not overlay_active or canvas == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _draw() -> void:
	if not overlay_active or canvas == null:
		return

	var screen_rect := _world_rect_to_screen(world_bounds)
	draw_rect(screen_rect, FILL_COLOR, true)
	draw_rect(screen_rect, GRID_MAJOR_COLOR, false, 1.0)
	_draw_axis_lines(true)
	_draw_axis_lines(false)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed and _world_rect_to_screen(world_bounds).has_point(event.position):
		_dragging = true
		_drag_start_world = canvas.screen_to_world(event.position)
		_drag_start_offset = grid_offset
		accept_event()
	elif not event.pressed:
		_dragging = false
		accept_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _dragging:
		return
	var world_delta: Vector2 = canvas.screen_to_world(event.position) - _drag_start_world
	grid_offset = _normalized_offset(_drag_start_offset + world_delta)
	grid_changed.emit(grid_scale, grid_offset)
	queue_redraw()
	accept_event()


func _draw_axis_lines(vertical: bool) -> void:
	var step := grid_scale
	var screen_step := step * float(canvas.camera_zoom)
	while screen_step < MIN_SCREEN_STEP:
		step *= 2.0
		screen_step = step * float(canvas.camera_zoom)

	var origin := world_bounds.position.x if vertical else world_bounds.position.y
	var limit := world_bounds.end.x if vertical else world_bounds.end.y
	var offset := grid_offset.x if vertical else grid_offset.y
	var line_position := origin + fposmod(offset, step)
	while line_position > origin:
		line_position -= step

	while line_position <= limit:
		if line_position >= origin:
			if vertical:
				var start_v: Vector2 = canvas.world_to_screen(
					Vector2(line_position, world_bounds.position.y)
				)
				var end_v: Vector2 = canvas.world_to_screen(
					Vector2(line_position, world_bounds.end.y)
				)
				draw_line(start_v, end_v, GRID_COLOR, 1.0)
			else:
				var start_h: Vector2 = canvas.world_to_screen(
					Vector2(world_bounds.position.x, line_position)
				)
				var end_h: Vector2 = canvas.world_to_screen(
					Vector2(world_bounds.end.x, line_position)
				)
				draw_line(start_h, end_h, GRID_COLOR, 1.0)
		line_position += step


func _normalized_offset(offset: Vector2) -> Vector2:
	return Vector2(fposmod(offset.x, grid_scale), fposmod(offset.y, grid_scale))


func _world_rect_to_screen(bounds: Rect2) -> Rect2:
	var top_left: Vector2 = canvas.world_to_screen(bounds.position)
	return Rect2(top_left, bounds.size * float(canvas.camera_zoom))
