extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const Drawing := preload("res://core/editor/pixel_drawing.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func test_default_size_and_palette_are_module_owned_and_save_keeps_provenance() -> void:
	ProjectService.new_project("Editor UI")
	assert_false(ProjectService.current_project.manifest.has("style_preset"))
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	var source_id := AssetLibrary.register_image(image, "AI Source", {"origin": "generated"})
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	main._recovery_dialog.hide()
	var canvas: PFInfiniteCanvas = main._canvas
	var graph := GraphScript.new()
	graph.id = "graph-main"
	graph.add_node(
		BatchNodeScript.new(),
		"editor-output",
		{
			"label": "Repair",
			"source_node_id": "",
			"source_run_id": "",
			"role": "standalone",
			"input_snapshots": {},
			"request_records": [],
			"result_slots": [
				{
					"slot_id": "slot-editor",
					"run_id": "",
					"request_id": "",
					"source_row_id": "",
					"source_asset_id": "",
					"input_snapshot_id": "",
					"planned_size": [8, 8],
					"status": "succeeded",
					"asset_id": source_id,
					"detached": false,
					"unexpected": false,
					"error": null,
				}
			],
		},
		Vector2.ZERO,
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "editor-output", Vector2.ZERO, "editor-card", false
	)
	card._set_selected_asset_ids([source_id])
	var controller: Node = main.get_node("M21UiController")
	controller._open_pixel_editor(source_id, card.item_id)
	var editor: PFPixelEditor = controller._pixel_editor
	Drawing.stroke(editor.document.get_frame(0, 0), Vector2i.ZERO, Vector2i(7, 7), Color.WHITE)
	editor.document.dirty = true
	editor._save(false)
	var updated_params: Dictionary = (
		GraphScript.from_json(ProjectService.get_graph_data(graph.id)).get_node_params("editor-output")
	)
	var updated_slots: Array = updated_params["result_slots"]
	assert_eq(updated_slots.size(), 1)
	assert_eq(updated_slots[0]["slot_id"], "slot-editor")
	assert_ne(updated_slots[0]["asset_id"], source_id)
	assert_true(AssetLibrary.has_asset(source_id))
	var metadata := AssetLibrary.get_asset_meta(String(updated_slots[0]["asset_id"]))
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


func test_animation_preview_starts_hidden_until_requested() -> void:
	var editor := PFPixelEditor.new()
	add_child_autofree(editor)
	await wait_process_frames(1)
	assert_false(editor._preview_window.visible)
