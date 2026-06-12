class_name PFCanvasSelection
extends RefCounted

## 画布选择状态容器。
## InfiniteCanvas 负责坐标和绘制，本类只保存选择、拖拽和框选状态，避免交互状态继续堆在主画布脚本中。

signal selection_changed(selected_ids: Array)

var selected_ids: Array = []
var is_dragging_items := false
var is_box_selecting := false
var box_additive := false
var drag_start_world := Vector2.ZERO
var drag_start_positions := {}
var box_start_screen := Vector2.ZERO
var box_end_screen := Vector2.ZERO


func get_selected_ids() -> Array:
	return selected_ids.duplicate()


func is_empty() -> bool:
	return selected_ids.is_empty()


func has(item_id: String) -> bool:
	return selected_ids.has(item_id)


func select_only(ids: Array, available_ids: Array) -> void:
	selected_ids = _filter_ids(ids, available_ids)
	selection_changed.emit(get_selected_ids())


func clear(notify: bool = true) -> void:
	selected_ids.clear()
	if notify:
		selection_changed.emit([])


func remove_item_reference(item_id: String) -> void:
	selected_ids.erase(item_id)


func toggle(item_id: String, available_ids: Array) -> void:
	if not available_ids.has(item_id):
		return
	if selected_ids.has(item_id):
		selected_ids.erase(item_id)
	else:
		selected_ids.append(item_id)
	selection_changed.emit(get_selected_ids())


func start_drag(world_position: Vector2, start_positions: Dictionary) -> void:
	is_dragging_items = true
	drag_start_world = world_position
	drag_start_positions = start_positions.duplicate(true)


func stop_drag() -> void:
	is_dragging_items = false
	drag_start_positions.clear()


func start_box(screen_position: Vector2, additive: bool) -> void:
	is_box_selecting = true
	box_additive = additive
	box_start_screen = screen_position
	box_end_screen = screen_position


func update_box(screen_position: Vector2) -> void:
	box_end_screen = screen_position


func stop_box() -> void:
	is_box_selecting = false


func get_box_rect() -> Rect2:
	return Rect2(box_start_screen, box_end_screen - box_start_screen).abs()


func _filter_ids(ids: Array, available_ids: Array) -> Array:
	var filtered := []
	for item_id in ids:
		var normalized_id := String(item_id)
		if available_ids.has(normalized_id) and not filtered.has(normalized_id):
			filtered.append(normalized_id)
	return filtered
