class_name PFCanvasBatchOps
extends RefCounted

## Batch-card operations that would otherwise bloat PFInfiniteCanvas.

const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")

const SPLIT_GAP := 24.0


static func get_asset_ids(
	items_by_id: Dictionary, card_id: String, selected_only: bool = false
) -> Array:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return []
	if selected_only:
		return item.get_selected_or_all_asset_ids()
	return item.asset_ids.duplicate()


static func get_selected_asset_ids(items_by_id: Dictionary, card_id: String) -> Array:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return []
	return item.get_selected_asset_ids()


static func get_marked_asset_ids(
	items_by_id: Dictionary, card_id: String, review_state: String
) -> Array:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return []
	return item.get_marked_asset_ids(review_state)


static func replace_asset_ids(
	items_by_id: Dictionary,
	card_id: String,
	new_asset_ids: Array,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> void:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return
	var before: Array = item.asset_ids.duplicate()
	var before_review_states: Dictionary = item.get_review_states()
	var before_review_filter: String = item.get_review_filter()
	var after := new_asset_ids.duplicate()
	var after_review_states := {}
	var after_review_filter := CanvasBatchCardScript.FILTER_ALL
	var do_replace := func() -> void:
		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
		_apply_review_states(item, after_review_states)
		_apply_review_filter(item, after_review_filter)
		GraphItemBridge.sync_batch_node_asset_ids(item, after)
		GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
		GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
		select_only.call([card_id])
		emit_changed.call()
	var undo_replace := func() -> void:
		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
		_apply_review_states(item, before_review_states)
		_apply_review_filter(item, before_review_filter)
		GraphItemBridge.sync_batch_node_asset_ids(item, before)
		GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
		GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
		select_only.call([card_id])
		emit_changed.call()
	if record_undo:
		UndoService.perform_action("Replace batch assets", do_replace, undo_replace)
	else:
		do_replace.call()


static func set_review_state(
	items_by_id: Dictionary,
	card_id: String,
	asset_ids: Array,
	review_state: String,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> int:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return 0
	var target_ids := _valid_target_ids(item, asset_ids)
	if target_ids.is_empty():
		return 0

	var before: Dictionary = item.get_review_states()
	var after := before.duplicate(true)
	var normalized_state := _normalize_review_state(review_state)
	for asset_id in target_ids:
		if normalized_state.is_empty():
			after.erase(asset_id)
		else:
			after[asset_id] = normalized_state

	var do_mark := func() -> void:
		_apply_review_states(item, after)
		GraphItemBridge.sync_batch_node_review_states(item, after)
		select_only.call([card_id])
		emit_changed.call()
	var undo_mark := func() -> void:
		_apply_review_states(item, before)
		GraphItemBridge.sync_batch_node_review_states(item, before)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Mark batch review state", do_mark, undo_mark)
	else:
		do_mark.call()
	return target_ids.size()


static func set_review_filter(
	items_by_id: Dictionary,
	card_id: String,
	review_filter: String,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> bool:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return false
	var before: String = item.get_review_filter()
	var after := _normalize_review_filter(review_filter)
	if before == after:
		return true

	var do_filter := func() -> void:
		_apply_review_filter(item, after)
		GraphItemBridge.sync_batch_node_review_filter(item, after)
		select_only.call([card_id])
		emit_changed.call()
	var undo_filter := func() -> void:
		_apply_review_filter(item, before)
		GraphItemBridge.sync_batch_node_review_filter(item, before)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Set batch review filter", do_filter, undo_filter)
	else:
		do_filter.call()
	return true


static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return {}
	return _split_spec(item, item.get_selected_or_all_asset_ids(), "subset")


static func split_marked_spec(
	items_by_id: Dictionary, card_id: String, review_state: String, label_suffix: String
) -> Dictionary:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return {}
	return _split_spec(item, item.get_marked_asset_ids(review_state), label_suffix)


static func _batch_item(items_by_id: Dictionary, card_id: String) -> Node:
	if not items_by_id.has(card_id):
		return null
	var item: Node = items_by_id[card_id]
	if item.get_script() != CanvasBatchCardScript:
		return null
	return item


static func _valid_target_ids(item: Node, asset_ids: Array) -> Array:
	var result := []
	for raw_id in asset_ids:
		var asset_id := String(raw_id)
		if item.asset_ids.has(asset_id) and not result.has(asset_id):
			result.append(asset_id)
	return result


static func _split_spec(item: Node, subset: Array, label_suffix: String) -> Dictionary:
	if subset.is_empty() or subset.size() == item.asset_ids.size():
		return {}
	return {
		"asset_ids": subset,
		"position": item.position + Vector2(item.get_canvas_bounds().size.x + SPLIT_GAP, 0.0),
		"label": "%s %s" % [item.label, label_suffix],
	}


static func _apply_review_states(item: Node, review_states: Dictionary) -> void:
	item.set_review_states(review_states)


static func _apply_review_filter(item: Node, review_filter: String) -> void:
	item.set_review_filter(review_filter)


static func _normalize_review_state(review_state: String) -> String:
	if (
		review_state
		in [
			CanvasBatchCardScript.REVIEW_KEEP,
			CanvasBatchCardScript.REVIEW_REJECT,
			CanvasBatchCardScript.REVIEW_FLAG,
		]
	):
		return review_state
	return CanvasBatchCardScript.REVIEW_NONE


static func _normalize_review_filter(review_filter: String) -> String:
	if (
		review_filter
		in [
			CanvasBatchCardScript.FILTER_ALL,
			CanvasBatchCardScript.FILTER_PENDING,
			CanvasBatchCardScript.REVIEW_KEEP,
			CanvasBatchCardScript.REVIEW_REJECT,
			CanvasBatchCardScript.REVIEW_FLAG,
		]
	):
		return review_filter
	return CanvasBatchCardScript.FILTER_ALL
