extends "res://addons/gut/test.gd"

const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")


func test_width_count_matrix() -> void:
	for width in [360, 600, 960]:
		for count in [0, 1, 2, 4, 5, 12, 13, 50]:
			var layout: Dictionary = LayoutScript.calculate(width, count)
			assert_lte(int(layout["columns"]), 4, "%d px / %d slots" % [width, count])
			assert_lte(int(layout["visible_rows"]), 3, "%d px / %d slots" % [width, count])
			if count >= 2:
				assert_gte(int(layout["tile_size"]), 96)
				assert_lte(int(layout["tile_size"]), 176)
	var fixed: Dictionary = LayoutScript.calculate(600, 13)
	assert_eq(fixed["columns"], 4)
	assert_eq(fixed["tile_size"], 136)
	assert_eq(fixed["grid_height"], 424)
	assert_eq(fixed["natural_height"], 488)


func test_single_slot_aspect_viewport() -> void:
	assert_eq(LayoutScript.single_viewport_height(600, Vector2i(64, 32)), 284)
	assert_eq(LayoutScript.single_viewport_height(600, Vector2i(32, 64)), 420)
	assert_eq(LayoutScript.single_viewport_height(360, Vector2i(64, 64)), 328)


func test_scrollbar_4_visual_12_hit_no_reflow() -> void:
	var before: Dictionary = LayoutScript.calculate(600, 12)
	var after: Dictionary = LayoutScript.calculate(600, 13)
	assert_eq(LayoutScript.SCROLLBAR_VISUAL_WIDTH, 4)
	assert_eq(LayoutScript.SCROLLBAR_HIT_WIDTH, 12)
	assert_eq(before["columns"], after["columns"])
	assert_eq(before["tile_size"], after["tile_size"])


func test_height_ranges_partial_row_natural_reset() -> void:
	assert_eq(LayoutScript.calculate(600, 0)["natural_height"], 240)
	assert_lte(LayoutScript.calculate(600, 1, Vector2i(32, 64))["natural_height"], 484)
	assert_eq(LayoutScript.clamp_output_width(200), 360)
	assert_eq(LayoutScript.clamp_output_width(1200), 960)
	assert_eq(LayoutScript.natural_height(600, 50), 488)
