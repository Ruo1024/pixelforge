extends "res://addons/gut/test.gd"

const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const MainScene := preload("res://ui/shell/main.tscn")

const BASE_LOGICAL_SIZE := Vector2i(1080, 560)
const EXPANDED_LOGICAL_SIZE := Vector2i(1280, 720)
const WINDOW_FACTORS := [1.0, 1.25, 1.5, 2.0]
const WORKSPACE_SIZES := [
	Vector2i(1080, 560),
	Vector2i(1280, 720),
	Vector2i(1440, 900),
	Vector2i(1080, 560),
]
const ACTION_IDS := [
	"file",
	"undo",
	"redo",
	"add_input",
	"import_reference",
	"run_selection",
	"export",
	"inspector",
	"more",
]
const ADAPTIVE_ACTION_IDS := ["undo", "redo", "inspector"]
const INTERNAL_RETINA_SNAPSHOT := {
	"screen": 0,
	"reported_scale": 2.0,
	"max_scale": 2.0,
	"screen_dpi": 220,
	"screen_size": Vector2i(1440, 778),
	"usable_size": Vector2i(1440, 778),
	"display_server": "macOS",
}
const EXTERNAL_NATIVE_SNAPSHOT := {
	"screen": 1,
	"reported_scale": 1.0,
	"max_scale": 2.0,
	"screen_dpi": 110,
	"screen_size": Vector2i(4650, 2825),
	"usable_size": Vector2i(4650, 2825),
	"display_server": "macOS",
}

var _root_state := {}
var _setting_states := {}
var _previous_pending_recovery: Array = []
var _main: Control = null
var _input_sender: GutInputSender = null
var _recovery_path := ""
var _recovery_dir := ""


func before_each() -> void:
	_root_state = _snapshot_root_window()
	_setting_states = {
		"interface_scale": _snapshot_setting("ui", "interface_scale"),
		"onboarding_complete": _snapshot_setting("onboarding", "v1_complete"),
	}
	_previous_pending_recovery = ProjectService._pending_recovery_autosaves.duplicate()
	ProjectService._pending_recovery_autosaves = []
	SettingsService.set_setting("onboarding", "v1_complete", true, false)
	get_tree().root.gui_embed_subwindows = true
	ProjectService.new_project("Adaptive shell window test")


func after_each() -> void:
	if _input_sender != null:
		_input_sender.release_all()
		_input_sender.clear()
		_input_sender = null
		await wait_process_frames(1)
	if is_instance_valid(_main):
		_main.queue_free()
		await wait_process_frames(2)
	_main = null
	_cleanup_recovery_fixture()
	ProjectService.new_project("Adaptive shell test cleanup")
	ProjectService._pending_recovery_autosaves = _previous_pending_recovery.duplicate()
	_restore_setting("ui", "interface_scale", _setting_states["interface_scale"])
	_restore_setting("onboarding", "v1_complete", _setting_states["onboarding_complete"])
	_restore_root_window(_root_state)
	await wait_process_frames(2)


func test_macos_display_snapshot_round_trip_is_idempotent() -> void:
	var internal_first := InterfaceScalePolicy.resolve_from_snapshot(
		INTERNAL_RETINA_SNAPSHOT, 0.0, "macOS"
	)
	var external := InterfaceScalePolicy.resolve_from_snapshot(
		EXTERNAL_NATIVE_SNAPSHOT, 0.0, "macOS"
	)
	var internal_again := InterfaceScalePolicy.resolve_from_snapshot(
		INTERNAL_RETINA_SNAPSHOT, 0.0, "macOS"
	)

	assert_almost_eq(float(internal_first["resolved"]), 2.0, 0.001)
	assert_almost_eq(float(internal_first["window_pixel_scale"]), 2.0, 0.001)
	assert_almost_eq(float(external["resolved"]), 2.0, 0.001)
	assert_almost_eq(float(external["window_pixel_scale"]), 2.0, 0.001)
	assert_eq(external["resolved"], internal_first["resolved"])
	assert_eq(external["window_pixel_scale"], internal_first["window_pixel_scale"])
	assert_eq(
		internal_again, internal_first, "Returning to the Retina screen must not accumulate scale"
	)


func test_real_root_resize_increases_visible_logical_area_at_each_factor() -> void:
	var root := get_tree().root
	for factor in WINDOW_FACTORS:
		await _configure_real_root(BASE_LOGICAL_SIZE, factor)
		_assert_root_scale_state(BASE_LOGICAL_SIZE, factor, "baseline @ %.2f" % factor)
		var before_resize := root.get_visible_rect().size

		root.size = _physical_size(EXPANDED_LOGICAL_SIZE, factor)
		await wait_process_frames(2)
		_assert_root_scale_state(EXPANDED_LOGICAL_SIZE, factor, "expanded @ %.2f" % factor)
		var after_resize := root.get_visible_rect().size
		assert_gt(after_resize.x, before_resize.x, "Resize must add horizontal workspace")
		assert_gt(after_resize.y, before_resize.y, "Resize must add vertical workspace")


func test_real_root_two_x_reflows_workspace_sizes_and_returns_to_compact() -> void:
	_main = await _make_main(BASE_LOGICAL_SIZE, 2.0)
	var visited_modes: Array[String] = []

	for logical_size in WORKSPACE_SIZES:
		get_tree().root.size = _physical_size(logical_size, 2.0)
		await wait_process_frames(3)
		_assert_root_scale_state(logical_size, 2.0, "workspace %s" % logical_size)
		var compact: bool = logical_size.x <= 1180
		_assert_workspace_layout(_main, logical_size, compact)
		visited_modes.append(String(_main.get_node("Root/TopBar").get_meta("layout_mode", "")))

	assert_eq(visited_modes, ["compact", "standard", "standard", "compact"])


func test_recovery_dialog_ok_uses_real_root_hit_test_at_two_x() -> void:
	_recovery_path = _create_recovery_fixture()
	assert_false(_recovery_path.is_empty())
	ProjectService.new_project("Clean recovery target")
	_main = await _make_main(BASE_LOGICAL_SIZE, 2.0)
	_main.call("_on_recovery_available", [_recovery_path])
	await wait_process_frames(3)

	var dialog: ConfirmationDialog = _main.get_node("RecoveryDialog")
	assert_true(dialog.visible)
	assert_true(dialog.is_embedded(), "The modal must use the root viewport hit-test path")
	watch_signals(dialog)
	await _click_control_through_root(dialog.get_ok_button())

	assert_signal_emitted(dialog, "confirmed")
	assert_eq(ProjectService.current_project.recovered_from_path, _recovery_path)
	assert_eq(ProjectService.current_project.project_path, "")
	assert_true(ProjectService.current_project.dirty)
	assert_eq(_main._pending_recovery_path, "")
	assert_false(dialog.visible)


func _make_main(logical_size: Vector2i, factor: float) -> Control:
	SettingsService.set_setting("ui", "interface_scale", factor, false)
	await _configure_real_root(logical_size, factor)
	var main := MainScene.instantiate() as Control
	add_child(main)
	await wait_process_frames(3)
	return main


func _configure_real_root(logical_size: Vector2i, factor: float) -> void:
	var root := get_tree().root
	InterfaceScalePolicy.apply_content_scale_policy(root, factor)
	root.size = _physical_size(logical_size, factor)
	await wait_process_frames(2)


func _assert_root_scale_state(logical_size: Vector2i, factor: float, label: String) -> void:
	var root := get_tree().root
	assert_eq(root.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, label)
	assert_eq(root.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_IGNORE, label)
	assert_eq(root.content_scale_size, Vector2i.ZERO, label)
	assert_almost_eq(root.content_scale_factor, factor, 0.001, label)
	assert_eq(root.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL, label)
	assert_eq(root.size, _physical_size(logical_size, factor), label)
	var visible_size := root.get_visible_rect().size
	assert_almost_eq(visible_size.x, float(logical_size.x), 0.51, label)
	assert_almost_eq(visible_size.y, float(logical_size.y), 0.51, label)


func _assert_workspace_layout(main: Control, logical_size: Vector2i, compact: bool) -> void:
	var label := "%s %s" % [logical_size, "compact" if compact else "standard"]
	var top_bar: Control = main.get_node("Root/TopBar")
	assert_almost_eq(main.size.x, float(logical_size.x), 0.51, label)
	assert_almost_eq(main.size.y, float(logical_size.y), 0.51, label)
	assert_eq(String(top_bar.get_meta("layout_mode", "")), "compact" if compact else "standard")
	assert_almost_eq(top_bar.size.y, 52.0, 0.5, label)
	_assert_no_direct_child_overlap(top_bar, label)

	for action_id in ACTION_IDS:
		assert_eq(_action_count(main, action_id), 1, "%s %s count" % [label, action_id])
		var action := _action_control(main, action_id)
		assert_not_null(action, "%s %s" % [label, action_id])
		if action != null:
			assert_true(action.visible, "%s %s visible" % [label, action_id])
			_assert_global_rect_inside(action, main, "%s %s" % [label, action_id])

	for action_id in ADAPTIVE_ACTION_IDS:
		var button := _action_control(main, action_id) as Button
		assert_not_null(button, "%s %s" % [label, action_id])
		if button != null:
			assert_eq(button.text.is_empty(), compact, "%s %s label" % [label, action_id])
			assert_false(button.tooltip_text.is_empty(), "%s %s tooltip" % [label, action_id])
			assert_gte(button.size.x, 32.0, "%s %s width" % [label, action_id])
			assert_gte(button.size.y, 32.0, "%s %s height" % [label, action_id])

	for persistent_label_action in ["run_selection", "export"]:
		var button := _action_control(main, persistent_label_action) as Button
		assert_not_null(button, "%s %s" % [label, persistent_label_action])
		if button != null:
			assert_false(button.text.is_empty(), "%s %s label" % [label, persistent_label_action])


func _click_control_through_root(control: Control) -> void:
	var root := get_tree().root
	var popup := control.get_window()
	var popup_point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var root_logical_point := Vector2(popup.position) + popup_point
	var root_window_point := root.get_final_transform() * root_logical_point
	assert_true(
		Rect2(Vector2.ZERO, Vector2(root.size)).has_point(root_window_point),
		"Raw click must be inside the physical root Window",
	)

	_input_sender = GutInputSender.new(Input)
	_input_sender.draw_mouse = false
	_input_sender.mouse_warp = false
	_input_sender.set_auto_flush_input(true)

	var motion := InputEventMouseMotion.new()
	motion.position = root_window_point
	motion.global_position = root_window_point
	motion.window_id = root.get_window_id()
	_input_sender.send_event(motion)
	await wait_process_frames(1)

	var down := InputEventMouseButton.new()
	down.position = root_window_point
	down.global_position = root_window_point
	down.window_id = root.get_window_id()
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	_input_sender.send_event(down)
	await wait_process_frames(1)

	var up := down.duplicate() as InputEventMouseButton
	up.button_mask = 0
	up.pressed = false
	_input_sender.send_event(up)
	await wait_process_frames(4)


func _create_recovery_fixture() -> String:
	ProjectService.new_project("Recovery click source")
	var source_id: String = ProjectService.current_project.get_id()
	ProjectService.set_canvas_data({"camera": {"center": [99, 42], "zoom": 2.0}, "items": []}, true)
	var error: Error = ProjectService.autosave_now()
	assert_eq(error, OK, "Recovery fixture autosave failed: %s" % error_string(error))
	var autosaves: Array = ProjectService.list_autosaves(source_id)
	assert_false(autosaves.is_empty(), "Recovery fixture autosave was not listed")
	if autosaves.is_empty():
		return ""
	_recovery_dir = "user://autosave/%s" % source_id
	return String(autosaves.back())


func _cleanup_recovery_fixture() -> void:
	if not _recovery_path.is_empty() and FileAccess.file_exists(_recovery_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_recovery_path))
	if (
		not _recovery_dir.is_empty()
		and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_recovery_dir))
	):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_recovery_dir))
	_recovery_path = ""
	_recovery_dir = ""


func _physical_size(logical_size: Vector2i, factor: float) -> Vector2i:
	return Vector2i(
		int(round(float(logical_size.x) * factor)),
		int(round(float(logical_size.y) * factor)),
	)


func _action_control(root: Node, action_id: String) -> Control:
	for node in root.find_children("*", "Control", true, false):
		if String(node.get_meta("action_id", "")) == action_id:
			return node as Control
	return null


func _action_count(root: Node, action_id: String) -> int:
	var count := 0
	for node in root.find_children("*", "Control", true, false):
		if String(node.get_meta("action_id", "")) == action_id:
			count += 1
	return count


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
				"%s %s/%s" % [label, controls[left_index].name, controls[right_index].name],
			)


func _assert_global_rect_inside(control: Control, parent: Control, label: String) -> void:
	var rect := control.get_global_rect()
	var parent_rect := parent.get_global_rect()
	assert_gte(rect.position.x, parent_rect.position.x - 0.5, "%s left" % label)
	assert_gte(rect.position.y, parent_rect.position.y - 0.5, "%s top" % label)
	assert_lte(rect.end.x, parent_rect.end.x + 0.5, "%s right" % label)
	assert_lte(rect.end.y, parent_rect.end.y + 0.5, "%s bottom" % label)


func _snapshot_root_window() -> Dictionary:
	var root := get_tree().root
	return {
		"size": root.size,
		"position": root.position,
		"min_size": root.min_size,
		"max_size": root.max_size,
		"content_scale_mode": root.content_scale_mode,
		"content_scale_aspect": root.content_scale_aspect,
		"content_scale_size": root.content_scale_size,
		"content_scale_factor": root.content_scale_factor,
		"content_scale_stretch": root.content_scale_stretch,
		"gui_embed_subwindows": root.gui_embed_subwindows,
		"auto_accept_quit": get_tree().auto_accept_quit,
	}


func _restore_root_window(state: Dictionary) -> void:
	var root := get_tree().root
	root.content_scale_mode = int(state["content_scale_mode"])
	root.content_scale_aspect = int(state["content_scale_aspect"])
	root.content_scale_size = Vector2i(state["content_scale_size"])
	root.content_scale_factor = float(state["content_scale_factor"])
	root.content_scale_stretch = int(state["content_scale_stretch"])
	root.size = Vector2i(state["size"])
	root.position = Vector2i(state["position"])
	root.min_size = Vector2i(state["min_size"])
	root.max_size = Vector2i(state["max_size"])
	root.gui_embed_subwindows = bool(state["gui_embed_subwindows"])
	get_tree().auto_accept_quit = bool(state["auto_accept_quit"])


func _snapshot_setting(section: String, key: String) -> Dictionary:
	var exists := SettingsService._config.has_section_key(section, key)
	return {
		"exists": exists,
		"value": SettingsService.get_setting(section, key) if exists else null,
	}


func _restore_setting(section: String, key: String, state: Dictionary) -> void:
	if bool(state["exists"]):
		SettingsService.set_setting(section, key, state["value"], false)
	else:
		SettingsService._config.erase_section_key(section, key)
