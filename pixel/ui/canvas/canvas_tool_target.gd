class_name PFCanvasToolTarget
extends RefCounted

## Resolves the active sprite target for canvas tools.


static func active_target(
	items_by_id: Dictionary, selection: Variant, sprite_script: Script
) -> Dictionary:
	var selected_ids: Array = selection.get_selected_ids()
	if selected_ids.size() != 1 or not items_by_id.has(selected_ids[0]):
		return {}
	var item: Node = items_by_id[selected_ids[0]]
	if item.get_script() != sprite_script:
		return {}
	var image: Image = item.duplicate_image()
	if image == null:
		return {}
	return {
		"item_id": item.item_id,
		"asset_id": item.asset_id,
		"image": image,
		"image_size": image.get_size(),
		"world_position": item.position,
		"scale_factor": item.scale_factor,
	}
