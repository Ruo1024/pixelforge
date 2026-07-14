class_name PFOutputSlotGrid
extends Control

## Stable-slot viewport with internal vertical scroll and exact hit mapping.

signal slot_pressed(slot_id: String)

const Layout := preload("res://ui/canvas/output_layout_calculator.gd")

const STATE_COLORS := {
	"queued": Color(0.24, 0.27, 0.32),
	"running": Color(0.22, 0.42, 0.62),
	"succeeded": Color(0.18, 0.56, 0.34),
	"failed": Color(0.64, 0.2, 0.22),
	"canceled": Color(0.32, 0.32, 0.34),
}

var scroll_offset := 0.0
var _slots: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func configure(slots: Array) -> void:
	_slots = _visible_slots(slots)
	scroll_offset = 0.0
	queue_redraw()


func update_slots(slots: Array) -> void:
	var previous_offset := scroll_offset
	_slots = _visible_slots(slots)
	scroll_offset = clampf(previous_offset, 0.0, max_scroll_offset())
	queue_redraw()


func slot_ids() -> Array[String]:
	var result: Array[String] = []
	for slot in _slots:
		result.append(String(slot.get("slot_id", "")))
	return result


func visible_slot_ids() -> Array[String]:
	var result: Array[String] = []
	var viewport := Rect2(Vector2.ZERO, size)
	for index in range(_slots.size()):
		if viewport.intersects(slot_rect(index)):
			result.append(String(_slots[index].get("slot_id", "")))
	return result


func slot_rect(index: int) -> Rect2:
	if index < 0 or index >= _slots.size():
		return Rect2()
	var layout := _layout()
	var columns := maxi(1, int(layout["columns"]))
	var tile_size := int(layout["tile_size"])
	var column := index % columns
	var row := int(index / columns)
	return Rect2(
		Vector2(
			Layout.HORIZONTAL_PADDING + column * (tile_size + Layout.TILE_GAP),
			row * (tile_size + Layout.TILE_GAP) - scroll_offset,
		),
		Vector2(tile_size, tile_size)
	)


func slot_id_at(local_position: Vector2) -> String:
	for index in range(_slots.size()):
		if slot_rect(index).has_point(local_position):
			return String(_slots[index].get("slot_id", ""))
	return ""


func max_scroll_offset() -> float:
	return maxf(0.0, float(_layout()["content_height"]) - size.y)


func set_scroll_offset(value: float) -> void:
	scroll_offset = clampf(value, 0.0, max_scroll_offset())
	queue_redraw()


func handle_wheel(direction: int, zoom_modifier: bool) -> bool:
	if zoom_modifier or direction == 0:
		return false
	var before := scroll_offset
	var step := float(maxi(48, int(_layout()["tile_size"]) + Layout.TILE_GAP))
	set_scroll_offset(scroll_offset + step * float(-direction))
	return not is_equal_approx(before, scroll_offset)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var slot_id := slot_id_at(event.position)
			if not slot_id.is_empty():
				slot_pressed.emit(slot_id)
				accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if handle_wheel(direction, event.ctrl_pressed or event.meta_pressed):
				accept_event()


func _draw() -> void:
	for index in range(_slots.size()):
		var rect := slot_rect(index)
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var status := String(_slots[index].get("status", "queued"))
		draw_rect(rect, STATE_COLORS.get(status, STATE_COLORS["queued"]), true)
		draw_rect(rect, Color(0.72, 0.75, 0.8), false, 1.0)
	if max_scroll_offset() > 0.0:
		var ratio := size.y / maxf(size.y + max_scroll_offset(), 1.0)
		var thumb_height := maxf(24.0, size.y * ratio)
		var travel := maxf(0.0, size.y - thumb_height)
		var y := travel * scroll_offset / maxf(max_scroll_offset(), 1.0)
		draw_rect(
			Rect2(
				size.x - Layout.SCROLLBAR_VISUAL_WIDTH,
				y,
				Layout.SCROLLBAR_VISUAL_WIDTH,
				thumb_height
			),
			Color(0.72, 0.75, 0.8, 0.72),
			true
		)


func _layout() -> Dictionary:
	return Layout.calculate(int(size.x), _slots.size())


func _visible_slots(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_value in value:
		if not (slot_value is Dictionary):
			continue
		var slot: Dictionary = slot_value
		if bool(slot.get("detached", false)):
			continue
		result.append(slot.duplicate(true))
	return result
