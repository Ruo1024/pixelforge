extends "res://addons/gut/test.gd"

const VIEW_PATH := "res://ui/canvas/cleanup_card_view.gd"
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_fixed_bounds_and_scroll_regions() -> void:
	var view: Control = await _view()
	if view == null:
		return
	var script: Variant = load(VIEW_PATH)
	assert_eq(script.DEFAULT_SIZE, Vector2i(420, 680))
	assert_eq(script.MIN_SIZE, Vector2i(360, 480))
	assert_eq(script.MAX_SIZE, Vector2i(800, 1000))
	assert_eq(script.HEADER_HEIGHT, 40)
	assert_eq(script.STATUS_HEIGHT, 32)
	assert_eq(script.FOOTER_HEIGHT, 56)
	assert_eq(CardContract.default_size_for_type("pixel_cleanup"), Vector2i(420, 680))
	assert_eq(CardContract.minimum_size_for_type("pixel_cleanup"), Vector2i(360, 480))
	assert_eq(
		CardContract.normalize_requested_size("pixel_cleanup", [900, 1200]), Vector2i(800, 1000)
	)
	var body: ScrollContainer = view.get_node("BodyScroll")
	assert_false(body.is_ancestor_of(view.get_node("RunStatusGroup")))
	assert_false(body.is_ancestor_of(view.get_node("Footer")))


func test_all_groups_footer_only_and_runtime_refresh() -> void:
	var view: Control = await _view()
	if view == null:
		return
	assert_eq(
		view.get_group_ids(),
		[
			"run_status",
			"input_summary",
			"preset",
			"grid",
			"resample",
			"quantize",
			"last_report",
			"footer"
		]
	)
	assert_null(view.find_child("Execute", true, false))
	var footer: Button = view.get_node("Footer/PrimaryAction")
	assert_eq(footer.text, "Start cleanup")
	var actions := []
	view.action_requested.connect(func(action: String) -> void: actions.append(action))
	footer.pressed.emit()
	assert_eq(actions, ["run_cleanup"])
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
