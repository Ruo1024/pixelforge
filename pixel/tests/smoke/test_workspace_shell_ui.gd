extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const Strings := preload("res://ui/shell/strings.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Workspace Shell")
	AssetLibrary.clear()


func test_workspace_groups_global_and_canvas_actions_with_three_empty_starts() -> void:
	var main := await _make_main()
	var global_actions: Control = main.get_node("Root/TopBar/GlobalActions")
	var canvas_actions: Control = main.get_node("Root/TopBar/CanvasActions")
	var hint: Control = main.get_node("Root/Content/InfiniteCanvas/EmptyCanvasImportHint")

	var global_texts := _button_texts(global_actions)
	for action_text in [
		Strings.ACTION_NEW, Strings.ACTION_OPEN, Strings.ACTION_SAVE, Strings.ACTION_EXPORT_PNG
	]:
		assert_true(global_texts.has(action_text))
	assert_true(_button_texts(canvas_actions).has(Strings.ACTION_ADD_INPUT))
	assert_true(_button_texts(canvas_actions).has(Strings.ACTION_IMPORT_REFERENCE))
	assert_true(_button_texts(canvas_actions).has(Strings.ACTION_OPEN_EXAMPLE))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/AddInput"))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/ImportReference"))
	assert_not_null(hint.get_node("EmptyContent/EmptyActions/OpenExample"))
	assert_not_null(global_actions.get_node("SettingsButton"))
	assert_not_null(main.get_node("WorkspaceSettingsController/WorkspaceSettingsDialog"))


func test_empty_add_input_creates_real_graph_atomically_and_updates_context() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var hint: Control = canvas.get_node("EmptyCanvasImportHint")
	var context: Control = main.get_node("Root/Content/ContextInspector")

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


func test_context_inspector_reuses_cleanup_for_sprite_and_batch() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var context: Control = main.get_node("Root/Content/ContextInspector")
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
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var navigation: Control = canvas.get_node("WorkspaceNavigation")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var first_id: String = AssetLibrary.register_image(image, "first", {"origin": "imported"})
	var second_id: String = AssetLibrary.register_image(image, "second", {"origin": "imported"})
	var first: Node = canvas.add_sprite_item(image, first_id, Vector2(-800, -300))
	canvas.add_sprite_item(image, second_id, Vector2(900, 500))
	await wait_process_frames(1)

	(navigation.get_node("NavigationRow/FocusAll") as Button).pressed.emit()
	await wait_process_frames(1)
	var all_center := Rect2(Vector2(-800, -300), Vector2(1732, 832)).get_center()
	assert_almost_eq(canvas.world_to_screen(all_center).x, canvas.size.x * 0.5, 1.0)
	assert_almost_eq(canvas.world_to_screen(all_center).y, canvas.size.y * 0.5, 1.0)

	canvas.select_ids([first.item_id])
	(navigation.get_node("NavigationRow/FocusSelected") as Button).pressed.emit()
	await wait_process_frames(1)
	assert_almost_eq(
		canvas.world_to_screen(first.get_canvas_bounds().get_center()).x, canvas.size.x * 0.5, 1.0
	)
	assert_almost_eq(
		canvas.world_to_screen(first.get_canvas_bounds().get_center()).y, canvas.size.y * 0.5, 1.0
	)


func test_language_switch_refreshes_workspace_chrome_and_content_modules() -> void:
	var main := await _make_main()
	var global_actions: Control = main.get_node("Root/TopBar/GlobalActions")
	var canvas_actions: Control = main.get_node("Root/TopBar/CanvasActions")
	var hint: Control = main.get_node("Root/Content/InfiniteCanvas/EmptyCanvasImportHint")

	LocalizationService.set_language("zh_CN")
	await wait_process_frames(2)

	assert_true(_button_texts(global_actions).has(Strings.text("ACTION_NEW")))
	assert_true(_button_texts(canvas_actions).has(Strings.text("ACTION_ADD_INPUT")))
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
		controller._batch_menu.get_item_text(
			controller._batch_menu.get_item_index(controller.BATCH_MENU_MARK_KEEP)
		),
		Strings.text("BATCH_ACTION_MARK_KEEP")
	)
	(hint.get_node("EmptyContent/EmptyActions/AddInput") as Button).pressed.emit()
	await wait_process_frames(2)
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var card: Node = canvas._items_by_id.values()[0]
	assert_eq(card._display_name, Strings.text("NODE_OBJECT_LIST"))
	assert_eq(SettingsService.get_setting("ui", "language", "auto"), "zh_CN")


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
