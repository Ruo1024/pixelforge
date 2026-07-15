# gdlint: disable=max-public-methods
extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const WindowScalePolicy := preload("res://ui/shell/window_scale_policy.gd")
const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")
const BetaWorkspaceFixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")


func test_main_window_uses_readable_minimum_sizes() -> void:
	LocalizationService.set_language("en")
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var root := main.get_node("Root")
	var top_bar: Control = root.get_node("TopBar")
	var bottom_bar: Control = root.get_node("BottomBar")

	assert_eq(main.custom_minimum_size, Vector2(1080, 560))
	assert_eq(top_bar.custom_minimum_size.y, 52.0)
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

	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
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


func test_auto_interface_scale_detects_high_density_displays() -> void:
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(2560, 1440)), 1.25)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(3840, 2160)), 1.5)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(5120, 3140)), 2.0)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(2.0, Vector2i(2560, 1600)), 2.0)
	assert_eq(InterfaceScalePolicy.compute_auto_interface_scale(1.5, Vector2i(1920, 1080)), 1.5)


func test_auto_interface_scale_detects_macos_retina_point_rects() -> void:
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1244, 778), "macOS", 0), 1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1334, 834), "macOS", 0), 1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(1440, 900), "macOS", 0), 1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(2.0, Vector2i(3024, 1964), "macOS", 220),
		2.0
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
		1.0
	)
	assert_eq(
		InterfaceScalePolicy.compute_auto_interface_scale(1.0, Vector2i(4650, 2825), "macOS", 96),
		1.0,
		"A native-scale external display must not be enlarged from resolution alone"
	)


func test_window_pixel_scale_is_separate_from_readable_interface_scale() -> void:
	var snapshot := {
		"reported_scale": 2.0,
		"max_scale": 2.0,
		"screen_dpi": 220,
		"usable_size": Vector2i(3024, 1964),
	}

	assert_eq(InterfaceScalePolicy.resolve_from_snapshot(snapshot, 0.0, "macOS")["resolved"], 2.0)
	assert_eq(InterfaceScalePolicy.window_pixel_scale_from_snapshot(snapshot, "macOS"), 2.0)
	assert_eq(WindowScalePolicy.effective_window_geometry_scale(2.0, 2.0), 2.0)


func test_macos_auto_scale_uses_session_max_and_editor_embed_is_neutral() -> void:
	var native_snapshot := {
		"reported_scale": 1.0,
		"max_scale": 2.0,
		"usable_size": Vector2i(4650, 2825),
		"display_server": "macOS",
	}
	var embedded_snapshot := native_snapshot.duplicate()
	embedded_snapshot["display_server"] = "embedded"
	assert_eq(
		InterfaceScalePolicy.resolve_from_snapshot(native_snapshot, 0.0, "macOS")["resolved"], 2.0
	)
	assert_eq(
		InterfaceScalePolicy.resolve_from_snapshot(embedded_snapshot, 0.0, "macOS")["resolved"], 1.0
	)


func test_window_scale_uses_display_server_geometry_without_second_conversion() -> void:
	assert_eq(
		WindowScalePolicy.usable_size_to_window_pixels(Vector2i(1470, 956), 2.0, "macOS"),
		Vector2i(1470, 956)
	)
	assert_eq(
		WindowScalePolicy.usable_size_to_window_pixels(Vector2i(3024, 1964), 2.0, "macOS"),
		Vector2i(3024, 1964)
	)
	assert_eq(
		WindowScalePolicy.window_pixels_to_screen_units(
			Vector2i(2880, 1800), 2.0, "macOS", Vector2i(1470, 956)
		),
		Vector2i(2880, 1800)
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


func test_content_scale_policy_keeps_window_resize_independent_from_ui_scale() -> void:
	var window := Window.new()
	window.size = Vector2i(1440, 900)
	InterfaceScalePolicy.apply_content_scale_policy(window, 1.5)

	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_IGNORE)
	assert_eq(window.content_scale_size, Vector2i.ZERO)
	assert_almost_eq(window.content_scale_factor, 1.5, 0.001)
	assert_eq(window.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL)
	window.size = Vector2i(2880, 1800)
	assert_eq(
		window.get_visible_rect().size,
		Vector2(1920, 1200),
		"A larger window must expose more workspace instead of zooming the old viewport"
	)

	window.free()


func test_window_geometry_does_not_double_macos_screen_units() -> void:
	assert_eq(WindowScalePolicy.effective_window_geometry_scale(1.25, 2.0), 1.25)
	assert_eq(
		WindowScalePolicy.usable_size_to_window_pixels(Vector2i(1440, 778), 2.0, "macOS"),
		Vector2i(1440, 778)
	)
	assert_eq(
		WindowScalePolicy.fit_size_to_usable_rect(
			Vector2i(2880, 1800), Vector2i(2160, 1120), Vector2i(2880, 1556), 64
		),
		Vector2i(2816, 1492)
	)
	assert_eq(
		WindowScalePolicy.fit_size_to_usable_rect(
			Vector2i(2880, 1800), Vector2i(2160, 1120), Vector2i(4650, 2825), 64
		),
		Vector2i(2880, 1800)
	)
	assert_eq(
		WindowScalePolicy.window_pixels_to_screen_units(
			Vector2i(1360, 700), 2.0, "macOS", Vector2i(1440, 778)
		),
		Vector2i(1360, 700)
	)


func test_file_dialog_policy_uses_godot_drawn_dialogs() -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	DialogScalePolicy.configure_file_dialog(dialog)

	assert_false(dialog.use_native_dialog)
	dialog.free()


func test_cleanup_inspector_is_parameter_only_and_scrollable() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var inspector: Control = main.get_node(
		"Root/Content/Workspace/ContextInspector/ContextRoot/CleanupInspector"
	)
	var root: VBoxContainer = inspector.get_node("InspectorRoot")

	assert_gte(inspector.custom_minimum_size.x, 360.0)
	assert_not_null(root.get_node("CleanupScroll"))
	assert_null(root.get_node_or_null("CleanupActions"))
	assert_null(root.find_child("ApplyCleanupButton", true, false))
	assert_null(root.find_child("CancelCleanupButton", true, false))


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


func test_offline_example_action_creates_v2_graph_without_output() -> void:
	ProjectService.new_project("Mock UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	assert_eq(canvas.get_item_count(), 5)
	assert_eq(ProjectService.current_project.graphs.size(), 1)
	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
	var canvas_items: Array = canvas.export_canvas_data()["items"]
	assert_eq(canvas_items.size(), 5)
	assert_eq(
		_node_ids_from_canvas_items(canvas_items),
		["prompt_preset", "text_prompt", "reference_set", "generate", "cleanup"]
	)
	assert_false(
		graph_data["nodes"].any(func(node: Dictionary) -> bool: return node["type"] == "batch")
	)
	for canvas_item in canvas_items:
		assert_eq(canvas_item["type"], "node")
		assert_eq(canvas_item["graph_id"], graph_id)
	for node_data in graph_data["nodes"]:
		assert_ne(String(node_data.get("type", "")), "size_spec")
	assert_false(graph_data["edges"].any(_edge_uses_legacy_generation_port))


func test_selected_graph_node_params_are_undoable() -> void:
	ProjectService.new_project("Graph Params UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var canvas_items: Array = canvas.export_canvas_data()["items"]
	var prompt_item_id := _item_id_for_node(canvas_items, "text_prompt")
	canvas.select_ids([prompt_item_id])

	assert_true(
		controller.apply_graph_node_params(graph_id, "text_prompt", {"text": "four tiny towers"})
	)
	assert_eq(_graph_text_param(graph_id), "four tiny towers")
	assert_true(UndoService.undo())
	assert_ne(_graph_text_param(graph_id), "four tiny towers")
	assert_true(UndoService.redo())
	assert_eq(_graph_text_param(graph_id), "four tiny towers")


func test_registry_graph_node_add_is_undoable_with_canvas_card() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Graph Add UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	var add_menu_texts := _menu_texts(controller._graph_add_menu)
	for expected_text in [
		"AI Generate", "Output", "Reference Image", "Object List", "Style Prompt", "Text Prompt"
	]:
		assert_has(add_menu_texts, expected_text)
	assert_false(add_menu_texts.has("Size Spec"))
	assert_false(add_menu_texts.has("ComfyUI Workflow"))

	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var source_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "text_prompt")
	canvas.select_ids([source_item_id])
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	canvas._gui_input(tab_event)
	await wait_process_frames(1)

	assert_true(controller._graph_quick_add_menu.visible)
	assert_eq(_menu_texts(controller._graph_quick_add_menu), add_menu_texts)

	var existing_node_ids := {}
	for node_data in ProjectService.current_project.graphs[graph_id]["nodes"]:
		existing_node_ids[String(node_data.get("id", ""))] = true
	controller._graph_quick_add_menu.hide()
	var requested_world_position := Vector2(840, 360)
	var requested_screen_position := Vector2i(
		canvas.get_screen_position() + canvas.world_to_screen(requested_world_position)
	)
	assert_true(controller.show_graph_quick_add_menu(requested_screen_position))
	var prompt_menu_id := -1
	for menu_id in controller._graph_add_types:
		if String(controller._graph_add_types[menu_id]) == "text_prompt":
			prompt_menu_id = int(menu_id)
			break
	assert_gte(prompt_menu_id, 0)
	controller._graph_quick_add_menu.id_pressed.emit(prompt_menu_id)
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
	assert_false(added_node_data.has("position"))
	assert_eq(_status_label(main).text, Strings.text("STATUS_GRAPH_ADD_DONE") % "Text Prompt")

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
	await wait_process_frames(1)
	canvas.select_ids([])
	tab_event = InputEventKey.new()
	tab_event.keycode = KEY_TAB
	tab_event.pressed = true
	canvas._gui_input(tab_event)
	await wait_process_frames(1)

	assert_true(controller._graph_quick_add_menu.visible)
	controller._graph_quick_add_menu.hide()

	canvas.select_ids([source_item_id])
	var source_item_data := _item_data_for_id(canvas.export_canvas_data()["items"], source_item_id)
	var source_position: Array = source_item_data["position"]
	var prompt_node_id: String = controller.add_graph_node_to_selected_graph("text_prompt")
	var prompt_node_data := _node_data_for_id(
		ProjectService.current_project.graphs[graph_id]["nodes"], prompt_node_id
	)
	assert_false(prompt_node_data.has("position"))
	var prompt_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], prompt_node_id)
	assert_eq(
		_item_data_for_id(canvas.export_canvas_data()["items"], prompt_item_id)["position"],
		[int(source_position[0]) + 280, int(source_position[1])],
	)

	var batch_node_id: String = controller.add_graph_node_to_selected_graph(
		"batch", Vector2(960, 480)
	)
	var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], batch_node_id)
	assert_false(batch_node_id.is_empty())
	assert_false(batch_item_id.is_empty())
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), [])
	var batch_params: Dictionary = _node_data_for_id(
		ProjectService.current_project.graphs[graph_id]["nodes"], batch_node_id
	)["params"]
	assert_false(batch_params.has("asset_ids"))
	assert_eq(batch_params["result_slots"], [])
	assert_true(UndoService.undo())
	assert_true(_item_id_for_node(canvas.export_canvas_data()["items"], batch_node_id).is_empty())
	assert_false(
		ProjectService.current_project.graphs[graph_id]["nodes"].any(
			func(node: Dictionary) -> bool: return String(node.get("id", "")) == batch_node_id
		)
	)
	assert_true(UndoService.redo())
	assert_false(_item_id_for_node(canvas.export_canvas_data()["items"], batch_node_id).is_empty())


func test_quick_add_on_empty_canvas_creates_default_graph_at_requested_position_atomically(
) -> void:
	ProjectService.new_project("Empty Quick Add")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var requested_world := Vector2(-240, 180)
	var requested_screen := Vector2i(
		canvas.get_screen_position() + canvas.world_to_screen(requested_world)
	)

	assert_true(controller.show_graph_quick_add_menu(requested_screen))
	var object_menu_id := -1
	for menu_id in controller._graph_add_types:
		if String(controller._graph_add_types[menu_id]) == "object_list":
			object_menu_id = int(menu_id)
			break
	assert_gte(object_menu_id, 0)
	controller._graph_quick_add_menu.id_pressed.emit(object_menu_id)
	controller._graph_quick_add_menu.hide()

	assert_true(ProjectService.current_project.graphs.has("graph_main"))
	var nodes: Array = ProjectService.current_project.graphs["graph_main"]["nodes"]
	assert_eq(nodes.size(), 1)
	assert_eq(nodes[0]["type"], "object_list")
	assert_false(nodes[0].has("position"))
	assert_eq(canvas.get_item_count(), 1)
	var object_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], nodes[0]["id"])
	assert_eq(
		_item_data_for_id(canvas.export_canvas_data()["items"], object_item_id)["position"],
		[-240, 180]
	)
	assert_true(UndoService.undo())
	assert_true(ProjectService.current_project.graphs.is_empty())
	assert_eq(canvas.get_item_count(), 0)
	assert_true(UndoService.redo())
	assert_true(ProjectService.current_project.graphs.has("graph_main"))
	assert_eq(canvas.get_item_count(), 1)


func test_graph_status_events_update_status_bar() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var edge := {"from": ["objects", "subjects"], "to": ["generate", "subjects"]}
	canvas.graph_status.emit({"type": "connect_preview", "state": "valid"})
	assert_eq(_status_label(main).text, Strings.text("STATUS_GRAPH_CONNECT_PREVIEW_VALID"))
	canvas.graph_status.emit(
		{"type": "connect_preview", "state": "invalid", "reason": "Wrong port"}
	)
	assert_eq(
		_status_label(main).text,
		Strings.text("STATUS_GRAPH_CONNECT_PREVIEW_INVALID_FORMAT") % "Wrong port"
	)

	canvas.graph_status.emit({"type": "edge_selected", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.text("STATUS_GRAPH_EDGE_SELECTED") % ["objects", "subjects", "generate", "subjects"]
	)

	canvas.graph_status.emit({"type": "edge_deleted", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.text("STATUS_GRAPH_EDGE_DELETED") % ["objects", "subjects", "generate", "subjects"]
	)

	canvas.graph_status.emit({"type": "connect_succeeded", "edge": edge})
	assert_eq(
		_status_label(main).text,
		Strings.text("STATUS_GRAPH_CONNECT_DONE") % ["objects", "subjects", "generate", "subjects"]
	)
	canvas.graph_status.emit({"type": "nodes_grouped", "count": 2})
	assert_eq(_status_label(main).text, Strings.text("STATUS_FRAME_GROUPED_FORMAT") % 2)


func test_run_selected_graph_reports_ghost_node_type() -> void:
	ProjectService.new_project("Ghost Graph UI")
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)

	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	(
		ProjectService
		. set_graph_data(
			"graph_ghost",
			{
				"graph_version": 2,
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
						"params":
						{
							"label": "Ghost Batch",
							"source_node_id": "",
							"source_run_id": "",
							"role": "standalone",
							"input_snapshots": {},
							"request_records": [],
							"result_slots": [],
						},
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
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
			% (Strings.text("STATUS_GRAPH_RUN_MISSING_NODE_TYPE") % "missing.plugin_node")
		)
	)


func test_candidate_continue_branch_is_one_undoable_canvas_action() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Candidate branch")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var asset_id := AssetLibrary.register_image(image, "candidate", {"origin": "generated"})
	var graph := GraphScript.new()
	graph.id = "graph_candidate_branch"
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			"source_batch",
			{
				"label": "Source",
				"source_node_id": "",
				"source_run_id": "source-run",
				"role": "standalone",
				"input_snapshots": {},
				"request_records": [],
				"result_slots": [_succeeded_slot("source-slot", "source-run", asset_id)],
			},
			Vector2.ZERO
		)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	canvas._add_graph_node_card(graph.id, "source_batch", Vector2.ZERO, "source_item", false)
	(
		controller
		. _handle_candidate_action(
			"continue_branch",
			{
				"graph_id": graph.id,
				"batch_node_id": "source_batch",
				"asset_ids": [asset_id],
				"snapshot":
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"prompt": "small tower",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 2,
					"requested_seed": 8,
					"extra": {},
				},
			}
		)
	)
	assert_eq(ProjectService.get_graph_data(graph.id)["nodes"].size(), 6)
	assert_eq(ProjectService.get_graph_data(graph.id)["edges"].size(), 4)
	assert_eq(canvas.export_canvas_data()["items"].size(), 6)
	assert_true(UndoService.undo())
	assert_eq(ProjectService.get_graph_data(graph.id)["nodes"].size(), 1)
	assert_eq(canvas.export_canvas_data()["items"].size(), 1)
	assert_true(UndoService.redo())
	assert_eq(ProjectService.get_graph_data(graph.id)["nodes"].size(), 6)
	assert_eq(canvas.export_canvas_data()["items"].size(), 6)


func test_workflow_template_inserts_at_anchor_and_undoes_as_one_canvas_action() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1440, 900)
	add_child_autofree(main)
	await wait_process_frames(2)
	ProjectService.new_project("Workflow insert")
	await wait_process_frames(1)
	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	var template: Dictionary = WorkflowTemplateService.builtin_templates()[0]
	var result: Dictionary = controller._insert_workflow_template(template, Vector2(500, 300))
	var template_node_count := Array(template["nodes"]).size()

	assert_true(result["ok"])
	assert_eq(ProjectService.get_graph_data("graph_main")["nodes"].size(), template_node_count)
	assert_eq(canvas.export_canvas_data()["items"].size(), template_node_count + 1)
	assert_eq(canvas.get_selected_ids().size(), template_node_count + 1)
	assert_eq(
		_item_data_for_id(canvas.export_canvas_data()["items"], result["frame_id"])["position"],
		[500, 300]
	)
	assert_true(UndoService.undo())
	await wait_process_frames(1)
	assert_eq(ProjectService.get_graph_data("graph_main")["nodes"].size(), 0)
	assert_eq(canvas.export_canvas_data()["items"], [])
	assert_true(UndoService.redo())
	await wait_process_frames(1)
	assert_eq(ProjectService.get_graph_data("graph_main")["nodes"].size(), template_node_count)
	assert_eq(canvas.export_canvas_data()["items"].size(), template_node_count + 1)


func test_selected_stage_runs_each_valid_target_without_unrelated_empty_inputs() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1440, 900)
	add_child_autofree(main)
	await wait_process_frames(2)
	var fixture: Dictionary = BetaWorkspaceFixture.build()
	var graph_data: Dictionary = fixture["graphs"][BetaWorkspaceFixture.GRAPH_ID]
	graph_data["edges"] = graph_data["edges"].filter(
		func(edge: Dictionary) -> bool: return String(edge["from"][0]).find("reference") < 0
	)
	fixture["canvas"]["items"] = fixture["canvas"]["items"].filter(
		func(item: Dictionary) -> bool: return item.get("id", "") != "stage_b"
	)
	for item in fixture["canvas"]["items"]:
		if item.get("type", "") == "node":
			item["frame_id"] = "stage_a"
	ProjectService.set_graphs_data(fixture["graphs"])
	ProjectService.set_canvas_data(fixture["canvas"])
	ProjectService.project_loaded.emit(ProjectService.current_project)
	await wait_process_frames(1)
	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	canvas.select_ids(["stage_a"])
	controller.run_selected_mock_graph()

	var completed: Dictionary = ProjectService.get_graph_data(BetaWorkspaceFixture.GRAPH_ID)
	var batch_a_params: Dictionary = _node_data_for_id(completed["nodes"], "batch_a")["params"]
	var batch_b_params: Dictionary = _node_data_for_id(completed["nodes"], "batch_b")["params"]
	var output_a: Dictionary = _current_output_for_source(completed["nodes"], "generate_a")
	var output_b: Dictionary = _current_output_for_source(completed["nodes"], "generate_b")
	assert_false(batch_a_params.has("asset_ids"))
	assert_false(batch_b_params.has("asset_ids"))
	assert_eq(batch_a_params["result_slots"], [])
	assert_eq(batch_b_params["result_slots"], [])
	assert_eq(output_a["params"]["result_slots"].size(), 4)
	assert_eq(output_b["params"]["result_slots"].size(), 4)
	assert_true(AssetLibrary.has_asset(String(output_a["params"]["result_slots"][0]["asset_id"])))


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


func _graph_text_param(graph_id: String) -> String:
	var nodes: Array = ProjectService.get_graph_data(graph_id).get("nodes", [])
	return String(_node_data_for_id(nodes, "text_prompt").get("params", {}).get("text", ""))


func _newest_batch_node_except(nodes: Array, excluded_ids: Array) -> Dictionary:
	var result := {}
	for raw_node in nodes:
		var node: Dictionary = raw_node
		if String(node.get("type", "")) != "batch":
			continue
		if excluded_ids.has(String(node.get("id", ""))):
			continue
		result = node
	return result


func _current_output_for_source(nodes: Array, source_node_id: String) -> Dictionary:
	for raw_node in nodes:
		var node: Dictionary = raw_node
		if String(node.get("type", "")) != "batch":
			continue
		var params: Dictionary = node.get("params", {})
		if (
			String(params.get("source_node_id", "")) == source_node_id
			and String(params.get("role", "")) == "current"
		):
			return node
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


func _edge_uses_legacy_generation_port(raw_edge: Variant) -> bool:
	if not (raw_edge is Dictionary):
		return false
	var edge: Dictionary = raw_edge
	var from_data: Array = edge.get("from", ["", ""])
	var to_data: Array = edge.get("to", ["", ""])
	return (
		String(from_data[1]) in ["items", "spec", "image", "images", "style"]
		or String(to_data[1]) in ["items", "spec", "image", "images", "style"]
	)


func _succeeded_slot(slot_id: String, run_id: String, asset_id: String) -> Dictionary:
	return {
		"slot_id": slot_id,
		"run_id": run_id,
		"request_id": "",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "",
		"planned_size": [4, 4],
		"status": "succeeded",
		"asset_id": asset_id,
		"detached": false,
		"unexpected": false,
		"error": null,
	}


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


func _menu_texts(menu: PopupMenu) -> Array[String]:
	var result: Array[String] = []
	for index in range(menu.item_count):
		result.append(menu.get_item_text(index))
	return result
