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
	compare_asset_ids: Array,
	select_only: Callable,
	emit_changed: Callable
) -> void:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return
	var before: Array = item.asset_ids.duplicate()
	var before_review_states: Dictionary = item.get_review_states()
	var before_review_filter: String = item.get_review_filter()
	var before_focus_asset_id: String = item._get_focus_asset_id()
	var before_compare_asset_ids: Array = item._get_compare_asset_ids()
	var before_compare_mode: String = item._get_compare_mode()
	var after := new_asset_ids.duplicate()
	var after_review_states := {}
	var after_review_filter := CanvasBatchCardScript.FILTER_ALL
	var after_focus_asset_id := ""
	var after_compare_asset_ids := _aligned_compare_asset_ids(compare_asset_ids, after)
	var after_compare_mode := CanvasBatchCardScript.COMPARE_CURRENT
	var do_replace := func() -> void:
		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
		_apply_review_states(item, after_review_states)
		_apply_review_filter(item, after_review_filter)
		_apply_focus_asset_id(item, after_focus_asset_id)
		_apply_compare_state(item, after_compare_asset_ids, after_compare_mode)
		GraphItemBridge.sync_batch_node_asset_ids(item, after)
		GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
		GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, after_focus_asset_id)
		GraphItemBridge.sync_batch_node_compare_state(
			item, after_compare_asset_ids, after_compare_mode
		)
		select_only.call([card_id])
		emit_changed.call()
	var undo_replace := func() -> void:
		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
		_apply_review_states(item, before_review_states)
		_apply_review_filter(item, before_review_filter)
		_apply_focus_asset_id(item, before_focus_asset_id)
		_apply_compare_state(item, before_compare_asset_ids, before_compare_mode)
		GraphItemBridge.sync_batch_node_asset_ids(item, before)
		GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
		GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
		GraphItemBridge.sync_batch_node_compare_state(
			item, before_compare_asset_ids, before_compare_mode
		)
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
	var before_focus_asset_id: String = item._get_focus_asset_id()
	var after := before.duplicate(true)
	var normalized_state := _normalize_review_state(review_state)
	for asset_id in target_ids:
		if normalized_state.is_empty():
			after.erase(asset_id)
		else:
			after[asset_id] = normalized_state

	var do_mark := func() -> void:
		_apply_review_states(item, after)
		_apply_focus_asset_id(item, _focus_after_current_filter(item, before_focus_asset_id))
		GraphItemBridge.sync_batch_node_review_states(item, after)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, item._get_focus_asset_id())
		select_only.call([card_id])
		emit_changed.call()
	var undo_mark := func() -> void:
		_apply_review_states(item, before)
		_apply_focus_asset_id(item, before_focus_asset_id)
		GraphItemBridge.sync_batch_node_review_states(item, before)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
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
	var before_focus_asset_id: String = item._get_focus_asset_id()
	var after := _normalize_review_filter(review_filter)
	if before == after:
		return true
	var after_focus_asset_id := _focus_after_filter(item, before_focus_asset_id, after)

	var do_filter := func() -> void:
		_apply_review_filter(item, after)
		_apply_focus_asset_id(item, after_focus_asset_id)
		GraphItemBridge.sync_batch_node_review_filter(item, after)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, after_focus_asset_id)
		select_only.call([card_id])
		emit_changed.call()
	var undo_filter := func() -> void:
		_apply_review_filter(item, before)
		_apply_focus_asset_id(item, before_focus_asset_id)
		GraphItemBridge.sync_batch_node_review_filter(item, before)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Set batch review filter", do_filter, undo_filter)
	else:
		do_filter.call()
	return true


static func set_review_layout(
	items_by_id: Dictionary,
	card_id: String,
	review_layout: String,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> bool:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return false
	var before: String = item.get_review_layout()
	var after := _normalize_review_layout(review_layout)
	if before == after:
		return true

	var do_layout := func() -> void:
		_apply_review_layout(item, after)
		select_only.call([card_id])
		emit_changed.call()
	var undo_layout := func() -> void:
		_apply_review_layout(item, before)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Set batch review layout", do_layout, undo_layout)
	else:
		do_layout.call()
	return true


static func set_compare_mode(
	items_by_id: Dictionary,
	card_id: String,
	compare_mode: String,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> bool:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return false
	var before_mode: String = item._get_compare_mode()
	var after_mode := _normalize_compare_mode(item, compare_mode)
	if before_mode == after_mode:
		return true
	if (
		after_mode == CanvasBatchCardScript.COMPARE_PREVIOUS
		and item._get_compare_asset_ids().is_empty()
	):
		return false

	var compare_asset_ids: Array = item._get_compare_asset_ids()
	var do_compare := func() -> void:
		_apply_compare_mode(item, after_mode)
		GraphItemBridge.sync_batch_node_compare_state(item, compare_asset_ids, after_mode)
		select_only.call([card_id])
		emit_changed.call()
	var undo_compare := func() -> void:
		_apply_compare_mode(item, before_mode)
		GraphItemBridge.sync_batch_node_compare_state(item, compare_asset_ids, before_mode)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Set batch compare mode", do_compare, undo_compare)
	else:
		do_compare.call()
	return true


static func focus_relative(
	items_by_id: Dictionary,
	card_id: String,
	step: int,
	record_undo: bool,
	select_only: Callable,
	emit_changed: Callable
) -> Dictionary:
	var item := _batch_item(items_by_id, card_id)
	if item == null:
		return {}
	var target_asset_id: String = item._focus_asset_id_relative(step)
	if target_asset_id.is_empty():
		return {}

	var before_focus_asset_id: String = item._get_focus_asset_id()
	var before_selected_asset_ids: Array = item.selected_asset_ids.duplicate()
	var after_selected_asset_ids := [target_asset_id]
	var focus_result := _focus_result(item, target_asset_id)
	var do_focus := func() -> void:
		_apply_selected_asset_ids(item, after_selected_asset_ids)
		_apply_focus_asset_id(item, target_asset_id)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, target_asset_id)
		select_only.call([card_id])
		emit_changed.call()
	var undo_focus := func() -> void:
		_apply_selected_asset_ids(item, before_selected_asset_ids)
		_apply_focus_asset_id(item, before_focus_asset_id)
		GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
		select_only.call([card_id])
		emit_changed.call()

	if record_undo:
		UndoService.perform_action("Focus batch thumbnail", do_focus, undo_focus)
	else:
		do_focus.call()
	return focus_result


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


static func _apply_focus_asset_id(item: Node, focus_asset_id: String) -> void:
	item._set_focus_asset_id(focus_asset_id, false)


static func _apply_review_layout(item: Node, review_layout: String) -> void:
	item.set_review_layout(review_layout)


static func _apply_selected_asset_ids(item: Node, selected_asset_ids: Array) -> void:
	item._set_selected_asset_ids(selected_asset_ids)


static func _apply_compare_state(
	item: Node, compare_asset_ids: Array, compare_mode: String
) -> void:
	item._set_compare_state(compare_asset_ids, compare_mode)


static func _apply_compare_mode(item: Node, compare_mode: String) -> void:
	item._set_compare_mode(compare_mode)


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


static func _normalize_review_layout(review_layout: String) -> String:
	if review_layout in [CanvasBatchCardScript.LAYOUT_CONTACT, CanvasBatchCardScript.LAYOUT_FOCUS]:
		return review_layout
	return CanvasBatchCardScript.LAYOUT_CONTACT


static func _normalize_compare_mode(item: Node, compare_mode: String) -> String:
	if not item._get_compare_asset_ids().is_empty():
		match compare_mode:
			CanvasBatchCardScript.COMPARE_PREVIOUS, CanvasBatchCardScript.COMPARE_SPLIT:
				return compare_mode
	return CanvasBatchCardScript.COMPARE_CURRENT


static func _aligned_compare_asset_ids(compare_asset_ids: Array, current_asset_ids: Array) -> Array:
	var result := []
	if compare_asset_ids.size() != current_asset_ids.size():
		return result
	for raw_id in compare_asset_ids:
		result.append(String(raw_id))
	return result


static func _focus_result(item: Node, focus_asset_id: String) -> Dictionary:
	var visible_ids: Array = item.get_visible_asset_ids()
	return {
		"asset_id": focus_asset_id,
		"index": visible_ids.find(focus_asset_id) + 1,
		"total": visible_ids.size(),
	}


static func _focus_after_current_filter(item: Node, focus_asset_id: String) -> String:
	return focus_asset_id if item.get_visible_asset_ids().has(focus_asset_id) else ""


static func _focus_after_filter(
	item: Node, focus_asset_id: String, review_filter: String
) -> String:
	if focus_asset_id.is_empty():
		return ""
	var normalized_filter := _normalize_review_filter(review_filter)
	match normalized_filter:
		CanvasBatchCardScript.FILTER_ALL:
			return focus_asset_id if item.asset_ids.has(focus_asset_id) else ""
		CanvasBatchCardScript.FILTER_PENDING:
			if item.asset_ids.has(focus_asset_id) and not item.review_states.has(focus_asset_id):
				return focus_asset_id
		CanvasBatchCardScript.REVIEW_KEEP:
			if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
				return focus_asset_id
		CanvasBatchCardScript.REVIEW_REJECT:
			if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
				return focus_asset_id
		CanvasBatchCardScript.REVIEW_FLAG:
			if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
				return focus_asset_id
	return ""
