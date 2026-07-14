extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Workspace Shell")
	AssetLibrary.clear()


func test_workspace_groups_global_and_canvas_actions_with_three_empty_starts() -> void:
	var main := await _make_main()
	var global_actions: Control = main.get_node("Root/TopBar/GlobalActions")
	var canvas_actions: Control = main.get_node("Root/TopBar/CanvasActions")
	var left_rail: Control = main.get_node("Root/Content/LeftRail")
	var hint: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas/EmptyCanvasImportHint")

	assert_true(_button_texts(global_actions).has(Strings.text("MENU_FILE")))
	assert_true(_button_texts(canvas_actions).has(Strings.text("ACTION_RUN_SELECTION")))
	assert_true(_button_texts(canvas_actions).has(Strings.text("ACTION_EXPORT")))
	assert_not_null(left_rail.get_node("AddInput"))
	assert_not_null(left_rail.get_node("ImportReference"))
	assert_not_null(left_rail.get_node("Library"))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/AddInput"))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/ImportReference"))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/OpenExample"))
	assert_not_null(canvas_actions.get_node("SettingsButton"))
	assert_not_null(main.get_node("WorkspaceSettingsController/WorkspaceSettingsDialog"))


func test_empty_add_input_creates_real_graph_atomically_and_updates_context() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var hint: Control = canvas.get_node("EmptyCanvasImportHint")
	var context: Control = main.get_node("Root/Content/Workspace/ContextInspector")

	(hint.get_node("EmptyContent/EmptyActions/AddInput") as Button).pressed.emit()
	await wait_process_frames(2)

	assert_eq(canvas.get_item_count(), 1)
	assert_eq(ProjectService.current_project.graphs.size(), 1)
	var graph_data: Dictionary = ProjectService.current_project.graphs.values()[0]
	assert_eq(graph_data["nodes"].size(), 1)
	assert_eq(graph_data["nodes"][0]["type"], "object_list")
	assert_false(hint.visible)
	assert_eq(context.get_node("ContextRoot/GraphSummary/NodeType").text, "object_list")
	assert_false(context.get_node("ContextRoot/CleanupInspector").visible)

	assert_true(UndoService.undo())
	await wait_process_frames(1)
	assert_eq(canvas.get_item_count(), 0)
	assert_true(ProjectService.current_project.graphs.is_empty())
	assert_true(hint.visible)


func test_empty_reference_import_creates_real_node_and_undo_keeps_asset() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var flow: Node = main.get_node("M21UiController/ImportFlowController")
	var image := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.DARK_ORANGE)
	var path := "user://tests/workspace_reference.png"
	assert_eq(image.save_png(path), OK)
	var result: Dictionary = flow._import_reference_file(path, {"mode": "workspace"})
	assert_true(result["ok"])
	var asset_id := String(result["asset_id"])
	assert_true(AssetLibrary.has_asset(asset_id))
	assert_eq(ProjectService.current_project.graphs.size(), 1)
	var graph: Dictionary = ProjectService.current_project.graphs.values()[0]
	assert_eq(graph["nodes"][0]["type"], "image_input")
	assert_eq(graph["nodes"][0]["params"]["asset_id"], asset_id)
	assert_eq(canvas.get_item_count(), 1)
	UndoService.undo()
	assert_eq(ProjectService.current_project.graphs.size(), 0)
	assert_eq(canvas.get_item_count(), 0)
	assert_true(AssetLibrary.has_asset(asset_id))
	UndoService.redo()
	assert_eq(ProjectService.current_project.graphs.size(), 1)
	assert_eq(canvas.get_item_count(), 1)


func test_blank_workspace_can_build_and_run_reference_to_result_chain() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var hint: Control = canvas.get_node("EmptyCanvasImportHint")
	var controller: Node = main.get_node("M21UiController")
	(hint.get_node("EmptyContent/EmptyActions/AddInput") as Button).pressed.emit()
	await wait_process_frames(2)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var object_node_id := String(ProjectService.current_project.graphs[graph_id]["nodes"][0]["id"])
	assert_true(
		(
			controller
			. apply_graph_node_params(
				graph_id,
				object_node_id,
				{
					"rows":
					[
						{"id": "barrel", "text": "barrel", "count": 3, "enabled": true},
						{"id": "crate", "text": "crate", "count": 3, "enabled": true},
						{"id": "lantern", "text": "lantern", "count": 3, "enabled": true},
					]
				}
			)
		)
	)
	var reference_node_id: String = controller.add_graph_node_to_selected_graph("image_input")
	var generate_node_id: String = controller.add_graph_node_to_selected_graph("ai_generate")
	var batch_node_id: String = controller.add_graph_node_to_selected_graph("batch")
	for node_id in [reference_node_id, generate_node_id, batch_node_id]:
		assert_false(String(node_id).is_empty())

	var reference := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	reference.fill(Color.DARK_ORANGE)
	var reference_asset_id := AssetLibrary.register_image(
		reference, "blank_reference", {"origin": "imported"}
	)
	assert_true(
		controller.apply_graph_node_params(
			graph_id, reference_node_id, {"asset_id": reference_asset_id}
		)
	)
	assert_true(
		(
			controller
			. apply_graph_node_params(
				graph_id,
				generate_node_id,
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 3,
					"seed": 42,
					"extra": {},
				}
			)
		)
	)

	var graph := GraphScript.from_json(ProjectService.get_graph_data(graph_id))
	assert_true(graph.add_edge(object_node_id, "subjects", generate_node_id, "subjects")["ok"])
	assert_true(graph.add_edge(reference_node_id, "assets", generate_node_id, "references")["ok"])
	assert_true(graph.add_edge(generate_node_id, "assets", batch_node_id, "in")["ok"])
	ProjectService.set_graph_data(graph_id, graph.to_json(), true)
	var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], batch_node_id)
	canvas.select_ids([batch_item_id])
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	var saved_graph: Dictionary = ProjectService.get_graph_data(graph_id)
	var old_batch_params: Dictionary = _node_data(saved_graph, batch_node_id)["params"]
	var output_node: Dictionary = _current_output_for_source(saved_graph, generate_node_id)
	var output_node_id := String(output_node["id"])
	var output_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], output_node_id)
	var result_asset_ids: Array = canvas._get_batch_asset_ids(output_item_id)
	assert_eq(result_asset_ids.size(), 9)
	var saved_batch_params: Dictionary = output_node["params"]
	assert_eq(old_batch_params["result_slots"], [])
	assert_false(saved_batch_params.has("asset_ids"))
	assert_false(saved_batch_params.has("review_states"))
	assert_eq(saved_batch_params["result_slots"].size(), 9)
	var first_result_id := String(saved_batch_params["result_slots"][0]["asset_id"])
	var first_snapshot: Dictionary = (
		AssetLibrary.get_asset_meta(first_result_id)["provenance"]["generation_snapshot"]
	)
	assert_eq(first_snapshot["reference_asset_ids"], [reference_asset_id])
	var generate_item_id: String = _item_id_for_node(
		canvas.export_canvas_data()["items"], generate_node_id
	)
	assert_true(canvas._set_graph_node_collapsed(generate_item_id, true, false))
	assert_true(canvas._set_batch_collapsed(output_item_id, true, false))
	var roundtrip_path := "user://tests/beta02_blank_chain_roundtrip.pxproj"
	assert_eq(ProjectService.save_project(roundtrip_path), OK)
	assert_eq(ProjectService.open_project(roundtrip_path), OK)
	var loaded_graph: Dictionary = ProjectService.get_graph_data(graph_id)
	var loaded_batch_params: Dictionary = _node_data(loaded_graph, output_node_id)["params"]
	assert_false(loaded_batch_params.has("asset_ids"))
	assert_false(loaded_batch_params.has("review_states"))
	assert_eq(_visible_asset_ids(loaded_batch_params), result_asset_ids)
	var loaded_canvas_items: Array = ProjectService.current_project.canvas["items"]
	assert_true(_item_data_for_node(loaded_canvas_items, generate_node_id)["collapsed"])
	assert_true(_item_data_for_node(loaded_canvas_items, output_node_id)["collapsed"])


func test_offline_example_is_one_undoable_reference_to_batch_workspace() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var controller: Node = main.get_node("M21UiController")
	controller.generate_mock_batch()
	await wait_process_frames(2)
	assert_eq(canvas.get_item_count(), 5)
	var graph: Dictionary = ProjectService.current_project.graphs.values()[0]
	assert_eq(_node_type(graph, "reference"), "image_input")
	assert_true(_has_edge(graph, "reference", "assets", "generate", "references"))
	var reference_id := String(_node_data(graph, "reference")["params"]["asset_id"])
	assert_true(AssetLibrary.has_asset(reference_id))

	assert_true(UndoService.undo())
	assert_eq(canvas.get_item_count(), 0)
	assert_true(ProjectService.current_project.graphs.is_empty())
	assert_true(AssetLibrary.has_asset(reference_id))
	assert_true(UndoService.redo())
	assert_eq(canvas.get_item_count(), 5)
	assert_eq(ProjectService.current_project.graphs.size(), 1)


func test_context_inspector_reuses_cleanup_for_sprite_and_batch() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var context: Control = main.get_node("Root/Content/Workspace/ContextInspector")
	var cleanup: Control = context.get_node("ContextRoot/CleanupInspector")
	var image := Image.create(24, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var asset_id: String = AssetLibrary.register_image(image, "reference", {"origin": "imported"})

	canvas.add_sprite_item(image, asset_id, Vector2.ZERO)
	await wait_process_frames(1)
	assert_true(cleanup.visible)
	assert_eq(context.get_node("ContextRoot/ContextTitle").text, "reference")

	var controller: Node = main.get_node("M21UiController")
	controller.generate_mock_batch()
	await wait_process_frames(2)
	assert_true(cleanup.visible)
	assert_eq(context.get_node("ContextRoot/GraphSummary").visible, false)


func test_navigation_buttons_focus_selected_and_all_canvas_content() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var navigation: Control = canvas.get_node("WorkspaceNavigation")
	var minimap: Control = canvas.get_node("CanvasMinimap")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var first_id: String = AssetLibrary.register_image(image, "first", {"origin": "imported"})
	var second_id: String = AssetLibrary.register_image(image, "second", {"origin": "imported"})
	var first: Node = canvas.add_sprite_item(image, first_id, Vector2(-800, -300))
	var second: Node = canvas.add_sprite_item(image, second_id, Vector2(900, 500))
	await wait_process_frames(1)
	assert_true(minimap.visible)
	(navigation.get_node("NavigationRow/ToggleMinimap") as Button).pressed.emit()
	assert_false(minimap.visible)
	(navigation.get_node("NavigationRow/ToggleMinimap") as Button).pressed.emit()
	assert_true(minimap.visible)

	(navigation.get_node("NavigationRow/FocusAll") as Button).pressed.emit()
	await wait_process_frames(1)
	var all_center: Vector2 = (
		first.get_canvas_bounds().merge(second.get_canvas_bounds()).get_center()
	)
	assert_almost_eq(canvas.world_to_screen(all_center).x, canvas.size.x * 0.5, 1.0)
	assert_almost_eq(canvas.world_to_screen(all_center).y, canvas.size.y * 0.5, 1.0)
	var minimap_target := Vector2(900, 500)
	var map_position: Vector2 = minimap.world_to_map(
		minimap_target, minimap._content_bounds, minimap.get_map_rect()
	)
	minimap._request_world_center(map_position)
	assert_almost_eq(canvas.camera_center.x, minimap_target.x, 1.0)
	assert_almost_eq(canvas.camera_center.y, minimap_target.y, 1.0)

	canvas.select_ids([first.item_id])
	(navigation.get_node("NavigationRow/FocusSelected") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_almost_eq(
		canvas.world_to_screen(first.get_canvas_bounds().get_center()).x, canvas.size.x * 0.5, 1.0
	)
	assert_almost_eq(
		canvas.world_to_screen(first.get_canvas_bounds().get_center()).y, canvas.size.y * 0.5, 1.0
	)
	canvas.pan_by_pixels(Vector2(500, 300))
	var fit_event := InputEventKey.new()
	fit_event.keycode = KEY_0
	fit_event.pressed = true
	fit_event.meta_pressed = true
	canvas._unhandled_key_input(fit_event)
	assert_almost_eq(canvas.world_to_screen(all_center).x, canvas.size.x * 0.5, 1.0)
	assert_almost_eq(canvas.world_to_screen(all_center).y, canvas.size.y * 0.5, 1.0)


func test_language_switch_refreshes_workspace_chrome_and_content_modules() -> void:
	var main := await _make_main()
	var global_actions: Control = main.get_node("Root/TopBar/GlobalActions")
	var canvas_actions: Control = main.get_node("Root/TopBar/CanvasActions")
	var hint: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas/EmptyCanvasImportHint")

	LocalizationService.set_language("zh_CN")
	await wait_process_frames(2)

	assert_true(_button_texts(global_actions).has(Strings.text("MENU_FILE")))
	assert_true(_button_texts(canvas_actions).has(Strings.text("ACTION_RUN_SELECTION")))
	assert_eq(
		hint.get_node("EmptyContent/HintLabel").text, Strings.text("EMPTY_CANVAS_IMPORT_HINT")
	)
	var controller: Node = main.get_node("M21UiController")
	var file_menu: MenuButton = null
	for child in global_actions.get_children():
		if child is MenuButton:
			file_menu = child
			break
	assert_not_null(file_menu)
	assert_eq(file_menu.text, Strings.text("MENU_FILE"))
	assert_eq(
		file_menu.get_popup().get_item_text(
			file_menu.get_popup().get_item_index(controller.FILE_MENU_IMPORT_IMAGES)
		),
		Strings.text("MENU_IMPORT_IMAGES")
	)
	assert_eq(
		file_menu.get_popup().get_item_text(controller._graph_add_parent_index),
		Strings.text("MENU_ADD_GRAPH_NODE")
	)
	assert_eq(
		controller._batch_menu.get_item_text(
			controller._batch_menu.get_item_index(controller.BATCH_MENU_MARK_KEEP)
		),
		Strings.text("BATCH_ACTION_MARK_KEEP")
	)
	var graph_menu_texts := []
	for index in range(controller._graph_add_menu.item_count):
		graph_menu_texts.append(controller._graph_add_menu.get_item_text(index))
	assert_has(graph_menu_texts, Strings.text("NODE_BATCH"))
	assert_has(graph_menu_texts, Strings.text("NODE_AI_GENERATE"))
	assert_false(graph_menu_texts.has("AI Generate"))
	assert_eq(
		main.get_node("M21UiController/ImportImagesDialog").title,
		Strings.text("DIALOG_IMPORT_IMAGES")
	)
	assert_eq(main.get_node("ExportDialog").title, Strings.text("DIALOG_EXPORT_PNG"))
	var settings_dialog: ConfirmationDialog = main.get_node(
		"WorkspaceSettingsController/WorkspaceSettingsDialog"
	)
	assert_eq(settings_dialog.get_ok_button().text, Strings.text("ACTION_OK"))
	assert_eq(settings_dialog.get_cancel_button().text, Strings.text("ACTION_CANCEL"))
	var onboarding: ConfirmationDialog = main.get_node("M21UiController/V1OnboardingDialog")
	assert_eq(onboarding.title, Strings.text("ONBOARDING_TITLE"))
	assert_eq(onboarding.get_ok_button().text, Strings.text("ONBOARDING_START"))
	var unsaved: ConfirmationDialog = main.get_node("ProjectLifecycleGuard/UnsavedChangesDialog")
	assert_eq(unsaved.title, Strings.text("DIALOG_UNSAVED_TITLE"))
	assert_eq(unsaved.get_cancel_button().text, Strings.text("ACTION_CANCEL"))
	(hint.get_node("EmptyContent/EmptyActions/AddInput") as Button).pressed.emit()
	await wait_process_frames(2)
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var card: Node = canvas._items_by_id.values()[0]
	assert_eq(card._display_name, Strings.text("NODE_OBJECT_LIST"))
	assert_eq(SettingsService.get_setting("ui", "language", "auto"), "zh_CN")
	controller.generate_mock_batch()
	await wait_process_frames(2)
	var cleanup: Control = main.get_node(
		"Root/Content/Workspace/ContextInspector/ContextRoot/CleanupInspector"
	)
	assert_eq(cleanup.find_child("CleanupTitle", true, false).text, Strings.text("CLEANUP_TITLE"))
	assert_eq(
		cleanup.find_child("AutoDetectCheck", true, false).text, Strings.text("CLEANUP_AUTO_DETECT")
	)
	assert_eq(
		cleanup.find_child("ResampleOptions", true, false).get_item_text(0),
		Strings.text("CLEANUP_RESAMPLE_MODE")
	)
	controller._m2_actions.batch_cleanup("", [], {})
	assert_eq(
		(main.get_node("Root/BottomBar").get_child(0) as Label).text,
		Strings.text("STATUS_CLEANUP_EMPTY")
	)


func _make_main() -> Control:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	return main


func _button_texts(parent: Control) -> Array:
	var result := []
	for child in parent.get_children():
		if child is Button:
			result.append(child.text)
	return result


func _node_data(graph: Dictionary, node_id: String) -> Dictionary:
	for node_value in graph.get("nodes", []):
		if node_value is Dictionary and String(node_value.get("id", "")) == node_id:
			return node_value
	return {}


func _node_type(graph: Dictionary, node_id: String) -> String:
	return String(_node_data(graph, node_id).get("type", ""))


func _current_output_for_source(graph: Dictionary, source_node_id: String) -> Dictionary:
	for node_value in graph.get("nodes", []):
		if not (node_value is Dictionary):
			continue
		var node: Dictionary = node_value
		if String(node.get("type", "")) != "batch":
			continue
		var params: Dictionary = node.get("params", {})
		if (
			String(params.get("source_node_id", "")) == source_node_id
			and String(params.get("role", "")) == "current"
		):
			return node
	return {}


func _item_id_for_node(items: Array, node_id: String) -> String:
	for item_value in items:
		var item: Dictionary = item_value
		if String(item.get("node_id", "")) == node_id:
			return String(item.get("id", ""))
	return ""


func _item_data_for_node(items: Array, node_id: String) -> Dictionary:
	for item_value in items:
		var item: Dictionary = item_value
		if String(item.get("node_id", "")) == node_id:
			return item
	return {}


func _visible_asset_ids(batch_params: Dictionary) -> Array:
	var result := []
	for raw_slot in batch_params.get("result_slots", []):
		if not (raw_slot is Dictionary):
			continue
		var slot: Dictionary = raw_slot
		if String(slot.get("status", "")) != "succeeded" or bool(slot.get("detached", false)):
			continue
		var asset_id := String(slot.get("asset_id", ""))
		if not asset_id.is_empty():
			result.append(asset_id)
	return result


func _has_edge(
	graph: Dictionary, from_node: String, from_port: String, to_node: String, to_port: String
) -> bool:
	for edge_value in graph.get("edges", []):
		var edge: Dictionary = edge_value
		if (
			edge.get("from", []) == [from_node, from_port]
			and edge.get("to", []) == [to_node, to_port]
		):
			return true
	return false
