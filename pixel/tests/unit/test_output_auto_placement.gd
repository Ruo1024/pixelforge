extends "res://addons/gut/test.gd"

const PLACEMENT_PATH := "res://services/output_auto_placement.gd"


func test_right_side_scan_never_moves_existing() -> void:
	assert_true(ResourceLoader.exists(PLACEMENT_PATH), "B7-4 placement service must exist")
	if not ResourceLoader.exists(PLACEMENT_PATH):
		return
	var placement: Variant = load(PLACEMENT_PATH).new()
	var source := Rect2(Vector2(100, 200), Vector2(400, 520))
	var existing := [
		Rect2(Vector2(580, 200), Vector2(320, 220)),
		Rect2(Vector2(580, 476), Vector2(320, 220)),
	]
	var before := existing.duplicate(true)
	assert_eq(placement.find_position(source, existing, Vector2(320, 220)), Vector2(580, 752))
	assert_eq(existing, before)
	assert_eq(placement.find_position(source, [], Vector2(320, 220)), Vector2(580, 200))


func test_scan_uses_effective_bounds_and_fifty_six_gap() -> void:
	if not ResourceLoader.exists(PLACEMENT_PATH):
		fail_test("B7-4 placement service must exist")
		return
	var placement: Variant = load(PLACEMENT_PATH).new()
	var source := Rect2(Vector2.ZERO, Vector2(360, 400))
	var existing := [Rect2(Vector2(440, 0), Vector2(400, 520))]
	assert_eq(placement.find_position(source, existing, Vector2(400, 520)), Vector2(440, 576))


func test_generation_controller_uses_effective_canvas_bounds_instead_of_fixed_offset() -> void:
	var source := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	assert_true(source.contains("OutputAutoPlacementScript.find_position("))
	assert_true(source.contains("_canvas_item_bounds("))
	assert_false(source.contains("_node_position(graph, source_node_id) + Vector2(480, 0)"))
