class_name PFCanvasMinimap
extends Control

## 画布导航缩略图。宿主提供画布导出的 items、内容边界和当前世界视口；
## 本控件只负责确定性映射、绘制与发出导航目标，不持有画布状态。

signal world_center_requested(world_center: Vector2)

const MAP_INSET := 8.0
const MIN_WORLD_EXTENT := 1.0
const MIN_ITEM_MARKER := 3.0
const DEFAULT_NODE_SIZE := Vector2(240.0, 160.0)
const DEFAULT_BATCH_SIZE := Vector2(600.0, 216.0)
const DEFAULT_SPRITE_SIZE := Vector2(64.0, 64.0)
const BACKGROUND_COLOR := Color(0.055, 0.062, 0.07, 0.94)
const CONTENT_COLOR := Color(0.26, 0.3, 0.33, 0.9)
const CARD_COLOR := Color(0.46, 0.58, 0.62, 0.9)
const SPRITE_COLOR := Color(0.42, 0.76, 0.62, 0.9)
const FRAME_FALLBACK_COLOR := Color(0.31, 0.44, 0.56, 0.9)
const VIEWPORT_FILL_COLOR := Color(0.96, 0.84, 0.28, 0.08)
const VIEWPORT_BORDER_COLOR := Color(0.96, 0.84, 0.28, 1.0)

var _items: Array = []
var _content_bounds := Rect2(Vector2.ZERO, Vector2.ONE)
var _viewport_world_rect := Rect2(Vector2.ZERO, Vector2.ONE)
var _is_dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func set_canvas_snapshot(items: Array, content_bounds: Rect2, viewport_world_rect: Rect2) -> void:
	_items = items.duplicate(true)
	_content_bounds = normalized_world_bounds(content_bounds)
	_viewport_world_rect = normalized_world_bounds(viewport_world_rect)
	queue_redraw()


func get_map_rect() -> Rect2:
	var inset := minf(MAP_INSET, minf(size.x, size.y) * 0.25)
	return Rect2(
		Vector2(inset, inset),
		Vector2(maxf(0.0, size.x - inset * 2.0), maxf(0.0, size.y - inset * 2.0))
	)


func get_viewport_map_rect() -> Rect2:
	return world_rect_to_map(_viewport_world_rect, _content_bounds, get_map_rect())


func map_position_to_world(map_position: Vector2) -> Vector2:
	return map_to_world(map_position, _content_bounds, get_map_rect())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_is_dragging = button.pressed
		if button.pressed:
			_request_world_center(button.position)
		accept_event()
	elif event is InputEventMouseMotion and _is_dragging:
		var motion := event as InputEventMouseMotion
		_request_world_center(motion.position)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	var map_rect := get_map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	draw_rect(map_rect, CONTENT_COLOR, true)
	_draw_items(map_rect, true)
	_draw_items(map_rect, false)
	var viewport_rect := get_viewport_map_rect().intersection(map_rect)
	if viewport_rect.has_area():
		draw_rect(viewport_rect, VIEWPORT_FILL_COLOR, true)
		draw_rect(viewport_rect, VIEWPORT_BORDER_COLOR, false, 1.0)


func _draw_items(map_rect: Rect2, frames: bool) -> void:
	for value in _items:
		if not (value is Dictionary):
			continue
		var item: Dictionary = value
		var is_frame := String(item.get("type", "")) == "frame"
		if is_frame != frames:
			continue
		var world_rect := item_world_rect(item)
		if not world_rect.has_area():
			continue
		var marker := world_rect_to_map(world_rect, _content_bounds, map_rect)
		marker.size.x = maxf(MIN_ITEM_MARKER, marker.size.x)
		marker.size.y = maxf(MIN_ITEM_MARKER, marker.size.y)
		marker = marker.intersection(map_rect)
		if not marker.has_area():
			continue
		if is_frame:
			var color := Color.from_string(
				String(item.get("color", "4f6f8fff")), FRAME_FALLBACK_COLOR
			)
			draw_rect(marker, Color(color, 0.16), true)
			draw_rect(marker, Color(color, 0.85), false, 1.0)
		elif String(item.get("type", "")) == "sprite":
			draw_rect(marker, SPRITE_COLOR, true)
		else:
			draw_rect(marker, CARD_COLOR, true)


func _request_world_center(map_position: Vector2) -> void:
	var map_rect := get_map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	world_center_requested.emit(map_to_world(map_position, _content_bounds, map_rect))


static func normalized_world_bounds(bounds: Rect2) -> Rect2:
	var normalized := bounds.abs()
	if normalized.size.x < MIN_WORLD_EXTENT:
		normalized.position.x -= (MIN_WORLD_EXTENT - normalized.size.x) * 0.5
		normalized.size.x = MIN_WORLD_EXTENT
	if normalized.size.y < MIN_WORLD_EXTENT:
		normalized.position.y -= (MIN_WORLD_EXTENT - normalized.size.y) * 0.5
		normalized.size.y = MIN_WORLD_EXTENT
	return normalized


static func world_to_map(world_position: Vector2, world_bounds: Rect2, map_rect: Rect2) -> Vector2:
	var bounds := normalized_world_bounds(world_bounds)
	var normalized := (world_position - bounds.position) / bounds.size
	return map_rect.position + normalized * map_rect.size


static func map_to_world(map_position: Vector2, world_bounds: Rect2, map_rect: Rect2) -> Vector2:
	var bounds := normalized_world_bounds(world_bounds)
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return bounds.get_center()
	var clamped := Vector2(
		clampf(map_position.x, map_rect.position.x, map_rect.end.x),
		clampf(map_position.y, map_rect.position.y, map_rect.end.y)
	)
	var normalized := (clamped - map_rect.position) / map_rect.size
	return bounds.position + normalized * bounds.size


static func world_rect_to_map(world_rect: Rect2, world_bounds: Rect2, map_rect: Rect2) -> Rect2:
	var normalized := world_rect.abs()
	return Rect2(
		world_to_map(normalized.position, world_bounds, map_rect),
		normalized.size / normalized_world_bounds(world_bounds).size * map_rect.size
	)


static func item_world_rect(item: Dictionary) -> Rect2:
	var position := _vector_from_value(item.get("position", [0, 0]), Vector2.ZERO)
	var explicit_bounds: Variant = item.get("bounds", null)
	if explicit_bounds is Rect2:
		return (explicit_bounds as Rect2).abs()
	if explicit_bounds is Dictionary:
		var bounds_data := explicit_bounds as Dictionary
		return (
			Rect2(
				_vector_from_value(bounds_data.get("position", [position.x, position.y]), position),
				_vector_from_value(bounds_data.get("size", [0, 0]), Vector2.ZERO)
			)
			. abs()
		)
	var item_type := String(item.get("type", ""))
	var fallback_size := DEFAULT_NODE_SIZE
	if item_type == "frame":
		fallback_size = Vector2.ONE
	elif item_type == "batch_card":
		fallback_size = DEFAULT_BATCH_SIZE
	elif item_type == "sprite":
		fallback_size = DEFAULT_SPRITE_SIZE
	var item_size := _vector_from_value(item.get("size", fallback_size), fallback_size)
	return Rect2(position, item_size).abs()


static func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
