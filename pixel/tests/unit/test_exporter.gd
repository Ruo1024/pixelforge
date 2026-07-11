extends "res://addons/gut/test.gd"

const Exporter := preload("res://services/exporter.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const ImageMath := preload("res://core/util/image_math.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/m2_export"))


func test_spritesheet_json_frames_match_packed_pixels() -> void:
	var red := _solid_image(Vector2i(2, 3), Color.RED)
	var blue := _solid_image(Vector2i(4, 2), Color.BLUE)
	var packed: Dictionary = (
		Exporter
		. pack_spritesheet(
			[
				{"name": "red", "image": red},
				{"name": "blue", "image": blue},
			],
			{"columns": 2, "padding": 1, "image": "sheet.png"}
		)
	)

	var sheet: Image = packed["image"]
	var atlas: Dictionary = packed["json"]
	assert_eq(sheet.get_size(), Vector2i(7, 3))
	assert_eq(atlas["frames"]["red.png"]["frame"], {"x": 0, "y": 0, "w": 2, "h": 3})
	assert_eq(atlas["frames"]["blue.png"]["frame"], {"x": 3, "y": 0, "w": 4, "h": 2})
	assert_eq(sheet.get_pixel(0, 0).to_html(false), Color.RED.to_html(false))
	assert_eq(sheet.get_pixel(3, 0).to_html(false), Color.BLUE.to_html(false))
	assert_eq(sheet.get_pixel(2, 0).a, 0.0)


func test_upscaled_png_export_keeps_original_color_set() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.BLUE)
	image.set_pixel(0, 1, Color.GREEN)
	image.set_pixel(1, 1, Color.TRANSPARENT)
	var path := "user://tests/m2_export/upscaled.png"

	assert_eq(Exporter.export_png(image, path, {"scale": 4}), OK)
	var loaded: Image = FileIOScript.load_png(path)
	assert_not_null(loaded)
	assert_eq(loaded.get_size(), Vector2i(8, 8))
	assert_eq(ImageMath.color_set(loaded), ImageMath.color_set(image))


func test_spritesheet_metadata_preserves_animation_tags() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var tags := [{"name": "walk", "from": 0, "to": 1}]
	var packed := Exporter.pack_spritesheet(
		[{"name": "a", "image": image}, {"name": "b", "image": image}], {"tags": tags}
	)
	assert_eq(packed["json"]["meta"]["frameTags"], tags)


func test_spritesheet_export_writes_png_and_json_manifest() -> void:
	var path := "user://tests/m2_export/sheet.png"
	var result: Dictionary = (
		Exporter
		. export_spritesheet(
			[
				{"name": "one", "image": _solid_image(Vector2i(2, 2), Color.YELLOW)},
				{"name": "two", "image": _solid_image(Vector2i(2, 2), Color.CYAN)},
			],
			path,
			{"columns": 1, "padding": 0}
		)
	)

	assert_true(bool(result["ok"]))
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists("user://tests/m2_export/sheet.json"))
	var parsed: Variant = FileIOScript.bytes_to_json(
		FileAccess.get_file_as_bytes("user://tests/m2_export/sheet.json")
	)
	assert_true(parsed is Dictionary)
	assert_true(Dictionary(parsed)["frames"].has("one.png"))
	assert_true(Dictionary(parsed)["frames"].has("two.png"))


func _solid_image(size: Vector2i, color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image
