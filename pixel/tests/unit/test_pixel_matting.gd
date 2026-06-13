extends "res://addons/gut/test.gd"

const Matting := preload("res://core/pixel/matting.gd")


func test_flood_matting_keeps_internal_highlight_but_global_removes_it() -> void:
	var image := _make_apple_on_white()

	var flood: Dictionary = Matting.matte(
		image, {"mode": Matting.MODE_FLOOD, "tolerance": 0.0, "feather": 0}
	)
	var flood_image: Image = flood["image"]
	assert_true(bool(flood["is_flat_bg"]))
	assert_eq(flood_image.get_pixel(0, 0).a, 0.0)
	assert_eq(flood_image.get_pixel(5, 5).a, 1.0)
	assert_eq(flood_image.get_pixel(4, 4).to_html(false), Color.RED.to_html(false))

	var global: Dictionary = Matting.matte(
		image, {"mode": Matting.MODE_GLOBAL, "tolerance": 0.0, "feather": 0}
	)
	var global_image: Image = global["image"]
	assert_eq(global_image.get_pixel(0, 0).a, 0.0)
	assert_eq(global_image.get_pixel(5, 5).a, 0.0)


func test_gradient_boundary_reports_non_flat_background_without_deleting_pixels() -> void:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in range(12):
		for x in range(12):
			image.set_pixel(x, y, Color(float(x) / 11.0, 0.4, float(y) / 11.0, 1.0))

	var result: Dictionary = Matting.matte(image, {"mode": Matting.MODE_FLOOD})
	var output: Image = result["image"]
	assert_false(bool(result["is_flat_bg"]))
	assert_eq(String(result["warning"]), "non_flat_background")
	assert_eq(output.get_pixel(0, 0).a, 1.0)
	assert_eq(output.get_pixel(11, 11).a, 1.0)


func test_zero_tolerance_only_removes_exact_background_color() -> void:
	var image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.set_pixel(1, 1, Color(0.96, 0.96, 0.96, 1.0))
	image.set_pixel(3, 3, Color.RED)

	var result: Dictionary = Matting.matte(
		image, {"mode": Matting.MODE_FLOOD, "tolerance": 0.0, "feather": 0, "bg_color": Color.WHITE}
	)
	var output: Image = result["image"]
	assert_eq(output.get_pixel(0, 0).a, 0.0)
	assert_eq(output.get_pixel(1, 1).a, 1.0)
	assert_eq(output.get_pixel(3, 3).a, 1.0)


func _make_apple_on_white() -> Image:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in range(3, 9):
		for x in range(3, 9):
			image.set_pixel(x, y, Color.RED)
	image.set_pixel(5, 5, Color.WHITE)
	return image
