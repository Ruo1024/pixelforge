class_name PFCanvasBatchOps
extends RefCounted

## Read-only Output asset projection helpers. Domain writes live in InfiniteCanvas transactions.


static func get_asset_ids(items_by_id: Dictionary, card_id: String, selected_only: bool) -> Array:
	var item: Node = items_by_id.get(card_id, null)
	if item == null or not item.has_method("get_visible_asset_ids"):
		return []
	if selected_only and item.has_method("get_selected_asset_ids"):
		return item.get_selected_asset_ids()
	return item.get_visible_asset_ids()


static func get_selected_asset_ids(items_by_id: Dictionary, card_id: String) -> Array:
	return get_asset_ids(items_by_id, card_id, true)
