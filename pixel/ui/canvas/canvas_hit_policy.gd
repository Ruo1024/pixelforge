class_name PFCanvasHitPolicy
extends RefCounted

## Canvas hit-test arbitration for item-level interactions.

const KIND_EMPTY := "empty"
const KIND_ITEM := "item"
const KIND_BATCH_THUMBNAIL := "batch_thumbnail"


static func hit_at_world(
	item_layer: Node,
	world_position: Vector2,
	batch_card_script: Script,
	sprite_script: Script,
	node_card_script: Script
) -> Dictionary:
	var children := item_layer.get_children()
	for index in range(children.size() - 1, -1, -1):
		var item := children[index]
		if not _is_canvas_item(item, batch_card_script, sprite_script, node_card_script):
			continue
		if not item.visible or not item.contains_world_point(world_position):
			continue
		if item.get_script() == batch_card_script:
			var asset_index: int = item.asset_index_at_world(world_position)
			if asset_index >= 0:
				return _hit(KIND_BATCH_THUMBNAIL, item, asset_index)
		return _hit(KIND_ITEM, item, -1)
	return {"kind": KIND_EMPTY, "item": null, "item_id": "", "asset_index": -1}


static func _is_canvas_item(
	item: Variant, batch_card_script: Script, sprite_script: Script, node_card_script: Script
) -> bool:
	if not (item is Node):
		return false
	var script: Script = item.get_script()
	return script == batch_card_script or script == sprite_script or script == node_card_script


static func _hit(kind: String, item: Node, asset_index: int) -> Dictionary:
	return {"kind": kind, "item": item, "item_id": item.item_id, "asset_index": asset_index}
