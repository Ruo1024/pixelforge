extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const Drawing := preload("res://core/editor/pixel_drawing.gd")


func test_canvas_editor_entry_save_as_updates_batch_and_provenance() -> void:
	ProjectService.new_project("Editor UI")
	ProjectService.current_project.manifest["style_preset"] = {"palette": {"ref": "pico8"}}
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var source_id := AssetLibrary.register_image(image, "AI Source", {"origin": "generated"})
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	main._recovery_dialog.hide()
	var canvas: PFInfiniteCanvas = main._canvas
	var card: Node = canvas._add_batch_card(
		[source_id], Vector2.ZERO, "Repair", "editor_batch", false
	)
	var controller: Node = main.get_node("M21UiController")
	controller._open_pixel_editor(source_id, card.item_id)
	var editor: PFPixelEditor = controller._pixel_editor
	Drawing.stroke(editor.document.get_frame(0, 0), Vector2i.ZERO, Vector2i(7, 7), Color.WHITE)
	editor.document.dirty = true
	editor._save(false)
	var updated: Array = canvas._get_batch_asset_ids(card.item_id)
	assert_eq(updated.size(), 1)
	assert_ne(updated[0], source_id)
	var metadata := AssetLibrary.get_asset_meta(String(updated[0]))
	assert_eq(metadata["origin"], "edited")
	assert_eq(metadata["provenance"]["parent_asset"], source_id)
	assert_gt(Array(metadata["editor_palette"]).size(), 2)


func test_double_click_routing_emits_sprite_asset_context() -> void:
	ProjectService.new_project("Editor Double Click")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var asset_id := AssetLibrary.register_image(image, "Sprite")
	var canvas := PFInfiniteCanvas.new()
	canvas.size = Vector2(400, 300)
	add_child_autofree(canvas)
	await wait_process_frames(1)
	canvas.add_sprite_item(image, asset_id, Vector2.ZERO, "sprite_edit", false)
	watch_signals(canvas)
	assert_true(canvas._emit_asset_edit_request(canvas.world_to_screen(Vector2(1, 1))))
	assert_signal_emitted_with_parameters(canvas, "asset_edit_requested", [asset_id, ""])


func test_palette_remap_32_square_and_selection_move_stay_interactive() -> void:
	ProjectService.new_project("Editor Palette")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var asset_id := AssetLibrary.register_image(image, "Remap")
	var editor := PFPixelEditor.new()
	add_child_autofree(editor)
	await wait_process_frames(1)
	assert_true(editor.open_asset(asset_id))
	editor.hide()
	editor.document.palette = [Color.RED, Color.BLUE]
	editor._palette_index = 0
	editor._canvas.foreground = Color.BLUE
	var started := Time.get_ticks_msec()
	editor._remap_palette_color()
	assert_lt(Time.get_ticks_msec() - started, 50)
	assert_eq(editor.document.get_frame(0, 0).get_pixel(10, 10), Color.BLUE)

	editor._canvas.selection_rect = Rect2i(0, 0, 4, 4)
	editor._canvas._selection_source = editor.document.get_frame(0, 0).get_region(
		editor._canvas.selection_rect
	)
	editor._canvas._move_selection(editor.document.get_frame(0, 0), Vector2i(6, 6))
	assert_eq(editor._canvas.selection_rect.position, Vector2i(6, 6))
