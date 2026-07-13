extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Beta 0.6 workspace")
	AssetLibrary.clear()


func test_workspace_shell_exposes_frozen_primary_regions() -> void:
	pending("B6-2 workspace shell")
	return
	var main := await _make_main()
	var top_bar: Control = main.get_node("Root/TopBar")
	var left_rail: Control = main.get_node("Root/Content/LeftRail")
	var inspector: Control = main.get_node("Root/Content/Workspace/ContextInspector")

	assert_eq(top_bar.custom_minimum_size.y, 52.0)
	assert_eq(left_rail.custom_minimum_size.x, 48.0)
	assert_false(inspector.visible)
	for action_id in ["file", "run_selection", "export", "inspector", "more"]:
		assert_eq(_action_count(main, action_id), 1, action_id)


func test_loaded_fifty_percent_zoom_is_synchronized_in_one_frame() -> void:
	pending("B6-2 workspace shell")
	return
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	canvas.load_canvas_data({"camera": {"center": [0, 0], "zoom": 0.5}, "items": []})
	await wait_process_frames(1)
	assert_eq(canvas.camera_zoom, 0.5)
	assert_eq(canvas.zoom_index, 2)
	assert_eq(main.get_node("Root/Content/Workspace/InfiniteCanvas/ZoomControl/ZoomLabel").text, "50%")


func _make_main() -> Control:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	main.get_node("RecoveryDialog").hide()
	return main


func _action_count(root: Node, action_id: String) -> int:
	var count := 0
	for node in root.find_children("*", "Control", true, false):
		if String(node.get_meta("action_id", "")) == action_id:
			count += 1
	return count
