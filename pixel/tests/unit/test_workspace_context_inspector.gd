extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const InspectorScript := preload("res://ui/inspector/workspace_context_inspector.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Candidate inspector")
	AssetLibrary.clear()


func test_single_candidate_maps_safe_snapshot_and_emits_safe_action_context() -> void:
	var asset_id := _register_candidate(
		"candidate-a",
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"prompt": "tiny forest shrine",
			"negative_prompt": "blur",
			"style": {"preset_id": "nes", "api_key": "nested-must-not-leak"},
			"width": 1024,
			"height": 1024,
			"seed": 0,
			"reference_asset_ids": ["reference-a", "reference-b"],
			"reference_content_sha256s": ["hash-a", "hash-b"],
			"source_generate_node_id": "generate-cloud",
			"run_id": "run-safe",
			"cost": 0.042,
			"created_at": "2026-07-13T08:00:00Z",
			"api_key": "must-not-leak",
			"external_response": {"raw": "must-not-leak"},
		},
	)
	var fixture := await _make_inspector_with_batch([asset_id], [asset_id])
	var inspector: Control = fixture["inspector"]
	var panel: Control = inspector.get_node("ContextRoot/CandidatePanel")

	assert_true(panel.visible)
	assert_eq(_row_value(panel, "Prompt"), "tiny forest shrine")
	assert_eq(_row_value(panel, "Model"), "gpt-image-2")
	assert_eq(_row_value(panel, "Seed"), "0")
	assert_eq(_row_value(panel, "Size"), "1024×1024")
	assert_true(_row_value(panel, "References").contains("reference-a, reference-b"))
	assert_eq(_row_value(panel, "Cost"), "$0.0420")
	assert_eq(_row_value(panel, "CreatedAt"), "2026-07-13T08:00:00Z")
	assert_eq(_row_value(panel, "Source"), "generate-cloud")
	assert_false(_all_label_text(panel).contains("must-not-leak"))
	assert_true(inspector.get_node("ContextRoot/CleanupInspector").visible)

	watch_signals(inspector)
	(panel.get_node("CandidateActions/CopySettingsButton") as Button).pressed.emit()
	var expected_snapshot: Dictionary = fixture["snapshot"]
	expected_snapshot.erase("api_key")
	expected_snapshot.erase("external_response")
	expected_snapshot["style"].erase("api_key")
	var expected_context := {
		"snapshot": expected_snapshot,
		"asset_ids": [asset_id],
		"graph_id": "graph-main",
		"batch_node_id": "batch-results",
	}
	assert_signal_emitted_with_parameters(
		inspector, "candidate_action_requested", ["copy_settings", expected_context]
	)
	assert_false(JSON.stringify(expected_context).contains("must-not-leak"))
	LocalizationService.set_language("zh_CN")
	assert_eq((panel.get_node("CandidateActions/CopyPromptButton") as Button).text, "复制提示词")


func test_multiple_candidates_only_offer_reference_and_continue_actions() -> void:
	var first_id := _register_candidate("first", {"prompt": "first", "model_id": "model-a"})
	var second_id := _register_candidate("second", {"prompt": "second", "model_id": "model-b"})
	var fixture := await _make_inspector_with_batch([first_id, second_id], [first_id, second_id])
	var panel: Control = fixture["inspector"].get_node("ContextRoot/CandidatePanel")
	var actions: Control = panel.get_node("CandidateActions")

	assert_eq((panel.get_node("CandidateSummary") as Label).text, "2 candidates selected")
	assert_false((actions.get_node("CopyPromptButton") as Button).visible)
	assert_false((actions.get_node("CopySettingsButton") as Button).visible)
	assert_false((actions.get_node("RerunButton") as Button).visible)
	assert_true((actions.get_node("AsReferenceButton") as Button).visible)
	assert_true((actions.get_node("ContinueBranchButton") as Button).visible)
	assert_false((actions.get_node("AsReferenceButton") as Button).disabled)
	assert_false((actions.get_node("ContinueBranchButton") as Button).disabled)


func test_missing_snapshot_degrades_without_empty_detail_rows() -> void:
	var asset_id := _register_candidate("legacy", {}, false)
	var fixture := await _make_inspector_with_batch([asset_id], [asset_id])
	var panel: Control = fixture["inspector"].get_node("ContextRoot/CandidatePanel")
	var actions: Control = panel.get_node("CandidateActions")

	assert_eq(
		(panel.get_node("CandidateSummary") as Label).text,
		"Generation details are unavailable for this older result.",
	)
	for row_name in [
		"PromptRow",
		"ModelRow",
		"SeedRow",
		"SizeRow",
		"ReferencesRow",
		"CostRow",
		"CreatedAtRow",
		"SourceRow",
	]:
		assert_false((panel.get_node(row_name) as Control).visible)
	assert_true((actions.get_node("CopyPromptButton") as Button).disabled)
	assert_true((actions.get_node("CopySettingsButton") as Button).disabled)
	assert_true((actions.get_node("RerunButton") as Button).disabled)
	assert_false((actions.get_node("AsReferenceButton") as Button).disabled)
	assert_true((actions.get_node("ContinueBranchButton") as Button).disabled)


func test_canvas_change_refreshes_the_selected_candidate_detail() -> void:
	var first_id := _register_candidate("first", {"prompt": "first", "model_id": "model-a"})
	var second_id := _register_candidate("second", {"prompt": "second", "model_id": "model-b"})
	var fixture := await _make_inspector_with_batch([first_id, second_id], [first_id])
	var panel: Control = fixture["inspector"].get_node("ContextRoot/CandidatePanel")
	var card: Node = fixture["card"]
	var canvas: Control = fixture["canvas"]

	assert_eq(_row_value(panel, "Model"), "model-a")
	card._set_selected_asset_ids([second_id])
	canvas.canvas_changed.emit()
	assert_eq(_row_value(panel, "Model"), "model-b")


func _make_inspector_with_batch(asset_ids: Array, selected_ids: Array) -> Dictionary:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	var inspector: Control = InspectorScript.new()
	add_child_autofree(inspector)
	await wait_process_frames(2)
	var card: Node = canvas._add_batch_card(
		asset_ids, Vector2(24, 24), "Candidates", "batch-item", false
	)
	card.graph_id = "graph-main"
	card.node_id = "batch-results"
	card._set_selected_asset_ids(selected_ids)
	canvas.select_ids([card.item_id])
	inspector.show_canvas_selection(canvas)
	return {
		"canvas": canvas,
		"card": card,
		"inspector": inspector,
		"snapshot":
		_snapshot_for_asset(String(selected_ids[0])) if selected_ids.size() == 1 else {},
	}


func _register_candidate(
	name: String, snapshot: Dictionary, include_snapshot: bool = true
) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.DARK_ORANGE)
	var provenance := {"created_at": "legacy-time"}
	if include_snapshot:
		provenance["generation_snapshot"] = snapshot.duplicate(true)
	return AssetLibrary.register_image(
		image, name, {"origin": "generated", "provenance": provenance}
	)


func _snapshot_for_asset(asset_id: String) -> Dictionary:
	return AssetLibrary.get_asset_meta(asset_id).get("provenance", {}).get(
		"generation_snapshot", {}
	)


func _row_value(panel: Control, field_name: String) -> String:
	return String((panel.get_node("%sRow/FieldValue" % field_name) as Label).text)


func _all_label_text(node: Node) -> String:
	var values: Array[String] = []
	if node is Label:
		values.append((node as Label).text)
	for child in node.get_children():
		values.append(_all_label_text(child))
	return "\n".join(values)
