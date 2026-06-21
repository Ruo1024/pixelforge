class_name PFCanvasSelectionSnapshot
extends RefCounted

## Small helpers for canvas selection snapshots and overlays.


static func selected_positions(items_by_id: Dictionary, selection: Variant) -> Dictionary:
	var positions := {}
	for item_id in selection.get_selected_ids():
		if items_by_id.has(item_id):
			positions[item_id] = items_by_id[item_id].position
	return positions


static func apply_positions(items_by_id: Dictionary, positions: Dictionary) -> void:
	for item_id in positions.keys():
		if items_by_id.has(item_id):
			items_by_id[item_id].position = Vector2(positions[item_id]).round()


static func positions_equal(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for item_id in left.keys():
		if not right.has(item_id):
			return false
		if Vector2(left[item_id]) != Vector2(right[item_id]):
			return false
	return true


static func ids_from_snapshots(snapshots: Array) -> Array:
	var ids := []
	for snapshot in snapshots:
		ids.append(String(snapshot["data"]["id"]))
	return ids


static func draw_overlay(
	canvas: Variant,
	items_by_id: Dictionary,
	selection: Variant,
	selection_color: Color,
	box_color: Color
) -> void:
	for item_id in selection.selected_ids:
		if not items_by_id.has(item_id):
			continue
		var item: Node = items_by_id[item_id]
		var bounds: Rect2 = item.get_canvas_bounds()
		var screen_rect: Rect2 = canvas._world_rect_to_screen(bounds)
		canvas.draw_rect(screen_rect.grow(2.0), selection_color, false, 2.0)

	if selection.is_box_selecting:
		var box: Rect2 = selection.get_box_rect()
		canvas.draw_rect(box, box_color, true)
		canvas.draw_rect(box, Color(1.0, 0.85, 0.25, 1.0), false, 1.0)
