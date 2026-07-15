extends "res://addons/gut/test.gd"

const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")


func test_output_grid_uses_dynamic_columns_and_scrolls_after_three_rows() -> void:
	var twelve: Dictionary = LayoutScript.calculate(600, 12)
	var fifty: Dictionary = LayoutScript.calculate(600, 50)
	assert_eq(twelve["columns"], 3)
	assert_eq(twelve["rows"], 4)
	assert_eq(twelve["visible_rows"], 3)
	assert_eq(fifty["columns"], 3)
	assert_eq(fifty["rows"], 17)
	assert_eq(fifty["natural_height"], 632)
	assert_gt(fifty["content_height"], fifty["grid_height"])


func test_output_width_and_dynamic_columns_follow_media_grid_bounds() -> void:
	assert_eq(LayoutScript.clamp_output_width(200), 520)
	assert_eq(LayoutScript.clamp_output_width(1600), 1200)
	for width in [520, 600, 720, 1200]:
		assert_lte(int(LayoutScript.calculate(width, 50)["columns"]), 5)
