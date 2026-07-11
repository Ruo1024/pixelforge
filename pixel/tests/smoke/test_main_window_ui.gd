extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const ViewportFillPolicy := preload("res://ui/shell/viewport_fill_policy.gd")
const WindowScalePolicy := preload("res://ui/shell/window_scale_policy.gd")
const Strings := preload("res://ui/shell/strings.gd")


func test_main_window_uses_readable_minimum_sizes() -> void:
	LocalizationService.set_language("en")
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var root := main.get_node("Root")
	var top_bar: Control = root.get_node("TopBar")
	var bottom_bar: Control = root.get_node("BottomBar")

	assert_eq(main.custom_minimum_size, Vector2(1080, 560))
	assert_eq(top_bar.custom_minimum_size.y, 48.0)
	assert_eq(bottom_bar.custom_minimum_size.y, 32.0)

	for child in top_bar.get_children():
		if child is Button:
			assert_gte(child.custom_minimum_size.x, 84.0)
			assert_gte(child.custom_minimum_size.y, 34.0)


func test_main_window_zoom_overlay_controls_canvas_zoom() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var zoom_control: Control = canvas.get_node("ZoomControl")
	var bottom_bar: Control = main.get_node("Root/BottomBar")
	var slider: HSlider = zoom_control.get_node("ZoomRow/ZoomSlider")
	var label: Label = zoom_control.get_node("ZoomRow/ZoomLabel")

	assert_eq(zoom_control.get_parent(), canvas)
	assert_gt(zoom_control.z_index, canvas.item_layer.z_index)
	assert_lte(zoom_control.get_global_rect().end.y, bottom_bar.get_global_rect().position.y)
	assert_eq(int(slider.value), canvas.zoom_index)
	assert_eq(label.text, "100%")

	slider.value = 8
	await wait_process_frames(1)
	assert_almost_eq(canvas.camera_zoom, 4.0, 0.001)
	assert_eq(label.text, "400%")

	canvas.zoom_by_steps(-4, canvas.size * 0.5)
	await wait_process_frames(1)
	assert_eq(int(slider.value), canvas.zoom_index)
	assert_eq(label.text, "100%")


func test_viewport_fill_policy_covers_expanded_visible_rect() -> void:
	var control := Control.new()
	ViewportFillPolicy.apply(control, Rect2(Vector2(-220, -120), Vector2(1880, 1200)))

	assert_eq(control.anchor_left, 0.0)
	assert_eq(control.anchor_right, 0.0)
	assert_eq(control.offset_left, -220.0)
	assert_eq(control.offset_top, -120.0)
	assert_eq(control.offset_right, 1660.0)
	assert_eq(control.offset_bottom, 1080.0)
	control.free()


func test_auto_interface_scale_detects_high_density_displays() -> void:
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(2560, 1440)), 1.25)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(3840, 2160)), 1.5)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(5120, 3140)), 2.0)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(2.0, Vector2i(2560, 1600)), 2.0)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.5, Vector2i(1920, 1080)), 1.5)


func test_auto_interface_scale_detects_macos_retina_point_rects() -> void:
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1244, 778), "macOS", 0),
		1.25
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1334, 834), "macOS", 0),
		1.25
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1440, 900), "macOS", 0),
		1.25
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(2.0, Vector2i(3024, 1964), "macOS", 220),
		1.25
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1440, 900), "macOS", 96),
		1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1920, 1080), "macOS", 110),
		1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1920, 1080), "macOS", 220),
		1.25
	)


func test_window_pixel_scale_is_separate_from_readable_interface_scale() -> void:
	var snapshot := {
		"reported_scale": 2.0,
		"screen_dpi": 220,
		"usable_size": Vector2i(3024, 1964),
	}

	assert_eq(InterfaceScalePolicy.resolve_from_snapshot(snapshot, 0.0, "macOS")["resolved"], 1.25)
	assert_eq(InterfaceScalePolicy.window_pixel_scale_from_snapshot(snapshot, "macOS"), 2.0)
	assert_eq(WindowScalePolicy.effective_window_geometry_scale(1.25, 2.0), 2.0)


func test_window_scale_converts_only_macos_point_sized_usable_rects() -> void:
	assert_eq(
		WindowScalePolicy.usable_size_to_window_pixels(Vector2i(1470, 956), 2.0, "macOS"),
		Vector2i(2940, 1912)
	)
	assert_eq(
		WindowScalePolicy.usable_size_to_window_pixels(Vector2i(3024, 1964), 2.0, "macOS"),
		Vector2i(3024, 1964)
	)
	assert_eq(
		WindowScalePolicy.window_pixels_to_screen_units(
			Vector2i(2880, 1800), 2.0, "macOS", Vector2i(1470, 956)
		),
		Vector2i(1440, 900)
	)


func test_interface_scale_preserves_readability_on_scaled_screens() -> void:
	assert_eq(
		InterfaceScalePolicy.fit_interface_scale_to_startup_screen(2.0, Vector2i(1334, 834)), 2.0
	)
	assert_eq(
		InterfaceScalePolicy.fit_interface_scale_to_startup_screen(2.0, Vector2i(1470, 956)), 2.0
	)
	assert_eq(
		InterfaceScalePolicy.fit_interface_scale_to_startup_screen(2.0, Vector2i(5120, 2982)), 2.0
	)


func test_content_scale_policy_captures_window_size_for_resize_fill() -> void:
	var window := Window.new()
	window.size = Vector2i(1440, 900)
	InterfaceScalePolicy.apply_content_scale_policy(window, 1.5)

	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_EXPAND)
	assert_eq(window.content_scale_size, Vector2i(1440, 900))
	assert_almost_eq(window.content_scale_factor, 1.5, 0.001)
	assert_eq(window.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL)

	window.free()


func test_live_rescale_detects_screen_signature_changes() -> void:
	var base := {
		"screen": 0,
		"reported_scale": 1.0,
		"screen_dpi": 96,
		"usable_size": Vector2i(1920, 1080),
	}
	var same := base.duplicate()
	var screen_changed := base.duplicate()
	screen_changed["screen"] = 1
	var scale_changed := base.duplicate()
	scale_changed["reported_scale"] = 1.5
	var dpi_changed := base.duplicate()
	dpi_changed["screen_dpi"] = 144

	assert_false(InterfaceScalePolicy.screen_scale_snapshot_changed(base, same))
	assert_true(InterfaceScalePolicy.screen_scale_snapshot_changed(base, screen_changed))
	assert_true(InterfaceScalePolicy.screen_scale_snapshot_changed(base, scale_changed))
	assert_true(InterfaceScalePolicy.screen_scale_snapshot_changed(base, dpi_changed))


func test_file_dialog_policy_uses_godot_drawn_dialogs() -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	DialogScalePolicy.configure_file_dialog(dialog)

	assert_false(dialog.use_native_dialog)
	dialog.free()


func test_cleanup_inspector_keeps_apply_actions_reachable_below_scroll() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var inspector: Control = main.get_node(
		"Root/Content/ContextInspector/ContextRoot/CleanupInspector"
	)
	var root: VBoxContainer = inspector.get_node("InspectorRoot")

	assert_gte(inspector.custom_minimum_size.x, 420.0)
	assert_not_null(root.get_node("CleanupScroll"))
	assert_not_null(root.get_node("CleanupActions/ApplyCleanupButton"))
	assert_eq(
		root.get_node("CleanupActions/ApplyCleanupButton").get_parent().name, "CleanupActions"
	)


func test_selection_tool_buttons_are_hidden_until_selection_actions_are_wired() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var top_bar: Control = main.get_node("Root/TopBar")
	var checked_buttons := 0
	for child in top_bar.find_children("*", "Button", true, false):
		if child is Button:
			checked_buttons += 1
			assert_ne(child.text, "W")
			assert_ne(child.text, "M")
			assert_ne(child.text, "L")
	assert_gt(checked_buttons, 0)


func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
	ProjectService.new_project("Mock UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	assert_eq(canvas.get_item_count(), 4)
	assert_eq(ProjectService.current_project.graphs.size(), 1)
	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
	var batch_node: Dictionary = graph_data["nodes"][3]
	assert_eq(batch_node["type"], "batch")
	assert_eq(batch_node["params"]["asset_ids"].size(), 10)
	var canvas_items: Array = canvas.export_canvas_data()["items"]
	assert_eq(canvas_items.size(), 4)
	assert_eq(_node_ids_from_canvas_items(canvas_items), ["objects", "size", "generate", "batch_1"])
	for canvas_item in canvas_items:
		assert_eq(canvas_item["type"], "node")
		assert_eq(canvas_item["graph_id"], graph_id)

	var batch_item_id := _item_id_for_node(canvas_items, "batch_1")
	var generate_item_id := _item_id_for_node(canvas_items, "generate")
	var generate_card: Node = canvas._items_by_id[generate_item_id]
	var first_asset_ids: Array = batch_node["params"]["asset_ids"].duplicate()
	canvas.select_ids([batch_item_id])
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	var rerun_asset_ids: Array = batch_node["params"]["asset_ids"]
	assert_eq(rerun_asset_ids.size(), 10)
	assert_ne(rerun_asset_ids, first_asset_ids)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), rerun_asset_ids)
	assert_eq(generate_card._status_badge, Strings.text("CONTENT_STATUS_COMPLETE"))

	canvas.select_ids([])
	canvas._selected_graph_edge = {
		"graph_id": graph_id,
		"edge": {"from": ["generate", "images"], "to": ["batch_1", "in"]},
	}
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	var edge_rerun_asset_ids: Array = batch_node["params"]["asset_ids"]
	assert_eq(edge_rerun_asset_ids.size(), 10)
	assert_ne(edge_rerun_asset_ids, rerun_asset_ids)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), edge_rerun_asset_ids)
	var valid_graph_data := graph_data.duplicate(true)

	canvas.select_ids([])
	canvas._selected_graph_edge = {"graph_id": "missing_graph", "edge": {}}
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % Strings.STATUS_GRAPH_RUN_MISSING_GRAPH
	)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), edge_rerun_asset_ids)

	var graph_without_batch := valid_graph_data.duplicate(true)
	var kept_nodes := []
	for raw_node in graph_without_batch["nodes"]:
		var node_data: Dictionary = raw_node
		if String(node_data.get("type", "")) != "batch":
			kept_nodes.append(node_data)
	graph_without_batch["nodes"] = kept_nodes
	ProjectService.set_graph_data(graph_id, graph_without_batch, true)

	canvas.select_ids([batch_item_id])
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % Strings.STATUS_GRAPH_RUN_NO_BATCH
	)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), edge_rerun_asset_ids)

	graph_data = valid_graph_data.duplicate(true)
	_remove_graph_edge(graph_data, "size", "spec", "generate", "spec")
	ProjectService.set_graph_data(graph_id, graph_data, true)
	var stable_asset_ids := edge_rerun_asset_ids.duplicate()

	canvas.select_ids([batch_item_id])
	controller.run_selected_mock_graph()
	await wait_process_frames(2)

	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % "Node generate requires input port spec"
	)
	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	assert_eq(batch_node["params"]["asset_ids"], stable_asset_ids)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), stable_asset_ids)
	assert_eq(generate_card._status_badge, Strings.text("CONTENT_STATUS_FAILED"))
	assert_false(canvas.export_canvas_data()["items"][2].has("execution_status"))


func test_batch_review_shortcuts_mark_selected_mock_thumbnail() -> void:
	ProjectService.new_project("Batch Shortcut UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)
	canvas.set_camera_zoom(1.0, canvas.size * 0.5)
	await wait_process_frames(1)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
	var batch_node: Dictionary = graph_data["nodes"][3]
	var first_asset_id := String(batch_node["params"]["asset_ids"][0])
	var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "batch_1")
	var batch_card: Node = canvas._items_by_id[batch_item_id]

	canvas.select_ids([batch_item_id])
	assert_true(batch_card.toggle_asset_at_world(batch_card.position + Vector2(20, 60)))
	assert_true(_send_key(controller, KEY_K))

	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	assert_eq(batch_node["params"]["review_states"][first_asset_id], "keep")

	assert_true(_send_key(controller, KEY_R))
	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	assert_eq(batch_node["params"]["review_states"][first_asset_id], "reject")


func test_selected_graph_node_params_are_undoable_and_affect_rerun() -> void:
	ProjectService.new_project("Graph Params UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var canvas_items: Array = canvas.export_canvas_data()["items"]
	var object_item_id := _item_id_for_node(canvas_items, "objects")
	var batch_item_id := _item_id_for_node(canvas_items, "batch_1")
	var object_card: Node = canvas._items_by_id[object_item_id]
	canvas.select_ids([object_item_id])

	assert_true(controller.apply_graph_node_params(graph_id, "objects", {"items": "tree\nrock"}))
	assert_eq(object_card._summary, "2 objects")
	assert_true(UndoService.undo())
	assert_eq(object_card._summary, "5 objects")
	assert_true(UndoService.redo())
	assert_eq(object_card._summary, "2 objects")

	controller.run_selected_mock_graph()
	await wait_process_frames(2)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id).size(), 4)
	assert_eq(_status_label(main).text, Strings.STATUS_GRAPH_RUN_DONE % 4)


func test_registry_graph_node_add_is_undoable_with_canvas_card() -> void:
	ProjectService.new_project("Graph Add UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	assert_eq(controller._graph_add_menu.item_count, 4)
	assert_eq(
		[
			controller._graph_add_menu.get_item_text(0),
			controller._graph_add_menu.get_item_text(1),
			controller._graph_add_menu.get_item_text(2),
			controller._graph_add_menu.get_item_text(3),
		],
		["AI Generate", "ComfyUI Workflow", "Object List", "Size Spec"]
	)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var object_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "objects")
	canvas.select_ids([object_item_id])
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	canvas._gui_input(tab_event)
	await wait_process_frames(1)

	assert_true(controller._graph_quick_add_menu.visible)
	assert_eq(controller._graph_quick_add_menu.item_count, 4)
	assert_eq(
		[
			controller._graph_quick_add_menu.get_item_text(0),
			controller._graph_quick_add_menu.get_item_text(1),
			controller._graph_quick_add_menu.get_item_text(2),
			controller._graph_quick_add_menu.get_item_text(3),
		],
		["AI Generate", "ComfyUI Workflow", "Object List", "Size Spec"]
	)

	var existing_node_ids := {}
	for node_data in ProjectService.current_project.graphs[graph_id]["nodes"]:
		existing_node_ids[String(node_data.get("id", ""))] = true
	controller._graph_quick_add_menu.hide()
	var requested_world_position := Vector2(840, 360)
	var requested_screen_position := Vector2i(
		canvas.get_screen_position() + canvas.world_to_screen(requested_world_position)
	)
	assert_true(controller.show_graph_quick_add_menu(requested_screen_position))
	var size_menu_id := -1
	for menu_id in controller._graph_add_types:
		if String(controller._graph_add_types[menu_id]) == "size_spec":
			size_menu_id = int(menu_id)
			break
	assert_gte(size_menu_id, 0)
	controller._graph_quick_add_menu.id_pressed.emit(size_menu_id)
	controller._graph_quick_add_menu.hide()

	var node_id := ""
	for node_data in ProjectService.current_project.graphs[graph_id]["nodes"]:
		var candidate_id := String(node_data.get("id", ""))
		if not existing_node_ids.has(candidate_id):
			node_id = candidate_id
			break

	assert_false(node_id.is_empty())
	assert_true(
		ProjectService.current_project.graphs[graph_id]["nodes"].any(
			func(node: Dictionary) -> bool: return String(node.get("id", "")) == node_id
		)
	)
	var added_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], node_id)
	assert_false(added_item_id.is_empty())
	assert_eq(
		_item_data_for_id(canvas.export_canvas_data()["items"], added_item_id)["position"],
		[840, 360]
	)
	var graph_nodes: Array = ProjectService.current_project.graphs[graph_id]["nodes"]
	var added_node_data := _node_data_for_id(graph_nodes, node_id)
	assert_eq(added_node_data["position"], [840, 360])
	assert_eq(_status_label(main).text, Strings.STATUS_GRAPH_ADD_DONE % "Size Spec")

	assert_true(UndoService.undo())
	assert_true(_item_id_for_node(canvas.export_canvas_data()["items"], node_id).is_empty())
	assert_false(
		ProjectService.current_project.graphs[graph_id]["nodes"].any(
			func(node: Dictionary) -> bool: return String(node.get("id", "")) == node_id
		)
	)

	assert_true(UndoService.redo())
	assert_false(_item_id_for_node(canvas.export_canvas_data()["items"], node_id).is_empty())
	assert_true(
		ProjectService.current_project.graphs[graph_id]["nodes"].any(
			func(node: Dictionary) -> bool: return String(node.get("id", "")) == node_id
		)
	)
	controller._graph_quick_add_menu.hide()
	canvas.select_ids([])
	tab_event = InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	canvas._gui_input(tab_event)
	await wait_process_frames(1)

	assert_false(controller._graph_quick_add_menu.visible)
	assert_eq(_status_label(main).text, Strings.STATUS_GRAPH_ADD_NEEDS_SELECTION)

	canvas.select_ids([object_item_id])
	var object_item_data := _item_data_for_id(canvas.export_canvas_data()["items"], object_item_id)
	var object_position: Array = object_item_data["position"]
	var file_node_id: String = controller.add_graph_node_to_selected_graph("size_spec")
	var file_node_data := _node_data_for_id(
		ProjectService.current_project.graphs[graph_id]["nodes"], file_node_id
	)
	assert_eq(
		file_node_data["position"],
		[int(object_position[0]) + 280, int(object_position[1])],
	)


func test_batch_review_focus_shortcuts_step_selected_mock_thumbnail() -> void:
	ProjectService.new_project("Batch Focus UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
	var batch_node: Dictionary = graph_data["nodes"][3]
	var asset_ids: Array = batch_node["params"]["asset_ids"]
	var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "batch_1")

	canvas.select_ids([batch_item_id])
	assert_true(_send_key(controller, KEY_RIGHT))
	assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[0]])

	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	assert_eq(batch_node["params"]["focus_asset_id"], asset_ids[0])

	assert_true(_send_key(controller, KEY_RIGHT))
	assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[1]])

	graph_data = ProjectService.current_project.graphs[graph_id]
	batch_node = graph_data["nodes"][3]
	assert_eq(batch_node["params"]["focus_asset_id"], asset_ids[1])

	assert_true(_send_key(controller, KEY_LEFT))
	assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[0]])


func test_graph_status_events_update_status_bar() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var edge := {"from": ["objects", "items"], "to": ["generate", "items"]}

	canvas.graph_status.emit({"type": "edge_selected", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_EDGE_SELECTED % ["objects", "items", "generate", "items"]
	)

	canvas.graph_status.emit({"type": "edge_deleted", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_EDGE_DELETED % ["objects", "items", "generate", "items"]
	)

	canvas.graph_status.emit({"type": "connect_succeeded", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.STATUS_GRAPH_CONNECT_DONE % ["objects", "items", "generate", "items"]
	)


func test_run_selected_graph_reports_ghost_node_type() -> void:
	ProjectService.new_project("Ghost Graph UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	(
		ProjectService
		. set_graph_data(
			"graph_ghost",
			{
				"graph_version": 1,
				"id": "graph_ghost",
				"name": "Ghost Graph",
				"nodes":
				[
					{
						"id": "plugin_1",
						"type": "missing.plugin_node",
						"position": [0, 0],
						"params": {"seed": 9},
					},
					{
						"id": "batch_1",
						"type": "batch",
						"position": [300, 0],
						"params": {"label": "Ghost Batch", "asset_ids": []},
					},
				],
				"edges": [],
			},
			false
		)
	)
	(
		canvas
		. load_canvas_data(
			{
				"camera": {"center": [0, 0], "zoom": 1.0},
				"items":
				[
					_node_item("ghost_item", "graph_ghost", "plugin_1", Vector2(0, 0)),
					_node_item("batch_item", "graph_ghost", "batch_1", Vector2(300, 0)),
				],
			}
		)
	)

	canvas.select_ids(["ghost_item"])
	controller.run_selected_mock_graph()
	await wait_process_frames(1)

	assert_eq(
		_status_label(main).text,
		(
			Strings.STATUS_GRAPH_RUN_FAILED_DETAIL
			% (Strings.STATUS_GRAPH_RUN_MISSING_NODE_TYPE % "missing.plugin_node")
		)
	)


func _node_ids_from_canvas_items(items: Array) -> Array:
	var node_ids := []
	for item in items:
		node_ids.append(String(Dictionary(item).get("node_id", "")))
	return node_ids


func _item_id_for_node(items: Array, node_id: String) -> String:
	for item in items:
		var data: Dictionary = item
		if String(data.get("node_id", "")) == node_id:
			return String(data.get("id", ""))
	return ""


func _item_data_for_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		var data: Dictionary = item
		if String(data.get("id", "")) == item_id:
			return data
	return {}


func _node_data_for_id(nodes: Array, node_id: String) -> Dictionary:
	for node in nodes:
		var data: Dictionary = node
		if String(data.get("id", "")) == node_id:
			return data
	return {}


func _remove_graph_edge(
	graph_data: Dictionary, from_node: String, from_port: String, to_node: String, to_port: String
) -> void:
	var kept_edges := []
	for raw_edge in graph_data.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge: Dictionary = raw_edge
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if (
			String(from_data[0]) == from_node
			and String(from_data[1]) == from_port
			and String(to_data[0]) == to_node
			and String(to_data[1]) == to_port
		):
			continue
		kept_edges.append(edge)
	graph_data["edges"] = kept_edges


func _node_item(
	item_id: String, graph_id: String, node_id: String, position: Vector2
) -> Dictionary:
	return {
		"id": item_id,
		"type": "node",
		"graph_id": graph_id,
		"node_id": node_id,
		"position": [int(position.x), int(position.y)],
		"z_index": 0,
		"locked": false,
	}


func _status_label(main: Control) -> Label:
	return main.get_node("Root/BottomBar").get_child(0)


func _send_key(controller: Node, keycode: Key) -> bool:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return controller.handle_shortcut(event)
