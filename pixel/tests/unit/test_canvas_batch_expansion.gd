extends "res://addons/gut/test.gd"

const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Beta 0.6 batch expansion")


func test_all_filter_creates_fifty_real_slots_at_contract_geometry() -> void:
	var card := _batch_card(600, 240, 50)
	assert_eq(card.get_visible_asset_ids().size(), 50)
	assert_eq(card._columns(), 4)
	assert_eq(card._rows(), 13)
	assert_eq(card.get_canvas_bounds().size, Vector2(600, 1936))
	var last_rect: Rect2 = card._slot_rect(49)
	assert_eq(last_rect, Rect2(Vector2(156, 1792), Vector2(128, 128)))
	assert_eq(card.asset_index_at_world(card.position + last_rect.get_center()), 49)


func test_five_column_threshold_is_exact() -> void:
	var below := _batch_card(719, 240, 13)
	var exact := _batch_card(720, 240, 13)
	assert_eq(below._columns(), 4)
	assert_eq(exact._columns(), 5)


func test_result_counts_and_widths_follow_one_growth_formula() -> void:
	var expected_default_rows := {0: 0, 1: 1, 4: 1, 12: 3, 13: 4, 50: 13}
	for count in expected_default_rows:
		var card := _batch_card(600, 240, count)
		assert_eq(card._columns(), 4, "count %s" % count)
		assert_eq(card._rows(), expected_default_rows[count], "count %s" % count)
		assert_eq(card.get_slot_count(), count, "count %s" % count)
		if count > 0:
			var tail: Rect2 = card._slot_rect(count - 1)
			assert_eq(card.asset_index_at_world(card.position + tail.get_center()), count - 1)
	var expected_columns := {360: 2, 600: 4, 880: 6, 1600: 11}
	for width in expected_columns:
		var card := _batch_card(width, 240, 50)
		assert_eq(card._columns(), expected_columns[width], "width %s" % width)
		assert_eq(
			card._rows(), int(ceil(50.0 / float(expected_columns[width]))), "width %s" % width
		)
		assert_gte(card.get_canvas_bounds().size.y, card._slot_rect(49).end.y + 16.0)


func test_auto_growth_retracts_and_placeholders_do_not_jump() -> void:
	var card := _batch_card(600, 240, 50)
	var expanded_bounds: Rect2 = card.get_canvas_bounds()
	card.set_asset_ids(["only"])
	assert_lt(card.get_canvas_bounds().size.y, expanded_bounds.size.y)
	assert_eq(card._rows(), 1)

	var placeholder := _batch_card(600, 240, 0, "contact", 50)
	var placeholder_bounds: Rect2 = placeholder.get_canvas_bounds()
	var ids: Array[String] = []
	for index in range(50):
		ids.append("asset-%02d" % index)
	placeholder.set_asset_ids(ids)
	assert_eq(placeholder.get_canvas_bounds(), placeholder_bounds)
	assert_eq(
		placeholder.asset_index_at_world(
			placeholder.position + placeholder._slot_rect(49).get_center()
		),
		49
	)


func test_focus_keeps_complete_grid_and_tail_hit_target() -> void:
	var card := _batch_card(600, 240, 50, "focus")
	var last_rect: Rect2 = card._slot_rect(49)
	assert_eq(card.get_visible_asset_ids().size(), 50)
	assert_eq(card.asset_index_at_world(card.position + last_rect.get_center()), 49)
	assert_gt(card.get_canvas_bounds().size.y, 1936.0)


func test_expected_placeholders_reserve_the_same_fifty_slots() -> void:
	var card := _batch_card(600, 240, 0, "contact", 50)
	assert_eq(card.get_slot_count(), 50)
	assert_eq(card._rows(), 13)
	assert_eq(card.get_canvas_bounds().size.y, 1936.0)


func test_last_of_fifty_uses_front_action_row_without_scroll_or_paging() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	var ids := []
	for index in range(50):
		ids.append("asset-%02d" % index)
	var card: Node = canvas._add_batch_card(ids, Vector2.ZERO, "Results", "batch", false)
	assert_not_null(card.get_node("BatchActionRow/FilterAll"))
	assert_not_null(card.get_node("BatchActionRow/ProcessAll"))
	assert_true(card.toggle_asset_at_world(card.position + card._slot_rect(49).get_center()))
	assert_not_null(card.get_node("BatchActionRow/ReviewKeep"))
	assert_not_null(card.get_node("BatchActionRow/Continue"))
	var face_events := []
	canvas.batch_face_action_requested.connect(
		func(card_id: String, action_id: String, asset_ids: Array) -> void:
			face_events.append([card_id, action_id, asset_ids])
	)
	(card.get_node("BatchActionRow/ReviewKeep") as Button).pressed.emit()
	assert_eq(card.get_review_states()[ids[49]], CanvasBatchCardScript.REVIEW_KEEP)
	assert_true(UndoService.undo())
	assert_false(card.get_review_states().has(ids[49]))
	(card.get_node("BatchActionRow/Continue") as Button).pressed.emit()
	assert_eq(face_events, [["batch", "continue", [ids[49]]]])
	for child in card.get_children():
		assert_false(child is ScrollContainer)
	assert_true(card.find_children("*Next*", "Button", true, false).is_empty())


func _batch_card(
	width: int, height: int, count: int, layout: String = "contact", expected_count: int = 0
) -> Node:
	var ids: Array[String] = []
	for index in range(count):
		ids.append("asset-%02d" % index)
	var card: Node = CanvasBatchCardScript.new()
	add_child_autofree(card)
	(
		card
		. setup_from_data(
			{
				"id": "batch",
				"type": "batch_card",
				"asset_ids": ids,
				"position": [40, 60],
				"size": [width, height],
				"review_layout": layout,
				"run_state": {"status": "running", "expected_count": expected_count},
			}
		)
	)
	return card
