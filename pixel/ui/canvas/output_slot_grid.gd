class_name PFOutputSlotGrid
extends Control

## Output adapter over the shared virtualized media grid.

signal slot_pressed(slot_id: String)

const MediaTileGridScript := preload("res://ui/canvas/media_tile_grid.gd")

var scroll_offset := 0.0
var _slots: Array[Dictionary] = []
var _media_grid: PFMediaTileGrid = null


func _ready() -> void:
	_media_grid = MediaTileGridScript.new()
	_media_grid.name = "MediaTileGrid"
	_media_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_media_grid.item_pressed.connect(func(item_id: String) -> void: slot_pressed.emit(item_id))
	add_child(_media_grid)
	_apply(false)


func configure(slots: Array) -> void:
	_slots = _visible_slots(slots)
	scroll_offset = 0.0
	_apply(false)


func update_slots(slots: Array) -> void:
	_slots = _visible_slots(slots)
	_apply(true)


func slot_ids() -> Array[String]:
	var result: Array[String] = []
	for slot in _slots:
		result.append(String(slot.get("slot_id", "")))
	return result


func visible_slot_ids() -> Array[String]:
	return [] if _media_grid == null else _media_grid.visible_item_ids()


func slot_rect(index: int) -> Rect2:
	return Rect2() if _media_grid == null else _media_grid.item_rect(index)


func slot_id_at(local_position: Vector2) -> String:
	return "" if _media_grid == null else _media_grid.item_id_at(local_position)


func max_scroll_offset() -> float:
	return 0.0 if _media_grid == null else _media_grid.max_scroll_offset()


func set_scroll_offset(value: float) -> void:
	if _media_grid == null:
		return
	_media_grid.set_scroll_offset(value)
	scroll_offset = _media_grid.scroll_offset


func handle_wheel(direction: int, zoom_modifier: bool) -> bool:
	if _media_grid == null:
		return false
	var handled := _media_grid.handle_wheel(direction, zoom_modifier)
	scroll_offset = _media_grid.scroll_offset
	return handled


func created_tile_count() -> int:
	return 0 if _media_grid == null else _media_grid.created_tile_count()


func _apply(preserve_scroll: bool) -> void:
	if _media_grid == null:
		return
	var items: Array[Dictionary] = []
	for slot in _slots:
		var asset_value: Variant = slot.get("asset_id", "")
		(
			items
			. append(
				{
					"id": String(slot.get("slot_id", "")),
					"asset_id": String(asset_value) if asset_value is String else "",
					"status": String(slot.get("status", "queued")),
				}
			)
		)
	_media_grid.configure_items(items, preserve_scroll)
	scroll_offset = _media_grid.scroll_offset


func _visible_slots(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_value in value:
		if slot_value is Dictionary and not bool(slot_value.get("detached", false)):
			result.append(Dictionary(slot_value).duplicate(true))
	return result
