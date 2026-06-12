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
