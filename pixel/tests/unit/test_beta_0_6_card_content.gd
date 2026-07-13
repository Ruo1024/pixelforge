extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const StylePresetNodeScript := preload("res://core/graph/nodes/style_preset_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Beta 0.6 card content")
	AssetLibrary.clear()


func test_prompt_uses_five_line_draft_commit_and_escape_restore() -> void:
	var fixture := await _card(TextPromptNodeScript.new(), "prompt", {"text": "original"})
	var card: Node = fixture["card"]
	var edit: TextEdit = card.get_content_control("PromptEdit")
	edit.text = "committed draft"
	edit.text_changed.emit()
	assert_eq(card.get_content_control("PromptDraft").text, "Unsaved changes")
	assert_eq(card.get_content_control("PromptCharacterCount").text, "15 characters")
	var commit := InputEventKey.new()
	commit.keycode = KEY_ENTER
	commit.meta_pressed = true
	commit.pressed = true
	card._on_prompt_input(commit)
	assert_eq(fixture["commits"][-1][2], {"text": "committed draft"})
	edit.text = "discard me"
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	card._on_prompt_input(cancel)
	assert_eq(edit.text, "committed draft")
	assert_null(card.get_content_control("ApplyButton"))


func test_object_list_keeps_fifty_real_rows_inside_its_scroll_region() -> void:
	var rows := []
	for index in range(50):
		rows.append({"id": "row_%d" % index, "text": "object %d" % index, "count": 2, "enabled": true})
	var fixture := await _card(ObjectListNodeScript.new(), "objects", {"rows": rows})
	var card: Node = fixture["card"]
	assert_not_null(card.get_content_control("ObjectRowsScroll"))
	assert_eq(card.get_content_control("ObjectRows").get_child_count(), 50)
	assert_not_null(card.get_content_control("ObjectEnabled49"))
	assert_not_null(card.get_content_control("ObjectText49"))
	assert_not_null(card.get_content_control("ObjectCount49"))
	assert_not_null(card.get_content_control("ObjectMenu49"))
	assert_eq(card.get_content_control("ItemCount").text, "50/50 enabled · 100 expected results")
	assert_false(card.get_content_control("ObjectEdit").visible)


func test_style_palette_and_size_presets_are_visible_without_apply_buttons() -> void:
	var style := await _card(
		StylePresetNodeScript.new(),
		"style",
		{
			"preset": {
				"name": "Original",
				"base_size": 32,
				"palette": {"colors": ["#111111", "#ffffff", "#6fa8ff"]},
			}
		}
	)
	assert_eq(style["card"].get_content_control("PaletteStrip").get_child_count(), 3)
	var size := await _card(
		SizeSpecNodeScript.new(), "size", {"width": 32, "height": 24, "per_subject": 1}
	)
	var size_card: Node = size["card"]
	assert_eq(size_card.get_content_control("SizeHero").text, "32 × 24 px")
	(size_card.get_content_control("SizePreset64") as Button).pressed.emit()
	assert_eq(size["commits"][-1][2], {"width": 64, "height": 64, "per_subject": 1})
	assert_null(size_card.get_content_control("ApplyButton"))


func test_generate_card_has_one_primary_action_for_every_frozen_state() -> void:
	var fixture := await _card(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 2, "seed": 1}
	)
	var card: Node = fixture["card"]
	var primary: Button = card.get_content_control("PrimaryActionButton")
	assert_not_null(primary)
	assert_null(card.get_content_control("CancelButton"))
	assert_false(card.get_content_control("AdvancedSettings").visible)
	var cases := [
		["CONTENT_STATUS_INCOMPLETE", "Fix input", "fix_input", false],
		["CONTENT_STATUS_READY", "Generate", "run", false],
		["CONTENT_STATUS_QUEUED", "Cancel", "cancel", false],
		["CONTENT_STATUS_RUNNING", "Cancel", "cancel", false],
		["CONTENT_STATUS_CANCELING", "Stopping…", "", true],
		["CONTENT_STATUS_COMPLETE", "Generate again", "run", false],
		["CONTENT_STATUS_PARTIAL", "Retry failed items", "retry_failed", false],
		["CONTENT_STATUS_FAILED", "Retry", "retry", false],
		["CONTENT_STATUS_CANCELED", "Generate again", "run", false],
	]
	for spec in cases:
		card.set_execution_status(spec[0])
		assert_eq(primary.text, spec[1])
		assert_eq(primary.disabled, spec[3])
		if not String(spec[2]).is_empty():
			primary.pressed.emit()
			assert_eq(fixture["actions"][-1][2], spec[2])


func _card(node: PFNode, node_id: String, params: Dictionary) -> Dictionary:
	var graph := GraphScript.new()
	graph.id = "graph_%s" % node_id
	graph.add_node(node, node_id, params, Vector2.ZERO)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var commits := []
	var actions := []
	canvas.graph_node_params_commit_requested.connect(
		func(graph_id: String, committed_node_id: String, committed: Dictionary) -> void:
			commits.append([graph_id, committed_node_id, committed])
	)
	canvas.graph_node_action_requested.connect(
		func(graph_id: String, committed_node_id: String, action_id: String) -> void:
			actions.append([graph_id, committed_node_id, action_id])
	)
	var card: Node = canvas._add_graph_node_card(
		graph.id, node_id, Vector2.ZERO, "item_%s" % node_id, false
	)
	return {"canvas": canvas, "card": card, "commits": commits, "actions": actions}
