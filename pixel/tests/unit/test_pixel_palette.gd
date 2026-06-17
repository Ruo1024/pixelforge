extends "res://addons/gut/test.gd"

const PaletteScript := preload("res://core/pixel/palette.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const FixtureGenerator := preload("res://tests/fixtures/generators/pixel_fixture_generator.gd")


func before_each() -> void:
	PaletteRegistry.clear_custom_palettes()


func test_builtin_palettes_load_with_contract_counts() -> void:
	for palette_id in PaletteScript.BUILTIN_IDS:
		var palette: PFPalette = PaletteScript.load_builtin(palette_id)
		assert_not_null(palette)
		assert_eq(palette.id, palette_id)
		assert_gte(palette.get_color_count(), 2)
		assert_lte(palette.get_color_count(), 256)


func test_map_image_uses_exact_palette_colors() -> void:
	var palette: PFPalette = PaletteScript.load_builtin("db32")
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, PaletteScript.hex_to_color("#222034"))
	image.set_pixel(1, 0, PaletteScript.hex_to_color("#5FCDE4"))
	image.set_pixel(0, 1, PaletteScript.hex_to_color("#D95763"))
	image.set_pixel(1, 1, PaletteScript.hex_to_color("#8A6F30"))

	var mapped := PaletteScript.map_image(image, palette, PaletteScript.DISTANCE_OKLAB)

	assert_eq(mapped.get_pixel(0, 0).to_html(false), "222034")
	assert_eq(mapped.get_pixel(1, 0).to_html(false), "5fcde4")
	assert_eq(mapped.get_pixel(0, 1).to_html(false), "d95763")
	assert_eq(mapped.get_pixel(1, 1).to_html(false), "8a6f30")


func test_rgb_and_oklab_nearest_color_boundaries() -> void:
	var colors := PackedColorArray([Color.BLACK, Color.WHITE, Color.RED, Color.BLUE])
	var palette := PFPalette.new("test", "Test", colors)

	assert_eq(
		palette.nearest_color(Color(0.03, 0.02, 0.04), PaletteScript.DISTANCE_RGB), Color.BLACK
	)
	assert_eq(
		palette.nearest_color(Color(0.95, 0.95, 0.90), PaletteScript.DISTANCE_RGB), Color.WHITE
	)
	assert_eq(
		palette.nearest_color(Color(0.90, 0.05, 0.08), PaletteScript.DISTANCE_OKLAB), Color.RED
	)
	assert_eq(
		palette.nearest_color(Color(0.05, 0.07, 0.95), PaletteScript.DISTANCE_OKLAB), Color.BLUE
	)


func test_extract_palette_keeps_pure_and_two_color_images_exact() -> void:
	var pure := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pure.fill(Color8(12, 34, 56))
	var pure_palette := PaletteScript.extract_palette(pure, 4)
	assert_eq(pure_palette.get_color_count(), 1)
	assert_eq(pure_palette.colors[0].to_html(false), "0c2238")

	var checker := FixtureGenerator.make_checkerboard(
		Vector2i(8, 8), [Color8(10, 20, 30), Color8(220, 230, 240)]
	)
	var checker_palette := PaletteScript.extract_palette(checker, 4)
	assert_eq(checker_palette.get_color_count(), 2)
	assert_true(_palette_has(checker_palette, "0a141e"))
	assert_true(_palette_has(checker_palette, "dce6f0"))


func test_custom_palette_can_be_resolved_from_hex_values() -> void:
	var palette := (
		PaletteRegistry
		. resolve(
			{
				"palette_id": "user_soft",
				"palette_name": "User Soft",
				"palette_colors": ["#112233", "#DDEEFF"],
			}
		)
	)

	assert_not_null(palette)
	assert_eq(palette.id, "user_soft")
	assert_eq(palette.get_color_count(), 2)
	assert_eq(palette.colors[1].to_html(false), "ddeeff")


func test_custom_palette_import_registers_palette_from_json() -> void:
	var result := PaletteRegistry.parse_palette_text(
		'{"id":"farm","name":"Farm","colors":["#101820","FEE715"]}', "inline"
	)
	assert_true(bool(result["ok"]))

	var registered := PaletteRegistry.register_custom_palette(result["palette"])
	var resolved := PaletteRegistry.resolve({"palette_id": registered.id})

	assert_true(PaletteRegistry.is_custom_palette(registered.id))
	assert_eq(resolved.id, registered.id)
	assert_eq(resolved.get_color_count(), 2)
	assert_eq(resolved.colors[1].to_html(false), "fee715")


func test_invalid_custom_palette_reports_reason_and_does_not_pollute_registry() -> void:
	var result := PaletteRegistry.parse_palette_text(
		'{"id":"bad","name":"Bad","colors":["#000000","not-a-color"]}', "inline"
	)

	assert_false(bool(result["ok"]))
	assert_true(String(result["error"]).contains("colors[1]"))
	assert_eq(PaletteRegistry.get_custom_ids().size(), 0)


func test_cached_map_image_handles_repeated_512_image_quickly() -> void:
	var palette: PFPalette = PaletteScript.load_builtin("db32")
	var image := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color8(91, 110, 225))

	var started := Time.get_ticks_usec()
	var mapped := PaletteScript.map_image(image, palette)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0

	assert_eq(mapped.get_size(), image.get_size())
	assert_lt(elapsed_ms, 1000.0)


func _palette_has(palette: PFPalette, hex_text: String) -> bool:
	for color in palette.colors:
		if color.to_html(false) == hex_text:
			return true
	return false
