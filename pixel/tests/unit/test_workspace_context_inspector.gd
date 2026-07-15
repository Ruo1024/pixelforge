extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const InspectorScript := preload("res://ui/inspector/workspace_context_inspector.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


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
			"mode": "txt2img",
			"prompt": "tiny forest shrine",
			"target_width": 32,
			"target_height": 32,
			"provider_output_size": [1024, 1024],
			"actual_width": 1024,
			"actual_height": 1024,
			"requested_seed": -1,
			"actual_seed": 0,
			"reference_asset_ids": ["reference-a", "reference-b"],
			"reference_content_sha256s": ["a".repeat(64), "b".repeat(64)],
			"source_node_id": "generate-cloud",
			"run_id": "run-safe",
			"request_id": "request-safe",
			"extra": {"quality": "low", "authorization": "must-not-leak"},
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
	assert_null(panel.get_node_or_null("CostRow"))
	assert_eq(_row_value(panel, "CreatedAt"), "2026-07-13T08:00:00Z")
	assert_eq(_row_value(panel, "Source"), "generate-cloud")
	assert_false(_all_label_text(panel).contains("must-not-leak"))
	assert_false(inspector.get_node("ContextRoot/CleanupInspector").visible)

	watch_signals(inspector)
	(panel.get_node("CandidateActions/CopySettingsButton") as Button).pressed.emit()
	var expected_snapshot: Dictionary = fixture["snapshot"]
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


func test_output_selection_is_single_and_inspector_uses_the_selected_slot() -> void:
	var first_id := _register_candidate("first", {"prompt": "first", "model_id": "model-a"})
	var second_id := _register_candidate("second", {"prompt": "second", "model_id": "model-b"})
	var fixture := await _make_inspector_with_batch([first_id, second_id], [first_id, second_id])
	var panel: Control = fixture["inspector"].get_node("ContextRoot/CandidatePanel")
	var actions: Control = panel.get_node("CandidateActions")

	assert_eq((panel.get_node("CandidateSummary") as Label).text, "Generation details")
	assert_eq(_row_value(panel, "Model"), "model-a")
	assert_true((actions.get_node("CopyPromptButton") as Button).visible)
	assert_true((actions.get_node("CopySettingsButton") as Button).visible)
	assert_true((actions.get_node("RerunButton") as Button).visible)
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
	var graph := GraphScript.new()
	graph.id = "graph-main"
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			"batch-results",
			_output_params(asset_ids),
			Vector2.ZERO,
		)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "batch-results", Vector2(24, 24), "batch-item", false
	)
	assert_eq(card.asset_ids, asset_ids)
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


func _output_params(asset_ids: Array) -> Dictionary:
	var slots := []
	for index in range(asset_ids.size()):
		slots.append(_slot("slot-%d" % index, String(asset_ids[index]), false))
	if not asset_ids.is_empty():
		slots.append(_slot("slot-detached", String(asset_ids[0]), true))
	return {
		"label": "Candidates",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": slots,
	}


func _slot(slot_id: String, asset_id: String, detached: bool) -> Dictionary:
	return {
		"slot_id": slot_id,
		"run_id": "",
		"request_id": "",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "",
		"planned_size": [4, 4],
		"status": "succeeded",
		"asset_id": asset_id,
		"detached": detached,
		"unexpected": false,
		"error": null,
	}


func _register_candidate(
	name: String, snapshot: Dictionary, include_snapshot: bool = true
) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.DARK_ORANGE)
	var provenance := {"created_at": "legacy-time"}
	if include_snapshot:
		var complete_snapshot := _generation_snapshot_fixture()
		complete_snapshot.merge(snapshot, true)
		provenance["created_at"] = "2026-07-13T08:00:00Z"
		provenance["generation_snapshot"] = complete_snapshot
	var asset_id := AssetLibrary.register_image(
		image, name, {"origin": "generated", "provenance": provenance}
	)
	assert_false(asset_id.is_empty())
	return asset_id


func _generation_snapshot_fixture() -> Dictionary:
	return {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"mode": "txt2img",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [1024, 1024],
		"actual_width": 4,
		"actual_height": 4,
		"requested_seed": -1,
		"actual_seed": null,
		"run_id": "run-fixture",
		"request_id": "request-fixture",
		"source_node_id": "generate-fixture",
		"source_row_id": "",
		"prompt_preset_id": "",
		"prompt_prefix": "",
		"prompt": "fixture prompt",
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"extra": {"quality": "low"},
	}


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
