extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const ViewportFillPolicy := preload("res://ui/shell/viewport_fill_policy.gd")
const WindowScalePolicy := preload("res://ui/shell/window_scale_policy.gd")


func test_main_window_uses_readable_minimum_sizes() -> void:
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
	var zoom_control: Control = main.get_node("ZoomControl")
	var slider: HSlider = zoom_control.get_node("ZoomRow/ZoomSlider")
	var label: Label = zoom_control.get_node("ZoomRow/ZoomLabel")

	assert_eq(zoom_control.get_parent(), main)
	assert_gt(zoom_control.z_index, canvas.item_layer.z_index)
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

	var inspector: Control = main.get_node("Root/Content/CleanupInspector")
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
	for child in top_bar.get_children():
		if child is Button:
			assert_ne(child.text, "W")
			assert_ne(child.text, "M")
			assert_ne(child.text, "L")


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


func _send_key(controller: Node, keycode: Key) -> bool:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return controller.handle_shortcut(event)
