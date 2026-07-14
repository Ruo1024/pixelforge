extends "res://addons/gut/test.gd"

const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")


func test_output_grid_caps_at_four_columns_and_scrolls_after_twelve() -> void:
	var twelve: Dictionary = LayoutScript.calculate(600, 12)
	var fifty: Dictionary = LayoutScript.calculate(600, 50)
	assert_eq(twelve["columns"], 4)
	assert_eq(twelve["rows"], 3)
	assert_eq(fifty["columns"], 4)
	assert_eq(fifty["rows"], 13)
	assert_eq(fifty["natural_height"], 488)
	assert_gt(fifty["content_height"], fifty["viewport_height"])


func test_output_width_clamps_and_never_grows_a_fifth_column() -> void:
	assert_eq(LayoutScript.clamp_output_width(200), 360)
	assert_eq(LayoutScript.clamp_output_width(1200), 960)
	for width in [360, 600, 720, 960]:
		assert_lte(int(LayoutScript.calculate(width, 50)["columns"]), 4)
