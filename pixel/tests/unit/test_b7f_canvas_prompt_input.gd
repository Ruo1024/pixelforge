extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("B7F prompt input")


func test_prompt_wraps_english_chinese_japanese_and_unspaced_text_without_mutation() -> void:
	var fixture := await _prompt_card("stored")
	var card: Node = fixture["card"]
	var edit: TextEdit = card.get_content_control("PromptEdit")
	var lines := [
		"English words need to wrap inside the prompt editor boundary ".repeat(5),
		"中文长提示词需要在输入框边界内自动换行".repeat(10),
		"日本語の長いプロンプトも入力欄の境界で折り返す".repeat(10),
		"unspaced".repeat(50),
	]
	var exact_text := "\n".join(lines)
	edit.text = exact_text
	edit.text_changed.emit()
	await wait_process_frames(2)

	assert_eq(edit.wrap_mode, TextEdit.LINE_WRAPPING_BOUNDARY)
	assert_eq(edit.autowrap_mode, TextServer.AUTOWRAP_ARBITRARY)
	assert_eq(edit.scroll_horizontal, 0)
	assert_false(edit.get_h_scroll_bar().visible)
	for line_index in range(lines.size()):
		assert_gt(edit.get_line_wrap_count(line_index), 0, "line %d wraps" % line_index)
	card._commit_text_prompt(edit)
	assert_eq(fixture["commits"], [{"text": exact_text}])
	assert_eq(edit.text, exact_text, "visual wrapping never inserts storage newlines")


func test_same_lod_keeps_content_identity_focus_and_uncommitted_prompt_draft() -> void:
	var fixture := await _prompt_card("original")
	var card: Node = fixture["card"]
	var content: Control = card.get_node("Content")
	var edit: TextEdit = card.get_content_control("PromptEdit")
	edit.text = "draft stays local"
	edit.text_changed.emit()
	edit.grab_focus()
	await wait_process_frames(1)

	for zoom in [1.5, 2.0, 4.0, 0.75, 1.0]:
		card.set_lod_camera_zoom(zoom)
		assert_same(card.get_node("Content"), content, "content identity at zoom %s" % zoom)
		assert_same(card.get_content_control("PromptEdit"), edit)
		assert_eq(edit.text, "draft stays local")
		assert_true(edit.has_focus())
	assert_true(fixture["commits"].is_empty(), "LOD changes do not commit a draft")


func test_refresh_restores_prompt_focus_draft_and_scroll_position() -> void:
	var fixture := await _prompt_card("original")
	var card: Node = fixture["card"]
	var edit: TextEdit = card.get_content_control("PromptEdit")
	var draft := "\n".join(
		range(40).map(func(index: int) -> String: return "draft line %d" % index)
	)
	edit.text = draft
	edit.text_changed.emit()
	await wait_process_frames(2)
	edit.set_caret_line(30)
	edit.set_caret_column(8)
	edit.scroll_vertical = 24.0
	edit.grab_focus()
	await wait_process_frames(1)

	card.refresh_from_graph()
	await wait_process_frames(2)
	var replacement: TextEdit = card.get_content_control("PromptEdit")
	assert_ne(replacement, edit)
	assert_eq(replacement.text, draft)
	assert_true(replacement.has_focus())
	assert_eq(replacement.get_caret_line(), 30)
	assert_eq(replacement.get_caret_column(), 8)
	assert_gt(replacement.scroll_vertical, 0.0)
	assert_true(fixture["commits"].is_empty())


func test_plain_wheel_and_trackpad_scroll_are_owned_even_at_prompt_boundary() -> void:
	var fixture := await _prompt_card("original")
	var canvas: Control = fixture["canvas"]
	var card: Node = fixture["card"]
	var edit: TextEdit = card.get_content_control("PromptEdit")
	edit.text = "draft " + "scroll ".repeat(100)
	edit.text_changed.emit()
	edit.scroll_vertical = 100000.0
	edit.grab_focus()
	await wait_process_frames(1)
	var boundary_scroll := edit.scroll_vertical
	var zoom_before: float = canvas.camera_zoom
	var center_before: Vector2 = canvas.camera_center

	for _attempt in range(10):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		assert_true(card._is_plain_internal_scroll_event(wheel))
		card._on_internal_scroll_input(wheel, edit)
	var trackpad := InputEventPanGesture.new()
	trackpad.delta = Vector2(0, 12)
	assert_true(card._is_plain_internal_scroll_event(trackpad))
	card._on_internal_scroll_input(trackpad, edit)

	assert_eq(canvas.camera_zoom, zoom_before)
	assert_eq(canvas.camera_center, center_before)
	assert_eq(edit.scroll_vertical, boundary_scroll)
	assert_true(edit.has_focus())
	assert_eq(edit.text, "draft " + "scroll ".repeat(100))
	assert_true(fixture["commits"].is_empty())


func test_zoom_modifier_is_not_claimed_by_internal_scroll_owner() -> void:
	var fixture := await _prompt_card("original")
	var card: Node = fixture["card"]
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	assert_false(card._is_plain_internal_scroll_event(wheel))


func _prompt_card(text: String) -> Dictionary:
	(
		ProjectService
		. set_graph_data(
			"prompt_graph",
			{
				"graph_version": 2,
				"id": "prompt_graph",
				"name": "Prompt",
				"nodes": [{"id": "prompt", "type": "text_prompt", "params": {"text": text}}],
				"edges": [],
			},
			false
		)
	)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var commits := []
	canvas.graph_node_params_commit_requested.connect(
		func(_graph_id: String, _node_id: String, params: Dictionary) -> void:
			commits.append(params.duplicate(true))
	)
	var card: Node = canvas._add_graph_node_card(
		"prompt_graph", "prompt", Vector2.ZERO, "prompt_item", false
	)
	await wait_process_frames(2)
	return {"canvas": canvas, "card": card, "commits": commits}
