extends "res://addons/gut/test.gd"

const BoardScript := preload("res://core/board/pf_board.gd")
const ExporterScript := preload("res://services/board_exporter.gd")
const AnimationScript := preload("res://core/animation/pf_animation.gd")


func before_each() -> void:
	AssetLibrary.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/board"))


func test_add_layer_composite_and_layer_exports_match_expected_pixels() -> void:
	var red := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var green := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	green.fill(Color(0.0, 1.0, 0.0, 1.0))
	var red_id := AssetLibrary.register_image(red, "red")
	var green_id := AssetLibrary.register_image(green, "green")
	var board := BoardScript.new("Blend", 1, 1, 1)
	var base := board.add_layer("Base", PFBoard.LAYER_TILE)
	var glow := board.add_layer("Glow", PFBoard.LAYER_FREE)
	board.set_cell(base, Vector2i.ZERO, red_id)
	board.add_free_item(glow, green_id, Vector2i.ZERO)
	board.set_layer_visuals(glow, true, 1.0, "add")
	assert_eq(board.get_layer(glow)["items"].size(), 1)

	var exporter := ExporterScript.new()
	var image := exporter.compose(board, AssetLibrary)
	assert_not_null(image)
	assert_almost_eq(image.get_pixel(0, 0).r, 1.0, 1.0 / 255.0)
	assert_almost_eq(image.get_pixel(0, 0).g, 1.0, 1.0 / 255.0)
	var result := exporter.export_layers(
		board, ProjectSettings.globalize_path("user://tests/board/layers"), AssetLibrary
	)
	assert_true(result["ok"])
	assert_eq(result["files"].size(), 3)


func test_ten_thousand_tile_board_composes_under_export_budget() -> void:
	var tile := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tile.fill(Color(0.2, 0.4, 0.8, 1.0))
	var asset_id := AssetLibrary.register_image(tile, "tile")
	var board := BoardScript.new("Large", 100, 100, 16)
	var layer_id := board.add_layer("Terrain", PFBoard.LAYER_TILE)
	for y in range(100):
		for x in range(100):
			board.set_cell(layer_id, Vector2i(x, y), asset_id)
	var started := Time.get_ticks_msec()
	var image := ExporterScript.new().compose(board, AssetLibrary)
	var elapsed := Time.get_ticks_msec() - started
	assert_not_null(image)
	assert_eq(image.get_size(), Vector2i(1600, 1600))
	assert_lt(elapsed, 15000)


func test_twenty_offset_animations_and_frame_exports_are_deterministic() -> void:
	var red := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	red.fill(Color(1, 0, 0, 1))
	var blue := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blue.fill(Color(0, 0, 1, 1))
	var red_id := AssetLibrary.register_image(red, "red_frame")
	var blue_id := AssetLibrary.register_image(blue, "blue_frame")
	var animation := AnimationScript.new("Flame")
	animation.configure([red_id, blue_id], [100, 100], true)
	var animations := {animation.id: animation.to_json()}
	var board := BoardScript.new("VFX", 20, 1, 1)
	var layer_id := board.add_layer("VFX", PFBoard.LAYER_FREE)
	for x in range(20):
		board.add_free_item(layer_id, red_id, Vector2i(x, 0), animation.id, 100 if x % 2 else 0)
	var exporter := ExporterScript.new()
	var at_zero := exporter.compose(board, AssetLibrary, animations, 0)
	assert_eq(at_zero.get_pixel(0, 0), Color(1, 0, 0, 1))
	assert_eq(at_zero.get_pixel(1, 0), Color(0, 0, 1, 1))
	var frames := exporter.export_animation_frames(
		board,
		ProjectSettings.globalize_path("user://tests/board/frames"),
		AssetLibrary,
		animations,
		[0, 100]
	)
	assert_true(frames["ok"])
	assert_eq(frames["files"].size(), 2)
	var guide := exporter.export_godot_guide(
		board, ProjectSettings.globalize_path("user://tests/board/godot"), at_zero
	)
	assert_true(guide["ok"])
