extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")


func test_board_editor_entry_uses_fixed_module_defaults_and_places_asset() -> void:
	ProjectService.new_project("Board UI")
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.2, 1.0))
	var asset_id := AssetLibrary.register_image(image, "Grass", {"palette_ref": "pico8"})
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var editor: ConfirmationDialog = controller._board_editor
	editor._load_or_create_board()
	await wait_process_frames(1)
	assert_eq(editor.get_board().grid["tile_size"], 16)
	assert_eq(editor.get_board().layers.size(), 3)
	var board_canvas: PFBoardCanvas = editor.get_board_canvas()
	board_canvas.selected_layer_id = String(editor.get_board().layers[0]["id"])
	board_canvas.set_selected_asset(asset_id)
	assert_string_contains(editor._status.text, "Palette mismatch")
	board_canvas._place_at(board_canvas.camera_offset + Vector2(12, 12), false)
	assert_eq(editor.get_board().get_layer(board_canvas.selected_layer_id)["cells"].size(), 1)
	assert_eq(ProjectService.get_document_data("boards").size(), 1)
