extends "res://addons/gut/test.gd"

const Resampler := preload("res://core/pixel/resampler.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")


func test_nearest_scaled_images_resample_back_to_original() -> void:
	for variant in range(3):
		var original := FixtureGenerator.make_base_sprite(Vector2i(16 + variant * 8, 16), variant)
		var scaled := FixtureGenerator.scale_nearest(original, 4)
		var output := Resampler.resample(scaled, {"scale": 4.0, "mode": Resampler.MODE_MODE})

		assert_true(_images_equal(output, original))


func test_mode_resampling_survives_center_noise_better_than_center_strategy() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(16, 16), 1)
	var scaled := FixtureGenerator.scale_nearest(original, 4)
	var noisy := FixtureGenerator.add_cell_center_noise(scaled, 4, 0.10)

	var mode_output := Resampler.resample(noisy, {"scale": 4.0, "mode": Resampler.MODE_MODE})
	var center_output := Resampler.resample(noisy, {"scale": 4.0, "mode": Resampler.MODE_CENTER})

	assert_gte(FixtureGenerator.similarity(mode_output, original), 0.99)
	assert_lt(
		FixtureGenerator.similarity(center_output, original),
		FixtureGenerator.similarity(mode_output, original)
	)


func test_transparent_pixels_vote_in_their_own_bucket() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 0, 0, 1))
	for y in range(3):
		for x in range(3):
			image.set_pixel(x, y, Color(0, 0, 0, 0.1))

	var output := Resampler.resample(image, {"scale": 4.0, "mode": Resampler.MODE_MODE})

	assert_eq(output.get_pixel(0, 0).a, 0.0)


func test_edge_aware_preserves_center_line_when_mode_would_choose_background() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(2, 2, Color.WHITE)

	var mode_output := Resampler.resample(image, {"scale": 4.0, "mode": Resampler.MODE_MODE})
	var edge_output := Resampler.resample(image, {"scale": 4.0, "mode": Resampler.MODE_EDGE_AWARE})

	assert_eq(mode_output.get_pixel(0, 0), Color.BLACK)
	assert_eq(edge_output.get_pixel(0, 0), Color.WHITE)


func test_edge_aware_matches_mode_when_cell_contrast_is_below_threshold() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color8(100, 100, 100))
	image.set_pixel(2, 2, Color8(108, 108, 108))

	var mode_output := Resampler.resample(image, {"scale": 4.0, "mode": Resampler.MODE_MODE})
	var edge_output := (
		Resampler
		. resample(
			image,
			{
				"scale": 4.0,
				"mode": Resampler.MODE_EDGE_AWARE,
				"edge_threshold": 0.2,
			}
		)
	)

	assert_eq(
		edge_output.get_pixel(0, 0).to_html(false), mode_output.get_pixel(0, 0).to_html(false)
	)


func _images_equal(left: Image, right: Image) -> bool:
	if left.get_size() != right.get_size():
		return false
	for y in range(left.get_height()):
		for x in range(left.get_width()):
			if left.get_pixel(x, y).to_html(true) != right.get_pixel(x, y).to_html(true):
				return false
	return true
