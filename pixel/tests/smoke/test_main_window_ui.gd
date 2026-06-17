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
