class_name PFCanvasLODCoordinator
extends RefCounted

## Pushes canvas camera zoom to canvas-resident items that render semantic LOD.


static func sync_batch_camera_zoom(
	items_by_id: Dictionary, batch_card_script: Script, camera_zoom: float
) -> void:
	for raw_item in items_by_id.values():
		if not (raw_item is Node):
			continue
		var item: Node = raw_item
		if item.get_script() == batch_card_script:
			item.set_lod_camera_zoom(camera_zoom)


static func sync_camera_zoom(items_by_id: Dictionary, camera_zoom: float) -> void:
	for raw_item in items_by_id.values():
		if raw_item is Node and raw_item.has_method("set_lod_camera_zoom"):
			raw_item.set_lod_camera_zoom(camera_zoom)
