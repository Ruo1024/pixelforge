extends "res://addons/gut/test.gd"

const GenerationCardViewScript := preload("res://ui/canvas/generation_card_view.gd")
const GenerationCardPolicyScript := preload("res://ui/canvas/generation_card_policy.gd")
const PromptBuilder := preload("res://services/generation_prompt_builder.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_compact_fixed_surface_has_no_retired_controls_or_internal_scroll() -> void:
	var view := await _view(_snapshot())
	assert_eq(
		view.get_group_ids(),
		["run_status", "model", "resolution", "orientation", "count", "developer_prompt", "footer"]
	)
	assert_null(view.find_child("BodyScroll", true, false))
	assert_not_null(view.find_child("ResolutionPreset", true, false))
	assert_not_null(view.find_child("Orientation", true, false))
	assert_not_null(view.find_child("BatchSize", true, false))
	for retired in [
		"TargetWidth", "TargetHeight", "RatioLock", "Quality", "AdvancedParams", "Seed", "Cost"
	]:
		assert_null(view.find_child(retired, true, false), retired)
	var count: SpinBox = view.find_child("BatchSize", true, false)
	assert_eq(count.min_value, 1.0)
	assert_eq(count.max_value, 16.0)
	assert_eq(count.value, 4.0)
	assert_eq(GenerationCardViewScript.DEFAULT_SIZE, Vector2i(420, 520))
	assert_eq(GenerationCardViewScript.MIN_SIZE, Vector2i(380, 460))
	var orientation_group: HBoxContainer = view.find_child("OrientationGroup", true, false)
	assert_eq(orientation_group.get_child(0).text, "Aspect ratio")
	var ratio_options: OptionButton = view.find_child("Orientation", true, false)
	assert_eq(ratio_options.get_item_text(0), "16:9 · Landscape")
	assert_eq(ratio_options.get_item_text(1), "9:16 · Portrait")
	assert_eq(ratio_options.get_item_text(2), "1:1 · Square")


func test_developer_prompt_preview_defaults_hidden_and_reuses_prompt_builder() -> void:
	var snapshot := _snapshot()
	snapshot["prefix"] = "pixel art"
	snapshot["prompt"] = "forest"
	snapshot["rows"] = [{"id": "barrel", "text": "barrel", "count": 2, "enabled": true}]
	var view := await _view(snapshot)
	assert_null(view.find_child("DeveloperPromptPreview", true, false))
	view.set_developer_mode(true)
	var preview: Label = view.find_child("DeveloperPromptPreview", true, false)
	assert_not_null(preview)
	assert_eq(preview.text, PromptBuilder.build("pixel art", "forest", "barrel"))
	assert_eq(preview.text, "pixel art, forest, barrel")
	assert_eq(preview.text.count("pixel art"), 1)
	view.set_developer_mode(false)
	assert_null(view.find_child("DeveloperPromptPreview", true, false))


func test_delivery_controls_commit_only_the_frozen_graph_shape() -> void:
	var view := await _view(_snapshot())
	var commits := []
	view.params_commit_requested.connect(func(params: Dictionary) -> void: commits.append(params))
	var resolution: OptionButton = view.find_child("ResolutionPreset", true, false)
	resolution.select(3)
	resolution.item_selected.emit(3)
	assert_eq(commits[-1]["resolution_preset"], "4K")
	assert_eq(commits[-1]["seed"], -1)
	assert_eq(commits[-1]["extra"], {})
	var orientation: OptionButton = view.find_child("Orientation", true, false)
	orientation.select(0)
	orientation.item_selected.emit(0)
	assert_eq(commits[-1]["orientation"], "landscape")
	var count: SpinBox = view.find_child("BatchSize", true, false)
	count.value = 16
	assert_eq(commits[-1]["batch_size"], 16)
	for params in commits:
		for retired in ["target_width", "target_height", "ratio_lock", "quality"]:
			assert_false(params.has(retired), retired)


func test_read_only_model_host_status_and_footer_actions() -> void:
	var view := await _view(_snapshot())
	assert_eq(view.find_child("ModelValue", true, false).text, "GPT Image 2")
	assert_eq(view.find_child("ApiHost", true, false).text, "mock.openai.local")
	var cases := [
		["Ready", "generate", false],
		["Queued", "cancel", false],
		["Running", "cancel", false],
		["Canceling", "", true],
		["Complete", "regenerate", false],
		["Canceled", "regenerate", false],
	]
	for spec in cases:
		view.set_run_context({"state": spec[0], "errors": []})
		var button: Button = view.get_node("Footer/PrimaryAction")
		assert_eq(String(button.get_meta("action_id", "")), spec[1], spec[0])
		assert_eq(button.disabled, spec[2], spec[0])
	(
		view
		. set_run_context(
			{
				"state": "Running",
				"errors": [],
				"progress":
				{"determinate": false, "completed_items": 2, "total_items": 4, "elapsed_ms": 3200},
			}
		)
	)
	assert_string_contains(view.find_child("RunProgress", true, false).text, "2")
	assert_string_contains(view.find_child("RunProgress", true, false).text, "4")


func test_footer_error_priority_and_existing_output_actions_remain() -> void:
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


func _view(snapshot: Dictionary) -> Control:
	var view: Control = GenerationCardViewScript.new()
	view.size = Vector2(420, 480)
	add_child_autofree(view)
	view.configure(snapshot)
	await wait_process_frames(1)
	return view


func _snapshot() -> Dictionary:
	return {
		"params":
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"resolution_preset": "1080p",
			"orientation": "square",
			"batch_size": 4,
			"seed": -1,
			"extra": {},
		},
		"descriptor":
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"display_name": "GPT Image 2",
		},
		"api_host": "mock.openai.local",
		"prefix": "",
		"prompt": "forest shrine",
		"rows": [],
		"run": {"state": "Ready", "errors": []},
	}
