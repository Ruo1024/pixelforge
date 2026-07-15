extends "res://addons/gut/test.gd"

const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")


func test_width_count_matrix_uses_large_dynamic_tiles_and_at_most_three_rows() -> void:
	for width in [520, 720, 960, 1200]:
		for count in [0, 1, 2, 4, 5, 12, 13, 50]:
			var layout: Dictionary = LayoutScript.calculate(width, count)
			assert_lte(int(layout["columns"]), 5, "%d px / %d slots" % [width, count])
			assert_lte(int(layout["visible_rows"]), 3, "%d px / %d slots" % [width, count])
			if count >= 2:
				assert_gte(int(layout["tile_size"]), 176)
				assert_lte(int(layout["tile_size"]), 320)
	var default_twelve: Dictionary = LayoutScript.calculate(720, 12)
	assert_eq(default_twelve["columns"], 3)
	assert_eq(default_twelve["tile_size"], 224)
	assert_eq(default_twelve["visible_rows"], 3)


func test_single_slot_aspect_viewport_remains_bounded() -> void:
	assert_eq(LayoutScript.single_viewport_height(720, Vector2i(64, 32)), 344)
	assert_eq(LayoutScript.single_viewport_height(720, Vector2i(32, 64)), 420)
	assert_eq(LayoutScript.single_viewport_height(520, Vector2i(64, 64)), 420)


func test_scrollbar_is_visual_only_and_does_not_reflow_columns() -> void:
	var before: Dictionary = LayoutScript.calculate(720, 9)
	var after: Dictionary = LayoutScript.calculate(720, 10)
	assert_eq(LayoutScript.SCROLLBAR_VISUAL_WIDTH, 4)
	assert_eq(LayoutScript.SCROLLBAR_HIT_WIDTH, 12)
	assert_eq(before["columns"], after["columns"])
	assert_eq(before["tile_size"], after["tile_size"])


func test_default_width_empty_height_and_resize_bounds() -> void:
	assert_eq(LayoutScript.DEFAULT_WIDTH, 720)
	assert_eq(LayoutScript.calculate(720, 0)["natural_height"], 520)
	assert_eq(LayoutScript.clamp_output_width(200), 520)
	assert_eq(LayoutScript.clamp_output_width(1400), 1200)
	assert_lte(LayoutScript.calculate(1200, 50)["visible_rows"], 3)
