extends "res://addons/gut/test.gd"

const GridDetector := preload("res://core/pixel/grid_detector.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")


func test_detects_integer_scale_and_offset() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(16, 16), 2)
	var pseudo := FixtureGenerator.scale_bilinear(original, 4.0, Vector2(1, 2))

	var detected := GridDetector.detect(pseudo, {"prior_scale": 4.0})

	assert_almost_eq(float(detected["scale"]), 4.0, 0.25)
	assert_almost_eq(Vector2(detected["offset"]).x, 1.0, 1.0)
	assert_almost_eq(Vector2(detected["offset"]).y, 2.0, 1.0)
	assert_gte(float(detected["confidence"]), GridDetector.LOW_CONFIDENCE_THRESHOLD)


func test_detects_fractional_scale_with_prior() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(24, 16), 1)
	var pseudo := FixtureGenerator.scale_bilinear(original, 3.7)

	var detected := GridDetector.detect(pseudo, {"prior_scale": 3.7})

	assert_almost_eq(float(detected["scale"]), 3.7, 0.25)


func test_base_size_prior_limits_search_range_to_thirty_percent_window() -> void:
	var image := Image.create(320, 160, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)

	var search_range := GridDetector._resolve_search_range(image, {"base_size": 32})
	var default_range := GridDetector._resolve_search_range(image, {})

	assert_almost_eq(search_range.x, 7.0, 0.01)
	assert_almost_eq(search_range.y, 13.0, 0.01)
	assert_eq(default_range, Vector2(GridDetector.DEFAULT_MIN_LAG, GridDetector.DEFAULT_MAX_LAG))


func test_smooth_photo_like_input_reports_low_confidence() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(96, 96))

	var detected := GridDetector.detect(image)

	assert_lt(float(detected["confidence"]), GridDetector.LOW_CONFIDENCE_THRESHOLD)


func test_512_detection_finishes_within_budget() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(128, 128), 0)
	var pseudo := FixtureGenerator.scale_nearest(original, 4)

	var started := Time.get_ticks_usec()
	var detected := GridDetector.detect(pseudo, {"prior_scale": 4.0})
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	assert_almost_eq(float(detected["scale"]), 4.0, 0.25)
	assert_lt(elapsed_ms, 2000.0)


func test_24_sample_detection_matrix_meets_m1_acceptance_rate() -> void:
	var cases := _make_detection_matrix()
	var passed := 0
	var low_confidence_allowed := 0
	for item in cases:
		var detected := GridDetector.detect(item["image"], {"prior_scale": item["scale"]})
		var scale_error := (
			absf(float(detected["scale"]) - float(item["scale"])) / float(item["scale"])
		)
		var offset_error := _periodic_offset_error(
			Vector2(detected["offset"]), item["offset"], float(item["scale"])
		)
		var is_accurate := scale_error <= 0.05 and offset_error <= 1.0
		if is_accurate:
			passed += 1
		elif (
			bool(item.get("allow_low_confidence", false))
			and (float(detected["confidence"]) < GridDetector.LOW_CONFIDENCE_THRESHOLD)
		):
			low_confidence_allowed += 1

	assert_eq(cases.size(), 24)
	assert_gte(passed + low_confidence_allowed, 22)


func test_non_square_scale_divergence_is_reported_in_meta() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(16, 16), 0)
	var stretched := original.duplicate()
	stretched.resize(64, 96, Image.INTERPOLATE_NEAREST)

	var detected := GridDetector.detect(stretched)

	assert_true(bool(detected["non_square_warning"]))
	assert_gt(float(detected["non_square_ratio"]), 0.1)


func _make_detection_matrix() -> Array:
	var sizes := [
		Vector2i(16, 16),
		Vector2i(32, 16),
		Vector2i(16, 32),
		Vector2i(24, 24),
		Vector2i(32, 32),
		Vector2i(48, 32),
		Vector2i(32, 48),
		Vector2i(48, 48),
	]
	var cases := []
	for index in range(sizes.size()):
		var original := FixtureGenerator.make_checkerboard(
			sizes[index], [Color.BLACK, Color.WHITE, Color.RED, Color.BLUE], 1
		)
		(
			cases
			. append(
				{
					"image": FixtureGenerator.scale_bilinear(original, 3.7),
					"scale": 3.7,
					"offset": Vector2(1.25, 1.25),
				}
			)
		)
		(
			cases
			. append(
				{
					"image": FixtureGenerator.scale_bilinear(original, 4.0, Vector2(1, 2)),
					"scale": 4.0,
					"offset": Vector2(2, 3),
				}
			)
		)
		(
			cases
			. append(
				{
					"image":
					FixtureGenerator.jpeg_roundtrip(
						FixtureGenerator.scale_bilinear(original, 6.2), 0.85
					),
					"scale": 6.2,
					"offset": Vector2(1.25, 1.25),
					"allow_low_confidence": true,
				}
			)
		)
	return cases


func _periodic_offset_error(left: Vector2, right: Vector2, scale: float) -> float:
	return (
		Vector2(
			_periodic_axis_error(left.x, right.x, scale),
			_periodic_axis_error(left.y, right.y, scale)
		)
		. length()
	)


func _periodic_axis_error(left: float, right: float, scale: float) -> float:
	var distance := absf(left - right)
	return minf(distance, maxf(0.0, scale - distance))
