extends "res://addons/gut/test.gd"

const VIEW_PATH := "res://ui/canvas/cleanup_card_view.gd"
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const InspectorScript := preload("res://ui/inspector/cleanup_inspector.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_compact_bounds_have_no_internal_body_scroll() -> void:
	var view: Control = await _view()
	if view == null:
		return
	var script: Variant = load(VIEW_PATH)
	assert_eq(script.DEFAULT_SIZE, Vector2i(420, 360))
	assert_eq(script.MIN_SIZE, Vector2i(360, 300))
	assert_eq(script.MAX_SIZE, Vector2i(800, 720))
	assert_eq(script.HEADER_HEIGHT, 40)
	assert_eq(script.STATUS_HEIGHT, 32)
	assert_eq(script.FOOTER_HEIGHT, 56)
	assert_eq(CardContract.default_size_for_type("pixel_cleanup"), Vector2i(420, 360))
	assert_eq(CardContract.minimum_size_for_type("pixel_cleanup"), Vector2i(360, 300))
	assert_eq(
		CardContract.normalize_requested_size("pixel_cleanup", [900, 1200]), Vector2i(800, 720)
	)
	assert_null(view.get_node_or_null("BodyScroll"))
	assert_not_null(view.get_node("SummaryGroup/SettingsButton"))


func test_all_groups_footer_only_and_runtime_refresh() -> void:
	var view: Control = await _view()
	if view == null:
		return
	assert_eq(view.get_group_ids(), ["run_status", "summary", "settings", "footer"])
	assert_null(view.find_child("Execute", true, false))
	var footer: Button = view.get_node("Footer/PrimaryAction")
	assert_eq(footer.text, "Start cleanup")
	var actions := []
	view.action_requested.connect(func(action: String) -> void: actions.append(action))
	footer.pressed.emit()
	assert_eq(actions, ["run_cleanup"])
	view.get_node("SummaryGroup/SettingsButton").pressed.emit()
	assert_eq(actions, ["run_cleanup", "open_settings"])
	var instance_id := view.get_instance_id()
	LocalizationService.set_language("zh_CN")
	await wait_process_frames(1)
	assert_eq(view.get_instance_id(), instance_id)
	assert_eq(view.get_node("Footer/PrimaryAction").text, "开始清洗")


func _view() -> Control:
	assert_true(ResourceLoader.exists(VIEW_PATH), "B7-6 must add the cleanup card")
	if not ResourceLoader.exists(VIEW_PATH):
		return null
	var view: Control = load(VIEW_PATH).new()
	view.size = Vector2(420, 640)
	add_child_autofree(view)
	view.configure(
		{
			"params": {"preset_id": "cleanup-16bit-db32", "settings": {}},
			"run": {"state": "Ready"},
			"input": {"kind": "Output", "count": 2, "target": "32×32"}
		}
	)
	await wait_process_frames(1)
	return view


func test_inspector_roundtrips_every_setting_and_never_exposes_run_actions() -> void:
	var inspector: Control = InspectorScript.new()
	add_child_autofree(inspector)
	await wait_process_frames(1)
	var params := CleanupNodeScript.new().validate_params({})
	inspector.configure_node("graph-a", "cleanup-a", params)
	assert_eq(inspector.get_node_params(), params)
	assert_not_null(inspector.get_node("InspectorRoot/CleanupScroll"))
	assert_not_null(inspector.find_child("BaseSizeReadOnly", true, false))
	assert_null(inspector.find_child("ApplyCleanupButton", true, false))
	assert_null(inspector.find_child("CancelCleanupButton", true, false))
	assert_false(
		FileAccess.get_file_as_string("res://ui/inspector/cleanup_inspector.gd").contains(
			"Timer.new"
		)
	)


func test_inspector_commits_node_settings_once_and_blocks_changes_while_running() -> void:
	var inspector: Control = InspectorScript.new()
	add_child_autofree(inspector)
	await wait_process_frames(1)
	inspector.configure_node("graph-a", "cleanup-a", CleanupNodeScript.new().validate_params({}))
	watch_signals(inspector)
	var scale: SpinBox = inspector.find_child("ScaleSpin", true, false)
	assert_not_null(scale)
	scale.value = 5.0
	assert_signal_emit_count(inspector, "params_commit_requested", 1)
	var committed: Array = get_signal_parameters(inspector, "params_commit_requested", 0)
	assert_eq(committed[0], "graph-a")
	assert_eq(committed[1], "cleanup-a")
	assert_eq(committed[2]["preset_id"], "")
	inspector.set_cleanup_running(true)
	scale.value = 6.0
	assert_signal_emit_count(inspector, "params_commit_requested", 1)
