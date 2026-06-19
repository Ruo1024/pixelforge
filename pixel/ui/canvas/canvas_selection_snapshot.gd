class_name PFCanvasSelectionSnapshot
extends RefCounted

## Small helpers for canvas selection snapshots used by undoable interactions.


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
