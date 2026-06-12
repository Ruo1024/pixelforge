extends "res://addons/gut/test.gd"

const Quantizer := preload("res://core/pixel/quantizer.gd")
const Ditherer := preload("res://core/pixel/ditherer.gd")
const PaletteScript := preload("res://core/pixel/palette.gd")
const ColorSpace := preload("res://core/pixel/color_space.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")


func test_fixed_palette_bayer4_outputs_two_color_periodic_pattern() -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var result := (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_FIXED_PALETTE,
				"palette_id": "bw_2",
				"dither": Ditherer.MODE_BAYER4,
				"dither_strength": 1.0,
			}
		)
	)
	var output: Image = result["image"]

	assert_lte(Quantizer.count_colors(output), 2)
	for y in range(16):
		for x in range(16):
			assert_eq(
				output.get_pixel(x, y).to_html(false), output.get_pixel(x % 4, y % 4).to_html(false)
			)


func test_auto_k_quantization_limits_color_count() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(32, 8))
	var result := Quantizer.quantize(image, {"mode": Quantizer.MODE_AUTO_K, "k": 4})

	assert_lte(int(result["color_count"]), 4)


func test_auto_k_kmeans_error_is_not_worse_than_median_cut() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(64, 32))
	var median_output: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_AUTO_K,
				"k": 32,
				"auto_k_strategy": Quantizer.AUTO_K_STRATEGY_MEDIAN_CUT,
			}
		)["image"]
	)
	var kmeans_output: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_AUTO_K,
				"k": 32,
				"auto_k_strategy": Quantizer.AUTO_K_STRATEGY_KMEANS,
			}
		)["image"]
	)

	assert_lte(_oklab_mse(image, kmeans_output), _oklab_mse(image, median_output))


func test_auto_k_invalid_strategy_falls_back_to_median_cut() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(32, 16))
	var median_output: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_AUTO_K,
				"k": 8,
				"auto_k_strategy": Quantizer.AUTO_K_STRATEGY_MEDIAN_CUT,
			}
		)["image"]
	)
	var invalid_output: Image = (
		Quantizer
		. quantize(image, {"mode": Quantizer.MODE_AUTO_K, "k": 8, "auto_k_strategy": "surprise_me"})["image"]
	)

	assert_true(_images_equal(median_output, invalid_output))


func test_auto_k_kmeans_is_deterministic() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(48, 24))
	var params := {
		"mode": Quantizer.MODE_AUTO_K,
		"k": 16,
		"auto_k_strategy": Quantizer.AUTO_K_STRATEGY_KMEANS,
	}
	var first: Image = Quantizer.quantize(image, params)["image"]
	var second: Image = Quantizer.quantize(image, params)["image"]
	var third: Image = Quantizer.quantize(image, params)["image"]

	assert_true(_images_equal(first, second))
	assert_true(_images_equal(first, third))


func test_auto_k_kmeans_512_finishes_within_budget() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(512, 512))

	var started := Time.get_ticks_usec()
	var result := (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_AUTO_K,
				"k": 32,
				"auto_k_strategy": Quantizer.AUTO_K_STRATEGY_KMEANS,
			}
		)
	)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	# 计划口径 1.5s，自动化环境放宽 2 倍；本地可 PF_PERF_STRICT=1 启用严格预算。
	var budget_ms := 1500.0 if OS.get_environment("PF_PERF_STRICT") == "1" else 3000.0
	gut.p("kmeans 512x512 k=32 elapsed_ms=%.2f budget_ms=%.0f" % [elapsed_ms, budget_ms])
	assert_lte(int(result["color_count"]), 32)
	assert_lt(elapsed_ms, budget_ms)


func test_strength_zero_matches_no_dither() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(16, 16))
	var no_dither: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_FIXED_PALETTE,
				"palette_id": "bw_2",
				"dither": Ditherer.MODE_NONE
			}
		)["image"]
	)
	var zero_strength: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_FIXED_PALETTE,
				"palette_id": "bw_2",
				"dither": Ditherer.MODE_BAYER8,
				"dither_strength": 0.0,
			}
		)["image"]
	)

	assert_true(_images_equal(no_dither, zero_strength))


func test_fixed_palette_accepts_custom_palette_colors() -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color8(250, 10, 10))
	image.set_pixel(1, 0, Color8(10, 250, 10))

	var output: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_FIXED_PALETTE,
				"palette_colors": ["#FF0000", "#00FF00"],
			}
		)["image"]
	)

	assert_eq(output.get_pixel(0, 0).to_html(false), "ff0000")
	assert_eq(output.get_pixel(1, 0).to_html(false), "00ff00")


func test_chromatic_dither_keeps_palette_constraint() -> void:
	var image := FixtureGenerator.make_gradient(Vector2i(8, 8))
	var output: Image = (
		Quantizer
		. quantize(
			image,
			{
				"mode": Quantizer.MODE_FIXED_PALETTE,
				"palette_id": "pico8",
				"dither": Ditherer.MODE_CHROMATIC,
				"dither_strength": 0.5,
				"dither_chroma": 0.08,
				"dither_density": 0.75,
			}
		)["image"]
	)

	assert_lte(Quantizer.count_colors(output), 16)


func test_error_diffusion_uses_serpentine_scan_order() -> void:
	var image := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	var rows := [
		[0.45, 0.55, 0.65, 0.75],
		[0.45, 0.55, 0.65, 0.75],
		[0.45, 0.55, 0.65, 0.75],
	]
	for y in range(3):
		for x in range(4):
			var value := float(rows[y][x])
			image.set_pixel(x, y, Color(value, value, value, 1.0))

	var palette := PaletteScript.from_color_values(
		"bw_test", "Black White Test", [Color.BLACK, Color.WHITE]
	)
	var output := (
		Quantizer
		. quantize_to_palette(
			image,
			palette,
			{
				"dither": Ditherer.MODE_ERROR_DIFFUSION,
				"dither_strength": 1.0,
				"distance": PaletteScript.DISTANCE_RGB,
			}
		)
	)

	assert_eq(_binary_pattern(output), [0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1])


func _images_equal(left: Image, right: Image) -> bool:
	for y in range(left.get_height()):
		for x in range(left.get_width()):
			if left.get_pixel(x, y).to_html(true) != right.get_pixel(x, y).to_html(true):
				return false
	return true


func _binary_pattern(image: Image) -> Array:
	var values := []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			values.append(1 if image.get_pixel(x, y).r > 0.5 else 0)
	return values


func _oklab_mse(source: Image, quantized: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var left := ColorSpace.color_to_oklab(source.get_pixel(x, y))
			var right := ColorSpace.color_to_oklab(quantized.get_pixel(x, y))
			total += ColorSpace.oklab_distance(left, right)
			count += 1
	return total / maxf(1.0, float(count))
