extends "res://addons/gut/test.gd"

const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")


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


func _batch_card(
	width: int, height: int, count: int, layout: String = "contact", expected_count: int = 0
) -> Node:
	var ids: Array[String] = []
	for index in range(count):
		ids.append("asset-%02d" % index)
	var card: Node = CanvasBatchCardScript.new()
	add_child_autofree(card)
	card.setup_from_data(
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
	return card
