extends "res://addons/gut/test.gd"

const Selection := preload("res://core/pixel/selection.gd")


func test_magic_wand_contiguous_and_global_modes_select_expected_masks() -> void:
	var image := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_fill_rect(image, Rect2i(0, 1, 2, 2), Color.RED)
	_fill_rect(image, Rect2i(5, 1, 2, 2), Color.RED)
	_fill_rect(image, Rect2i(3, 1, 1, 3), Color.BLUE)

	var contiguous := Selection.magic_wand(image, Vector2i(0, 1), {"tolerance": 0.0})
	assert_eq(contiguous.get_selected_count(), 4)
	assert_eq(contiguous.get_bbox(), Rect2i(0, 1, 2, 2))
	assert_true(contiguous.contains(1, 2))
	assert_false(contiguous.contains(5, 1))

	var global := Selection.magic_wand(
		image, Vector2i(0, 1), {"tolerance": 0.0, "contiguous": false}
	)
	assert_eq(global.get_selected_count(), 8)
	assert_eq(global.get_bbox(), Rect2i(0, 1, 7, 2))


func test_selection_boolean_operations_are_pixel_exact() -> void:
	var left := Selection.rectangle(Vector2i(6, 4), Rect2i(1, 1, 3, 2))
	var right := Selection.rectangle(Vector2i(6, 4), Rect2i(3, 1, 2, 2))

	var merged := left.union_with(right)
	assert_eq(merged.get_selected_count(), 8)
	assert_eq(merged.get_bbox(), Rect2i(1, 1, 4, 2))

	var overlap := left.intersect(right)
	assert_eq(overlap.get_selected_count(), 2)
	assert_eq(overlap.get_bbox(), Rect2i(3, 1, 1, 2))

	var cut := left.subtract(right)
	assert_eq(cut.get_selected_count(), 4)
	assert_eq(cut.get_bbox(), Rect2i(1, 1, 2, 2))


func test_polygon_selection_extracts_transparent_bbox_image() -> void:
	var image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_fill_rect(image, Rect2i(1, 1, 4, 4), Color.GREEN)
	var selection := Selection.polygon(
		Vector2i(6, 6), [Vector2i(1, 1), Vector2i(5, 1), Vector2i(3, 5)]
	)

	assert_false(selection.is_empty())
	assert_eq(selection.get_bbox(), Rect2i(1, 1, 4, 4))
	var extracted := selection.extract_image(image)
	assert_eq(extracted.get_size(), Vector2i(4, 4))
	assert_eq(extracted.get_pixel(0, 0).to_html(false), Color.GREEN.to_html(false))
	assert_eq(extracted.get_pixel(3, 3).a, 0.0)


func test_magic_wand_256_response_time_stays_under_budget() -> void:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color8(32, 32, 32))
	var started := Time.get_ticks_usec()
	var selection := Selection.magic_wand(image, Vector2i(0, 0), {"tolerance": 0.0})
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	gut.p("magic wand 256x256 elapsed_ms=%.2f" % elapsed_ms)
	assert_eq(selection.get_selected_count(), 256 * 256)
	assert_lt(elapsed_ms, 50.0)


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			image.set_pixel(x, y, color)
