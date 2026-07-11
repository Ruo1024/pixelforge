extends "res://addons/gut/test.gd"

const PixelEditorScript := preload("res://ui/editor/pixel_editor.gd")
const BoardScript := preload("res://core/board/pf_board.gd")
const BoardExporter := preload("res://services/board_exporter.gd")


func test_eight_frame_editor_animation_is_immediately_available_to_board() -> void:
	ProjectService.new_project("Editor Animation Board")
	var source := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	source.fill(Color.RED)
	var source_id := AssetLibrary.register_image(source, "Walk")
	var editor := PixelEditorScript.new()
	add_child_autofree(editor)
	await wait_process_frames(1)
	assert_true(editor.open_asset(source_id))
	editor.hide()
	for frame_index in range(1, 8):
		var index := editor.document.add_frame(frame_index - 1, 80 + frame_index)
		editor.document.get_frame(0, index).fill(Color(float(frame_index) / 8.0, 0.0, 1.0, 1.0))
	editor.document.tags = [{"name": "walk", "from": 0, "to": 7}]
	editor._save(false)
	var animations := ProjectService.get_document_data("animations")
	assert_eq(animations.size(), 1)
	var animation_id := String(animations.keys()[0])
	assert_eq(animations[animation_id]["frames"].size(), 8)
	assert_eq(animations[animation_id]["tags"], editor.document.tags)

	var board := BoardScript.new("Preview", 1, 1, 4)
	var layer := board.add_layer("Animated", PFBoard.LAYER_FREE)
	board.add_free_item(layer, "", Vector2i.ZERO, animation_id)
	var exporter := BoardExporter.new()
	var first := exporter.compose(board, AssetLibrary, animations, 0)
	var later := exporter.compose(board, AssetLibrary, animations, 200)
	assert_ne(first.get_pixel(0, 0), later.get_pixel(0, 0))
