extends "res://addons/gut/test.gd"

const Pipeline := preload("res://core/pixel/pipeline.gd")
const Quantizer := preload("res://core/pixel/quantizer.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")


func test_default_cleanup_pipeline_returns_true_pixel_asset() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(32, 32), 0)
	var pseudo := FixtureGenerator.scale_nearest(original, 4)

	var result := (
		Pipeline
		. apply(
			pseudo,
			{
				"scale": 4.0,
				"quantize": Quantizer.MODE_AUTO_K,
				"k": 8,
				"target_size": original.get_size(),
			}
		)
	)
	var output: Image = result["image"]
	var report: Dictionary = result["report"]

	assert_eq(output.get_size(), original.get_size())
	assert_lte(Quantizer.count_colors(output), 8)
	assert_eq(report["output_size"], [32, 32])
	assert_gte(float(report["detect"]["confidence"]), 1.0)


func test_manual_cleanup_honors_given_grid() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(12, 12), 2)
	var pseudo := FixtureGenerator.scale_nearest(original, 4)

	var result := (
		Pipeline
		. apply(
			pseudo,
			{
				"detect": Pipeline.DETECT_MANUAL,
				"scale": 4.0,
				"offset": Vector2.ZERO,
				"quantize": Quantizer.MODE_NONE,
			}
		)
	)

	assert_true(FixtureGenerator.similarity(result["image"], original) >= 0.99)


func test_namespaced_params_can_disable_resample_step() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(8, 8), 1)

	var result := (
		Pipeline
		. apply(
			original,
			{
				Pipeline.STEP_DETECT_GRID: {"enabled": false},
				Pipeline.STEP_RESAMPLE: {"enabled": false},
				Pipeline.STEP_QUANTIZE: {"enabled": false},
			}
		)
	)

	assert_eq(result["image"].get_size(), original.get_size())
	assert_eq(result["report"]["steps"].size(), 3)
	assert_false(result["report"]["steps"][0]["enabled"])


func test_explicit_step_order_runs_only_requested_algorithms() -> void:
	var original := FixtureGenerator.make_base_sprite(Vector2i(8, 8), 0)

	var result := (
		Pipeline
		. apply(
			original,
			{
				"steps": [Pipeline.STEP_QUANTIZE],
				Pipeline.STEP_QUANTIZE:
				{
					"mode": Quantizer.MODE_FIXED_PALETTE,
					"palette_colors": ["#000000", "#FFFFFF"],
				},
			}
		)
	)

	assert_eq(result["image"].get_size(), original.get_size())
	assert_eq(result["report"]["steps"], [{"id": Pipeline.STEP_QUANTIZE, "enabled": true}])


func test_fixed_palette_cleanup_uses_registered_custom_palette() -> void:
	PaletteRegistry.clear_custom_palettes()
	var palette := PFPalette.new(
		"sunset", "Sunset", PackedColorArray([Color8(8, 16, 24), Color8(240, 160, 80)])
	)
	var registered := PaletteRegistry.register_custom_palette(palette)
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color8(10, 18, 30))
	image.set_pixel(1, 0, Color8(230, 150, 72))

	var result := (
		Pipeline
		. apply(
			image,
			{
				"steps": [Pipeline.STEP_QUANTIZE],
				Pipeline.STEP_QUANTIZE:
				{
					"mode": Quantizer.MODE_FIXED_PALETTE,
					"palette_id": registered.id,
				},
			}
		)
	)
	var output: Image = result["image"]

	assert_eq(output.get_pixel(0, 0).to_html(false), "081018")
	assert_eq(output.get_pixel(1, 0).to_html(false), "f0a050")
	assert_eq(result["report"]["quantize"]["palette_id"], registered.id)


func test_independent_cleanup_uses_fixed_detect_prior_without_project_style() -> void:
	var normalized := Pipeline.normalize_params({})
	var detect: Dictionary = normalized[Pipeline.STEP_DETECT_GRID]

	assert_eq(int(detect["base_size"]), 32)


func test_real_ai_fixture_samples_cleanup_smoke() -> void:
	if OS.get_environment("PF_ALLOW_PROTECTED_FIXTURES") != "1":
		assert_true(true, "Protected fixture smoke is owner-opt-in and is not read by automation")
		return
	for path in [
		"res://tests/fixtures/real/real_ai_01_character.png",
		"res://tests/fixtures/real/real_ai_02_robot.png",
		"res://tests/fixtures/real/real_ai_03_hair_detail.png",
	]:
		var image := _load_png_fixture(path)
		assert_not_null(image)
		var result := (
			Pipeline
			. apply(
				image,
				{
					Pipeline.STEP_DETECT_GRID: {"base_size": 128},
					Pipeline.STEP_QUANTIZE: {"mode": Quantizer.MODE_AUTO_K, "k": 16},
				}
			)
		)
		var output: Image = result["image"]
		var report: Dictionary = result["report"]

		assert_lte(maxi(output.get_width(), output.get_height()), 320)
		assert_lte(Quantizer.count_colors(output), 16)
		assert_false(report["detect"].is_empty())


func _load_png_fixture(path: String) -> Image:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	var image := Image.new()
	var error := image.load_png_from_buffer(bytes)
	if error != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image
