extends "res://addons/gut/test.gd"

const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")


func test_select_only_filters_duplicates_and_missing_ids() -> void:
	var selection := CanvasSelectionScript.new()

	selection.select_only(["a", "b", "a", "missing"], ["a", "b"])

	assert_eq(selection.get_selected_ids(), ["a", "b"])


func test_toggle_updates_selection_state() -> void:
	var selection := CanvasSelectionScript.new()

	selection.toggle("a", ["a", "b"])
	selection.toggle("missing", ["a", "b"])
	selection.toggle("a", ["a", "b"])

	assert_true(selection.is_empty())


func test_drag_and_box_state_are_separated_from_selected_ids() -> void:
	var selection := CanvasSelectionScript.new()
	selection.select_only(["sprite_1"], ["sprite_1"])

	selection.start_drag(Vector2(4, 8), {"sprite_1": Vector2(1, 2)})
	assert_true(selection.is_dragging_items)
	assert_eq(selection.drag_start_world, Vector2(4, 8))
	assert_eq(selection.drag_start_positions["sprite_1"], Vector2(1, 2))
	selection.stop_drag()
	assert_false(selection.is_dragging_items)

	selection.start_box(Vector2(10, 20), true)
	selection.update_box(Vector2(30, 40))
	assert_true(selection.is_box_selecting)
	assert_true(selection.box_additive)
	assert_eq(selection.get_box_rect(), Rect2(Vector2(10, 20), Vector2(20, 20)))
