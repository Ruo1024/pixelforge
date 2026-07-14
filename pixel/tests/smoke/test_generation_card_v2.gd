extends "res://addons/gut/test.gd"

const GenerationCardViewScript := preload("res://ui/canvas/generation_card_view.gd")
const GenerationCardPolicyScript := preload("res://ui/canvas/generation_card_policy.gd")
const GenerationRequestPlannerScript := preload("res://services/generation_request_planner.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_exact_six_groups_and_fixed_regions() -> void:
	var view := await _view(_snapshot())
	assert_eq(
		view.get_group_ids(),
		["run_status", "provider", "input_summary", "core_params", "dynamic_params", "footer"]
	)
	assert_eq(view.get_node("RunStatusGroup").get_parent(), view)
	assert_eq(view.get_node("Footer").get_parent(), view)
	var body: ScrollContainer = view.get_node("BodyScroll")
	for group_name in [
		"ProviderGroup", "InputSummaryGroup", "CoreParamsGroup", "DynamicParamsGroup"
	]:
		assert_true(body.is_ancestor_of(view.get_node("BodyScroll/BodyGroups/%s" % group_name)))
	assert_false(body.is_ancestor_of(view.get_node("RunStatusGroup")))
	assert_false(body.is_ancestor_of(view.get_node("Footer")))


func test_prompt_preview_rows_and_suffix() -> void:
	var descriptor := _descriptor(false, true)
	var snapshot := _snapshot(descriptor)
	snapshot["prompt"] = "forest shrine"
	snapshot["prefix"] = "clean pixel art"
	var view := await _view(snapshot)
	var expected_plan := GenerationRequestPlannerScript.plan(
		_planner_input(snapshot, []), [descriptor]
	)
	assert_true(expected_plan["ok"])
	assert_eq(
		view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/PromptPreview").text,
		expected_plan["requests"][0]["prompt"]
	)
	assert_string_contains(
		view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/PromptPreview").text,
		"pixel art designed for a 32x24 true-pixel target, flat colors, crisp edges"
	)
	assert_null(view.find_child("PromptEdit", true, false))


func test_footer_state_actions() -> void:
	var view := await _view(_snapshot())
	var cases := [
		["Ready", "Generate", "generate", false],
		["Queued", "Cancel", "cancel", false],
		["Running", "Cancel", "cancel", false],
		["Canceling", "Canceling…", "", true],
		["Complete", "Generate again", "regenerate", false],
		["Canceled", "Generate again", "regenerate", false],
	]
	for spec in cases:
		view.set_run_context({"state": spec[0], "errors": []})
		var button: Button = view.get_node("Footer/PrimaryAction")
		assert_eq(button.text, spec[1], spec[0])
		assert_eq(button.disabled, spec[3], spec[0])
		assert_eq(String(button.get_meta("action_id", "")), spec[2], spec[0])


func test_rows_hide_batch_and_preview_first_expand() -> void:
	var descriptor := _descriptor(false, true)
	var rows := [
		{"id": "hero", "text": "hero idle", "count": 3, "enabled": true},
		{"id": "enemy", "text": "slime attack", "count": 2, "enabled": true},
	]
	var snapshot := _snapshot(descriptor)
	snapshot["prefix"] = "16-bit"
	snapshot["prompt"] = "forest"
	snapshot["rows"] = rows
	var view := await _view(snapshot)
	assert_null(view.find_child("BatchSize", true, false))
	assert_eq(
		view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/RowsCount").text, "2 rows / 5 images"
	)
	var expected := GenerationRequestPlannerScript.plan(
		_planner_input(snapshot, rows), [descriptor]
	)
	assert_true(expected["ok"])
	assert_eq(
		view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/PromptPreview").text,
		expected["requests"][0]["prompt"]
	)
	var toggle: Button = view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/PromptListToggle")
	toggle.button_pressed = true
	toggle.toggled.emit(true)
	var list: VBoxContainer = view.get_node("BodyScroll/BodyGroups/CoreParamsGroup/PromptList")
	assert_true(list.visible)
	assert_eq(list.get_child_count(), 2)
	assert_string_contains(list.get_child(0).text, "hero idle · 3")
	assert_string_contains(list.get_child(1).text, "slime attack · 2")
	assert_lte(list.get_child(0).text.count("hero idle"), 2)


func test_fixed_bounds_and_scroll_regions() -> void:
	assert_eq(GenerationCardViewScript.DEFAULT_SIZE, Vector2i(400, 520))
	assert_eq(GenerationCardViewScript.MIN_SIZE, Vector2i(360, 400))
	assert_eq(GenerationCardViewScript.MAX_SIZE, Vector2i(1600, 1200))
	assert_eq(GenerationCardViewScript.HEADER_HEIGHT, 40)
	assert_eq(GenerationCardViewScript.FOOTER_HEIGHT, 56)
	var view := await _view(_snapshot())
	assert_eq(view.custom_minimum_size, Vector2(360, 360))
	assert_eq(view.get_node("RunStatusGroup").position.y, 0.0)
	assert_eq(view.get_node("Footer").anchor_top, 1.0)
	assert_eq(view.get_node("Footer").anchor_bottom, 1.0)
	assert_eq(view.get_node("Footer").offset_top, -56.0)
	assert_eq(view.get_node("BodyScroll").offset_bottom, -56.0)


func test_input_summary_jumps_upstream_only() -> void:
	var snapshot := _snapshot()
	snapshot["input_sources"] = [
		{"id": "objects", "kind": "subjects", "summary": "2 rows"},
		{"id": "prompt", "kind": "prompt", "summary": "forest shrine"},
	]
	var view := await _view(snapshot)
	var jumps := []
	view.upstream_requested.connect(func(source_id: String) -> void: jumps.append(source_id))
	view.get_node("BodyScroll/BodyGroups/InputSummaryGroup/InputSource0").pressed.emit()
	assert_eq(jumps, ["objects"])
	assert_null(
		view.get_node("BodyScroll/BodyGroups/InputSummaryGroup").find_child(
			"PromptEdit", true, false
		)
	)
	assert_null(
		view.get_node("BodyScroll/BodyGroups/InputSummaryGroup").find_child(
			"ObjectEdit", true, false
		)
	)


func test_descriptor_params_advanced_and_seed_visibility() -> void:
	var descriptor := _descriptor(true, true)
	var view := await _view(_snapshot(descriptor))
	assert_not_null(view.find_child("DynamicParam_quality", true, false))
	assert_not_null(view.find_child("Seed", true, false))
	assert_null(view.find_child("DynamicParam_unknown", true, false))
	var advanced: VBoxContainer = view.find_child("AdvancedParams", true, false)
	assert_false(advanced.visible)
	assert_not_null(advanced.find_child("DynamicParam_detail", true, false))

	var no_seed_descriptor := _descriptor(false, false)
	no_seed_descriptor["dynamic_params"] = [no_seed_descriptor["dynamic_params"][0]]
	var no_seed := await _view(_snapshot(no_seed_descriptor))
	assert_null(no_seed.find_child("Seed", true, false))
	assert_null(no_seed.find_child("DynamicParam_detail", true, false))


func test_footer_error_priority_and_preflight_routes() -> void:
	var policy := GenerationCardPolicyScript.new()
	var cases := [
		[[{"code": "provider_internal", "retryable": false}], "regenerate", "preflight_new_output"],
		[
			[{"code": "ambiguous_result", "retryable": false}],
			"regenerate_confirm",
			"preflight_new_output"
		],
		[[{"code": "invalid_request", "retryable": false}], "focus_generation", "focus_generation"],
		[[{"code": "content_policy", "retryable": false}], "edit_prompt", "focus_prompt"],
		[
			[{"code": "quota_exceeded", "retryable": false}],
			"provider_settings",
			"provider_settings"
		],
		[[{"code": "cancel_failed", "retryable": false}], "cancel_failed", "none"],
	]
	for spec in cases:
		var result: Dictionary = policy.footer_action({"state": "Failed", "errors": spec[0]})
		assert_eq(result["action_id"], spec[1])
		assert_eq(result["route"], spec[2])
	var retry := policy.footer_action(
		{"state": "Partial", "errors": [{"code": "rate_limited", "retryable": true}]}
	)
	assert_eq(retry["action_id"], "retry_failed")
	assert_eq(retry["route"], "preflight_retry_same_output")
	var wait := (
		policy
		. footer_action(
			{
				"state": "Partial",
				"errors": [{"code": "rate_limited", "retryable": true, "wait_seconds": 7}],
			}
		)
	)
	assert_eq(wait["action_id"], "retry_wait")
	assert_true(wait["disabled"])


func test_generation_progress_cost_error_provider_keys_refresh() -> void:
	var view := await _view(_snapshot())
	(
		view
		. set_run_context(
			{
				"state": "Running",
				"progress":
				{"determinate": false, "completed_items": 2, "total_items": 4, "elapsed_ms": 3200},
				"cost": {"kind": "estimate", "micro_usd": 250000},
				"provider_available": false,
			}
		)
	)
	var instance_id := view.get_instance_id()
	assert_true(view.get_node("RunStatusGroup/RunProgressIndicator").indeterminate)
	var english := _visible_text(view)
	assert_string_contains(english, "Running")
	assert_string_contains(english, "2/4")
	assert_string_contains(english, "$0.25")
	assert_string_contains(english, "Provider settings")
	LocalizationService.set_language("zh_CN")
	await wait_process_frames(1)
	assert_eq(view.get_instance_id(), instance_id)
	var chinese := _visible_text(view)
	assert_string_contains(chinese, "运行中")
	assert_string_contains(chinese, "2/4")
	assert_string_contains(chinese, "$0.25")
	assert_string_contains(chinese, "提供方设置")
	LocalizationService.set_language("en")
	await wait_process_frames(1)
	assert_eq(_visible_text(view), english)


func _view(snapshot: Dictionary) -> Control:
	var view: Control = GenerationCardViewScript.new()
	view.size = Vector2(400, 480)
	add_child_autofree(view)
	view.configure(snapshot)
	await wait_process_frames(1)
	return view


func _snapshot(descriptor: Dictionary = {}) -> Dictionary:
	var resolved := descriptor if not descriptor.is_empty() else _descriptor(true, true)
	return {
		"params":
		{
			"provider_id": resolved["provider_id"],
			"model_id": resolved["model_id"],
			"target_width": 32,
			"target_height": 24,
			"batch_size": 4,
			"seed": 7,
			"extra": {"quality": "low", "detail": 2},
		},
		"descriptor": resolved,
		"prefix": "",
		"prompt": "forest shrine",
		"rows": [],
		"reference_count": 0,
		"input_sources": [],
		"run": {"state": "Ready", "errors": []},
	}


func _descriptor(native_pixel: bool, seed: bool) -> Dictionary:
	return {
		"provider_id": "test_provider",
		"model_id": "test_model",
		"display_name": "Test Model",
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"max_reference_images": 4,
			"max_batch": 4,
			"target_size_constraints":
			{
				"min_width": 1,
				"max_width": 4096,
				"width_step": 1,
				"min_height": 1,
				"max_height": 4096,
				"height_step": 1,
				"allowed_sizes": [],
			},
			"native_pixel": native_pixel,
			"seed": seed,
			"provider_output_sizes": [[1024, 1024]],
		},
		"dynamic_params":
		[
			{
				"key": "quality",
				"kind": "enum",
				"default": "low",
				"values": ["low", "high"],
				"label_key": "GEN_PARAM_QUALITY",
				"help_key": "GEN_PARAM_QUALITY_HELP",
				"advanced": false,
			},
			{
				"key": "detail",
				"kind": "int",
				"default": 2,
				"min": 1,
				"max": 4,
				"step": 1,
				"label_key": "GEN_PARAM_QUALITY",
				"help_key": "GEN_PARAM_QUALITY_HELP",
				"advanced": true,
			},
		],
	}


func _planner_input(snapshot: Dictionary, rows: Array) -> Dictionary:
	var params: Dictionary = snapshot["params"]
	return {
		"run_id": "preview",
		"provider_id": params["provider_id"],
		"model_id": params["model_id"],
		"target_width": params["target_width"],
		"target_height": params["target_height"],
		"batch_size": params["batch_size"],
		"seed": params["seed"],
		"extra": params["extra"],
		"prefix": snapshot["prefix"],
		"prompt": snapshot["prompt"],
		"rows": rows,
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
	}


func _visible_text(root: Node) -> String:
	var values := []
	for child in root.find_children("*", "Label", true, false):
		if child.visible:
			values.append(child.text)
	for child in root.find_children("*", "Button", true, false):
		if child.visible:
			values.append(child.text)
	return "\n".join(values)
