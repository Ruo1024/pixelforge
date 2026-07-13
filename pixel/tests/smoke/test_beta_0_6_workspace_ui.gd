extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")

const MATRIX_LOCALES := ["en", "zh_CN"]
const MATRIX_WINDOWS := [Vector2(1080, 560), Vector2(1280, 720), Vector2(1440, 900)]
const MATRIX_SCALES := [1.0, 1.25, 1.5]


func before_each() -> void:
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, 1.0)
	LocalizationService.set_language("en")
	ProjectService.new_project("Beta 0.6 workspace")
	AssetLibrary.clear()


func after_each() -> void:
	SettingsService.set_setting("ui", "interface_scale", 1.0, false)
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, 1.0)
	LocalizationService.apply_language("en", "en")


func test_workspace_shell_exposes_frozen_primary_regions() -> void:
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
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	canvas.load_canvas_data({"camera": {"center": [0, 0], "zoom": 0.5}, "items": []})
	await wait_process_frames(1)
	assert_eq(canvas.camera_zoom, 0.5)
	assert_eq(canvas.zoom_index, 2)
	assert_eq(
		main.get_node("Root/Content/Workspace/InfiniteCanvas/ZoomControl/ZoomRow/ZoomLabel").text,
		"50%"
	)


func test_inspector_docks_wide_overlays_narrow_and_preserves_camera() -> void:
	var main := await _make_main()
	var workspace: Control = main.get_node("Root/Content/Workspace")
	var canvas: Control = workspace.get_node("InfiniteCanvas")
	var inspector: Control = workspace.get_node("ContextInspector")
	canvas.set_camera_zoom(0.75)
	canvas.camera_center = Vector2(120, -48)
	main.size = Vector2(1600, 800)
	await wait_process_frames(2)
	main._toggle_inspector()
	await wait_process_frames(2)
	assert_false(workspace.is_inspector_overlay())
	assert_true(inspector.visible)
	assert_lt(canvas.size.x, workspace.size.x)
	main.size = Vector2(1200, 700)
	await wait_process_frames(2)
	assert_true(workspace.is_inspector_overlay())
	assert_almost_eq(canvas.size.x, workspace.size.x, 1.0)
	assert_eq(canvas.camera_center, Vector2(120, -48))
	assert_eq(canvas.camera_zoom, 0.75)


func test_fixed_eighteen_case_workspace_geometry_matrix() -> void:
	SettingsService.set_setting("onboarding", "v1_complete", true, false)
	SettingsService.set_setting("ui", "live_rescale", false, false)
	var case_count := 0
	for locale in MATRIX_LOCALES:
		for window_size in MATRIX_WINDOWS:
			for interface_scale in MATRIX_SCALES:
				case_count += 1
				var case_label := "%s %s @ %s" % [locale, window_size, interface_scale]
				SettingsService.set_setting("ui", "interface_scale", interface_scale, false)
				LocalizationService.apply_language(locale, locale)
				ProjectService.new_project(
					"Beta 0.6 geometry title that is intentionally longer than the toolbar slot"
				)
				var main: Control = MainScript.new()
				add_child(main)
				await wait_process_frames(2)
				main.size = window_size
				await wait_process_frames(2)
				await _assert_workspace_case(main, window_size, interface_scale, case_label)
				main.queue_free()
				await wait_process_frames(2)
	assert_eq(case_count, 18)


func _assert_workspace_case(
	main: Control, window_size: Vector2, interface_scale: float, case_label: String
) -> void:
	var top_bar: Control = main.get_node("Root/TopBar")
	var content: Control = main.get_node("Root/Content")
	var left_rail: Control = content.get_node("LeftRail")
	var workspace: Control = content.get_node("Workspace")
	var canvas: Control = workspace.get_node("InfiniteCanvas")
	var inspector: Control = workspace.get_node("ContextInspector")
	var title: Label = top_bar.get_node("ProjectTitle")
	var status: Label = main.get_node("Root/BottomBar").get_child(0)
	assert_almost_eq(main.size.x, window_size.x, 0.5, case_label)
	assert_almost_eq(main.size.y, window_size.y, 0.5, case_label)
	assert_almost_eq(main._interface_scale, interface_scale, 0.001, case_label)
	assert_almost_eq(get_tree().root.content_scale_factor, interface_scale, 0.001, case_label)
	assert_eq(top_bar.size.y, 52.0, case_label)
	assert_eq(left_rail.size.x, 48.0, case_label)
	assert_false(inspector.visible, case_label)
	_assert_children_inside(top_bar, case_label)
	_assert_children_inside(left_rail, case_label)
	_assert_no_direct_child_overlap(top_bar, case_label)
	for action_id in [
		"file", "add_input", "import_reference", "run_selection", "export", "inspector", "more"
	]:
		assert_eq(_action_count(main, action_id), 1, "%s %s" % [case_label, action_id])
		var action := _action_control(main, action_id)
		assert_not_null(action, "%s %s" % [case_label, action_id])
		assert_true(action.visible, "%s %s" % [case_label, action_id])
		_assert_global_rect_inside(action, main, "%s %s" % [case_label, action_id])
	assert_eq(title.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, case_label)
	assert_lte(title.size.x, 280.5, case_label)
	assert_false(title.tooltip_text.is_empty(), case_label)
	_assert_text_height(title, case_label)
	_assert_text_height(status, case_label)

	var before_center := Vector2(120, -48)
	canvas.set_camera_zoom(0.75)
	canvas._center_on_world(before_center)
	main._toggle_inspector()
	await wait_process_frames(2)
	assert_true(inspector.visible, case_label)
	assert_eq(workspace.is_inspector_overlay(), window_size.x < 1440.0, case_label)
	assert_almost_eq(inspector.size.x, 360.0, 0.5, case_label)
	assert_almost_eq(inspector.get_rect().end.x, workspace.size.x, 0.5, case_label)
	if workspace.is_inspector_overlay():
		assert_almost_eq(canvas.size.x, workspace.size.x, 0.5, case_label)
	else:
		assert_almost_eq(canvas.size.x, workspace.size.x - 360.0, 0.5, case_label)
	assert_eq(canvas.camera_center, before_center, case_label)
	assert_almost_eq(canvas.camera_zoom, 0.75, 0.001, case_label)
	main._toggle_inspector()
	await wait_process_frames(1)
	assert_false(inspector.visible, case_label)
	assert_eq(canvas.camera_center, before_center, case_label)

	canvas.load_canvas_data({"camera": {"center": [12, 8], "zoom": 0.5}, "items": []})
	await wait_process_frames(1)
	var zoom_control: Control = canvas.get_node("ZoomControl")
	assert_almost_eq(canvas.camera_zoom, 0.5, 0.001, case_label)
	assert_eq(canvas.zoom_index, 2, case_label)
	assert_eq(int(zoom_control.get_node("ZoomRow/ZoomSlider").value), 2, case_label)
	assert_eq(zoom_control.get_node("ZoomRow/ZoomLabel").text, "50%", case_label)


func _assert_children_inside(parent: Control, label: String) -> void:
	for child in parent.get_children():
		if child is Control and child.visible:
			assert_gte(child.position.x, -0.5, "%s %s left" % [label, child.name])
			assert_gte(child.position.y, -0.5, "%s %s top" % [label, child.name])
			assert_lte(
				child.get_rect().end.x, parent.size.x + 0.5, "%s %s right" % [label, child.name]
			)
			assert_lte(
				child.get_rect().end.y, parent.size.y + 0.5, "%s %s bottom" % [label, child.name]
			)


func _assert_no_direct_child_overlap(parent: Control, label: String) -> void:
	var controls: Array[Control] = []
	for child in parent.get_children():
		if child is Control and child.visible:
			controls.append(child)
	for left_index in range(controls.size()):
		for right_index in range(left_index + 1, controls.size()):
			var overlap := controls[left_index].get_rect().intersection(
				controls[right_index].get_rect()
			)
			assert_lte(
				overlap.get_area(),
				0.5,
				"%s %s/%s" % [label, controls[left_index].name, controls[right_index].name]
			)


func _assert_global_rect_inside(control: Control, parent: Control, label: String) -> void:
	var rect := control.get_global_rect()
	var parent_rect := parent.get_global_rect()
	assert_gte(rect.position.x, parent_rect.position.x - 0.5, "%s left" % label)
	assert_gte(rect.position.y, parent_rect.position.y - 0.5, "%s top" % label)
	assert_lte(rect.end.x, parent_rect.end.x + 0.5, "%s right" % label)
	assert_lte(rect.end.y, parent_rect.end.y + 0.5, "%s bottom" % label)


func _assert_text_height(label_control: Label, label: String) -> void:
	var font := label_control.get_theme_font("font")
	var font_size := label_control.get_theme_font_size("font_size")
	assert_gte(label_control.size.y, font.get_height(font_size), label)


func _action_control(root: Node, action_id: String) -> Control:
	for node in root.find_children("*", "Control", true, false):
		if String(node.get_meta("action_id", "")) == action_id:
			return node
	return null


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
