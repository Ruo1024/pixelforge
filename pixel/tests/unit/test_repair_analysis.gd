extends "res://addons/gut/test.gd"

const Repair := preload("res://core/editor/repair_analysis.gd")


func test_noise_cleanup_removes_isolated_color_but_protects_highlight() -> void:
	var image := Image.create(5, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.2, 0.2, 1.0))
	image.set_pixel(1, 1, Color(0.3, 0.1, 0.2, 1.0))
	image.set_pixel(3, 1, Color.WHITE)
	var changed := Repair.clean_noise(image, 1)
	assert_true(changed.has(Vector2i(1, 1)))
	assert_false(changed.has(Vector2i(3, 1)))
	assert_eq(image.get_pixel(1, 1), Color(0.2, 0.2, 0.2, 1.0))
	assert_eq(image.get_pixel(3, 1), Color.WHITE)


func test_outline_endpoint_detector_finds_broken_line_terminals_exactly() -> void:
	var image := Image.create(8, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for x in [1, 2, 3, 5, 6]:
		image.set_pixel(x, 1, Color.BLACK)
	var endpoints := Repair.outline_endpoints(image)
	assert_eq(endpoints, [Vector2i(1, 1), Vector2i(3, 1), Vector2i(5, 1), Vector2i(6, 1)])
