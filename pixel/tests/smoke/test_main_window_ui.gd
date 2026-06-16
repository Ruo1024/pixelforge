extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")


func test_main_window_uses_readable_minimum_sizes() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var root := main.get_node("Root")
	var top_bar: Control = root.get_node("TopBar")
	var bottom_bar: Control = root.get_node("BottomBar")

	assert_eq(main.custom_minimum_size, Vector2(1280, 800))
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

	slider.value = 5
	await wait_process_frames(1)
	assert_almost_eq(canvas.camera_zoom, 4.0, 0.001)
	assert_eq(label.text, "400%")

	canvas.zoom_by_steps(-2, canvas.size * 0.5)
	await wait_process_frames(1)
	assert_eq(int(slider.value), canvas.zoom_index)
	assert_eq(label.text, "100%")


func test_auto_interface_scale_detects_high_density_displays() -> void:
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(2560, 1440)), 1.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(3840, 2160)), 1.5)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(5120, 3140)), 2.0)
	assert_eq(MainScript.compute_auto_interface_scale(2.0, Vector2i(2560, 1600)), 2.0)


func test_auto_interface_scale_detects_macos_retina_point_rects() -> void:
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1244, 778), "macOS", 0), 2.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1334, 834), "macOS", 0), 2.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1440, 900), "macOS", 0), 2.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1440, 900), "macOS", 96), 1.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1920, 1080), "macOS", 110), 1.0)
	assert_eq(MainScript.compute_auto_interface_scale(1.0, Vector2i(1920, 1080), "macOS", 220), 2.0)


func test_interface_scale_is_clamped_when_startup_screen_cannot_fit_scaled_window() -> void:
	assert_eq(MainScript.fit_interface_scale_to_startup_screen(2.0, Vector2i(1334, 834)), 1.0)
	assert_eq(MainScript.fit_interface_scale_to_startup_screen(2.0, Vector2i(5120, 2982)), 2.0)
