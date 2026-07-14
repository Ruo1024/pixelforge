extends "res://addons/gut/test.gd"

const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const RetroProviderScript := preload(
	"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd"
)
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const ProviderServiceScript := preload("res://services/provider_service.gd")
const PlannerScript := preload("res://services/generation_request_planner.gd")
const RetryPreflightScript := preload("res://services/generation_retry_preflight.gd")
const ResultMapperScript := preload("res://services/provider_result_mapper.gd")


func test_openai_exact_descriptor_and_schema() -> void:
	var provider: PFProvider = OpenAIProviderScript.new()
	assert_eq(provider.get_api_version(), 2)
	assert_eq(provider.get_model_descriptors(), [_openai_descriptor()])
	assert_eq(
		provider.get_config_schema(),
		[
			{
				"key": "api_key",
				"kind": "password",
				"label_key": "OPENAI_FIELD_API_KEY",
				"help_key": "OPENAI_FIELD_API_KEY_HELP",
				"required": true,
				"default": "",
			}
		]
	)
	var descriptors := provider.get_model_descriptors()
	assert_eq(descriptors.size(), 1)
	var descriptor: Dictionary = descriptors[0]
	assert_eq(descriptor.keys().size(), 8)
	assert_eq(descriptor["provider_id"], "openai_image")
	assert_eq(descriptor["model_id"], "gpt-image-2")
	assert_eq(descriptor["ui_scope"], "main")
	assert_eq(descriptor["provider_meta_keys"], ["remote_task_id"])
	assert_eq(descriptor["dynamic_params"].size(), 1)
	assert_eq(
		descriptor["capabilities"]["provider_output_sizes"],
		[[1024, 1024], [1536, 1024], [1024, 1536]]
	)
	assert_false(descriptor["capabilities"]["native_pixel"])


func test_retro_exact_descriptors_and_schema() -> void:
	var provider: PFProvider = RetroProviderScript.new()
	assert_eq(provider.get_api_version(), 2)
	assert_eq(
		provider.get_model_descriptors(),
		[
			_retro_descriptor("rd_plus", "Retro Diffusion Plus", true, 128, false),
			_retro_descriptor("rd_pro", "Retro Diffusion Pro", false, 256, true),
			_retro_descriptor("rd_fast", "Retro Diffusion Fast", false, 384, false),
		]
	)
	assert_eq(provider.get_config_schema().size(), 2)
	assert_eq(provider.get_config_schema()[0]["kind"], "password")
	assert_eq(provider.get_config_schema()[1]["kind"], "string")
	assert_eq(provider.get_config_schema()[1]["label_key"], "RETRO_FIELD_ENDPOINT")
	var descriptors := provider.get_model_descriptors()
	assert_eq(descriptors.size(), 3)
	assert_eq(
		descriptors.map(func(value: Dictionary) -> String: return value["model_id"]),
		["rd_plus", "rd_pro", "rd_fast"]
	)
	assert_eq(
		descriptors.map(func(value: Dictionary) -> String: return value["display_name"]),
		["Retro Diffusion Plus", "Retro Diffusion Pro", "Retro Diffusion Fast"]
	)
	assert_eq(
		descriptors.filter(func(value: Dictionary) -> bool: return value["is_default"]).size(), 1
	)
	for descriptor in descriptors:
		assert_eq(descriptor.keys().size(), 8)
		assert_eq(descriptor["ui_scope"], "main")
		assert_eq(descriptor["provider_meta_keys"], ["remote_task_id"])
		assert_true(descriptor["capabilities"]["native_pixel"])
		assert_eq(descriptor["capabilities"]["provider_output_sizes"], [])
		assert_eq(descriptor["dynamic_params"].size(), 2)
	assert_true(descriptors[1]["capabilities"]["cost_estimate"])
	assert_false(descriptors[0]["capabilities"]["cost_estimate"])
	assert_false(descriptors[2]["capabilities"]["cost_estimate"])


func test_service_rejects_nonexact_descriptor_and_config_schema_types() -> void:
	var service := ProviderServiceScript.new()
	service.load_builtin_plugins = false
	add_child_autofree(service)
	var openai: PFProvider = OpenAIProviderScript.new()
	assert_true(service._config_schema_is_valid(openai.get_config_schema()))
	var raw_label := openai.get_config_schema().duplicate(true)
	raw_label[0]["label"] = "API key"
	assert_false(service._config_schema_is_valid(raw_label))
	var secret_default := openai.get_config_schema().duplicate(true)
	secret_default[0]["default"] = "secret"
	assert_false(service._config_schema_is_valid(secret_default))
	var descriptors := openai.get_model_descriptors()
	assert_true(service._model_descriptors_are_valid("openai_image", descriptors))
	var wrong_flag := descriptors.duplicate(true)
	wrong_flag[0]["capabilities"]["safe_validation"] = "true"
	assert_false(service._model_descriptors_are_valid("openai_image", wrong_flag))
	var wrong_dynamic_default := descriptors.duplicate(true)
	wrong_dynamic_default[0]["dynamic_params"][0]["default"] = 1
	assert_false(service._model_descriptors_are_valid("openai_image", wrong_dynamic_default))
	var service_source := FileAccess.get_file_as_string("res://services/provider_service.gd")
	assert_string_contains(service_source, "res://services/schema_text_resolver.gd")
	assert_string_contains(service_source, "validate_schema")


func test_openai_mock_generation_returns_deferred_v2_terminal() -> void:
	var provider: PFOpenAIImageProvider = OpenAIProviderScript.new(
		OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-success"
	)
	var host := Node.new()
	add_child_autofree(host)
	provider.attach_request_host(host)
	assert_null(provider.configure({"api_key": "fixture-key"}))
	var task := provider.generate(_openai_request())
	var outcome := {"status": "pending", "value": null, "phases": []}
	task.progress.connect(func(value: Dictionary) -> void: outcome["phases"].append(value["phase"]))
	task.completed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = value
	)
	task.failed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = value
	)
	assert_eq(outcome["status"], "pending")
	assert_eq(outcome["phases"], [])
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["phases"], ["submitting", "provider_processing", "downloading", "decoding"])
	assert_null(ContractV2.validate_gen_result(outcome["value"], [], ["remote_task_id"]))
	assert_null(outcome["value"]["items"][0]["error"])
	assert_true(outcome["value"]["items"][0]["image"] is Image)
	provider.clear_session_config()


func test_retro_mock_generation_returns_deferred_v2_terminal() -> void:
	var provider: PFRetroDiffusionProvider = RetroProviderScript.new()
	var host := Node.new()
	add_child_autofree(host)
	provider.attach_request_host(host)
	assert_null(
		(
			provider
			. configure(
				{
					"api_key": "fixture-key",
					"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/retrodiffusion-success",
				}
			)
		)
	)
	var task := provider.generate(_retro_request())
	var outcome := {"status": "pending", "value": null, "phases": []}
	task.progress.connect(func(value: Dictionary) -> void: outcome["phases"].append(value["phase"]))
	task.completed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = value
	)
	task.failed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = value
	)
	assert_eq(outcome["status"], "pending")
	assert_eq(outcome["phases"], [])
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["phases"], ["submitting", "provider_processing", "downloading", "decoding"])
	assert_null(ContractV2.validate_gen_result(outcome["value"], [], ["remote_task_id"]))
	assert_null(outcome["value"]["items"][0]["error"])
	assert_eq(outcome["value"]["items"][0]["image"].get_size(), Vector2i(32, 32))
	provider.clear_session_config()


func test_malformed_generation_2xx_is_ambiguous_not_retryable() -> void:
	var provider: PFOpenAIImageProvider = OpenAIProviderScript.new(
		OS.get_environment("PF_HTTP_MOCK_URL") + "/malformed"
	)
	var host := Node.new()
	add_child_autofree(host)
	provider.attach_request_host(host)
	assert_null(provider.configure({"api_key": "fixture-key"}))
	var task := provider.generate(_openai_request())
	var outcome := {"status": "pending", "value": null}
	task.completed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = value
	)
	task.failed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = value
	)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "failed")
	assert_eq(outcome["value"]["code"], "ambiguous_result")
	assert_false(outcome["value"]["retryable"])
	provider.clear_session_config()


func test_zero_item_provider_payloads_remain_normalized_results() -> void:
	var openai: PFOpenAIImageProvider = OpenAIProviderScript.new()
	var openai_result := openai.decode_success_payload({"data": []}, _openai_request())
	assert_eq(openai_result["items"], [])
	assert_null(ContractV2.validate_gen_result(openai_result, [], ["remote_task_id"]))
	var retro: PFRetroDiffusionProvider = RetroProviderScript.new()
	var retro_result := retro.decode_success_payload(
		{"base64_images": [], "balance_cost": "0.000000"}, _retro_request()
	)
	assert_eq(retro_result["items"], [])
	assert_eq(retro_result["actual_cost_usd"], "0.000000")
	assert_null(ContractV2.validate_gen_result(retro_result, [], ["remote_task_id"]))


func test_mock_partial_then_manual_retry_targets_only_missing_slot() -> void:
	for provider_id in ["openai_image", "retrodiffusion"]:
		CostService.set_monthly_budget_micro_usd(0)
		var host := Node.new()
		add_child_autofree(host)
		var provider: PFProvider
		var endpoint_path := (
			"/openai-image-partial" if provider_id == "openai_image" else "/retrodiffusion-partial"
		)
		var requests_before := await _mock_post_count(endpoint_path)
		if provider_id == "openai_image":
			provider = OpenAIProviderScript.new(
				OS.get_environment("PF_HTTP_MOCK_URL") + endpoint_path
			)
			assert_null(provider.configure({"api_key": "fixture-key"}))
		else:
			provider = RetroProviderScript.new()
			assert_null(
				(
					provider
					. configure(
						{
							"api_key": "fixture-key",
							"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + endpoint_path,
						}
					)
				)
			)
		provider.attach_request_host(host)
		var planner_input := _planner_input(provider_id, 2)
		if provider_id == "retrodiffusion":
			planner_input["model_id"] = "rd_pro"
		var planned: Dictionary = PlannerScript.plan(
			planner_input, provider.get_model_descriptors()
		)
		assert_true(planned["ok"])
		var request: Dictionary = planned["requests"][0]
		var first: Dictionary = await _provider_outcome(provider.generate(request))
		assert_eq(first["status"], "completed")
		assert_eq(await _mock_post_count(endpoint_path), requests_before + 1)
		var mapped: Dictionary = ResultMapperScript.map_result(
			request, planned["slots"], first["value"]
		)
		assert_eq(mapped["state"], "partial")
		var failed_slots: Array = mapped["slot_updates"].filter(
			func(slot: Dictionary) -> bool: return slot["status"] == "failed"
		)
		var retry_groups: Array = PlannerScript.group_retry_slots(failed_slots, 4)
		assert_eq(retry_groups.size(), 1)
		assert_eq(retry_groups[0]["slot_ids"], [planned["slots"][1]["slot_id"]])
		assert_eq(retry_groups[0]["batch"], 1)
		var retry_plan: Dictionary = RetryPreflightScript.prepare_failed_slots(
			failed_slots, 4, "%s-retry" % request["run_id"]
		)
		assert_true(retry_plan["ok"])
		assert_eq(retry_plan["preflight"]["decision"], "allowed")
		assert_eq(retry_plan["slots"][0]["slot_id"], planned["slots"][1]["slot_id"])
		var invalid_retry: Dictionary = RetryPreflightScript.prepare_failed_slots(
			[mapped["slot_updates"][0]], 4, "%s-invalid" % request["run_id"]
		)
		assert_false(invalid_retry["ok"])
		assert_eq(invalid_retry["requests"], [])
		assert_eq(await _mock_post_count(endpoint_path), requests_before + 1)
		if provider_id == "retrodiffusion":
			CostService.set_monthly_budget_micro_usd(1)
			var confirmation: Dictionary = RetryPreflightScript.prepare_failed_slots(
				failed_slots, 4, "%s-confirm" % request["run_id"]
			)
			assert_eq(confirmation["preflight"]["decision"], "needs_confirmation")
			var canceled: Dictionary = RetryPreflightScript.authorize(confirmation, false)
			assert_false(canceled["ok"])
			assert_eq(canceled["requests"], [])
			assert_eq(await _mock_post_count(endpoint_path), requests_before + 1)
			CostService.set_monthly_budget_micro_usd(0)
			retry_plan = RetryPreflightScript.prepare_failed_slots(
				failed_slots, 4, "%s-retry" % request["run_id"]
			)
		var authorized: Dictionary = RetryPreflightScript.authorize(retry_plan)
		assert_true(authorized["ok"])
		var retry_request: Dictionary = authorized["requests"][0]
		assert_ne(retry_request["request_id"], request["request_id"])
		assert_eq(retry_request["batch"], 1)
		var retried: Dictionary = await _provider_outcome(provider.generate(retry_request))
		assert_eq(retried["status"], "completed")
		assert_eq(retried["value"]["items"].size(), 1)
		assert_null(retried["value"]["items"][0]["error"])
		assert_eq(await _mock_post_count(endpoint_path), requests_before + 2)
		provider.clear_session_config()
		CostService.set_monthly_budget_micro_usd(0)


func test_mock_generation_timeout_is_terminal_and_never_auto_retries() -> void:
	for provider_id in ["openai_image", "retrodiffusion"]:
		var host := Node.new()
		add_child_autofree(host)
		var provider: PFProvider
		if provider_id == "openai_image":
			provider = OpenAIProviderScript.new(
				OS.get_environment("PF_HTTP_MOCK_URL") + "/post-timeout", "", "", 0.05
			)
			assert_null(provider.configure({"api_key": "fixture-key"}))
		else:
			provider = RetroProviderScript.new(0.05)
			assert_null(
				(
					provider
					. configure(
						{
							"api_key": "fixture-key",
							"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/post-timeout",
						}
					)
				)
			)
		provider.attach_request_host(host)
		var planned: Dictionary = PlannerScript.plan(
			_planner_input(provider_id, 1), provider.get_model_descriptors()
		)
		assert_true(planned["ok"])
		var outcome: Dictionary = await _provider_outcome(provider.generate(planned["requests"][0]))
		assert_eq(outcome["status"], "failed")
		assert_eq(outcome["value"]["code"], "timeout")
		assert_false(outcome["value"]["retryable"])
		assert_eq(outcome["value"]["attempts"], 1)
		provider.clear_session_config()


func test_both_mock_providers_return_structured_http_failure() -> void:
	for provider_id in ["openai_image", "retrodiffusion"]:
		var host := Node.new()
		add_child_autofree(host)
		var provider: PFProvider
		if provider_id == "openai_image":
			provider = OpenAIProviderScript.new(OS.get_environment("PF_HTTP_MOCK_URL") + "/auth")
			assert_null(provider.configure({"api_key": "fixture-key"}))
		else:
			provider = RetroProviderScript.new()
			assert_null(
				(
					provider
					. configure(
						{
							"api_key": "fixture-key",
							"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/auth",
						}
					)
				)
			)
		provider.attach_request_host(host)
		var planned: Dictionary = PlannerScript.plan(
			_planner_input(provider_id, 1), provider.get_model_descriptors()
		)
		var outcome: Dictionary = await _provider_outcome(provider.generate(planned["requests"][0]))
		assert_eq(outcome["status"], "failed")
		assert_eq(outcome["value"]["code"], "auth_failed")
		assert_eq(outcome["value"]["stage"], "http")
		assert_false(outcome["value"]["retryable"])
		provider.clear_session_config()


func test_both_mock_providers_cancel_generation_before_wrapper_settles() -> void:
	for provider_id in ["openai_image", "retrodiffusion"]:
		var host := Node.new()
		add_child_autofree(host)
		var provider: PFProvider
		if provider_id == "openai_image":
			provider = OpenAIProviderScript.new(
				OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-slow"
			)
			assert_null(provider.configure({"api_key": "fixture-key"}))
		else:
			provider = RetroProviderScript.new()
			assert_null(
				(
					provider
					. configure(
						{
							"api_key": "fixture-key",
							"endpoint":
							OS.get_environment("PF_HTTP_MOCK_URL") + "/retrodiffusion-slow",
						}
					)
				)
			)
		provider.attach_request_host(host)
		var planned: Dictionary = PlannerScript.plan(
			_planner_input(provider_id, 1), provider.get_model_descriptors()
		)
		var request: Dictionary = planned["requests"][0]
		var events := []
		var phases := []
		var cancel_result := {"value": null}
		var task: PFProviderTaskV2 = provider.generate(request)
		task.progress.connect(func(value: Dictionary) -> void: phases.append(value["phase"]))
		task.canceled.connect(func(_request_id: String) -> void: events.append("generation"))
		assert_true(await _wait_until(func() -> bool: return phases.has("provider_processing")))
		var cancel_task: PFCancelTaskV2 = provider.cancel(request["request_id"])
		cancel_task.resolved.connect(
			func(value: Dictionary) -> void:
				cancel_result["value"] = value
				events.append("wrapper")
		)
		assert_true(await _wait_until(func() -> bool: return events.size() == 2))
		assert_eq(events, ["generation", "wrapper"])
		assert_true(cancel_result["value"]["local_stopped"])
		provider.clear_session_config()


func _openai_request() -> Dictionary:
	return {
		"run_id": "run-openai",
		"request_id": "request-openai",
		"idempotency_key": "idem-openai",
		"provider_id": "openai_image",
		"mode": "txt2img",
		"model_id": "gpt-image-2",
		"prompt": "barrel",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [1024, 1024],
		"batch": 1,
		"seed": -1,
		"ref_images": [],
		"extra": {"quality": "low"},
	}


func _retro_request() -> Dictionary:
	return {
		"run_id": "run-retro",
		"request_id": "request-retro",
		"idempotency_key": "idem-retro",
		"provider_id": "retrodiffusion",
		"mode": "txt2img",
		"model_id": "rd_plus",
		"prompt": "barrel",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [32, 32],
		"batch": 1,
		"seed": 7,
		"ref_images": [],
		"extra": {"remove_bg": true, "strength": 0.8},
	}


func _planner_input(provider_id: String, batch: int) -> Dictionary:
	return {
		"run_id": "run-mock-%s" % provider_id,
		"provider_id": provider_id,
		"model_id": "gpt-image-2" if provider_id == "openai_image" else "rd_plus",
		"target_width": 32,
		"target_height": 32,
		"batch_size": batch,
		"seed": -1 if provider_id == "openai_image" else 7,
		"prefix": "",
		"prompt": "barrel",
		"rows": [],
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
		"extra":
		(
			{"quality": "low"}
			if provider_id == "openai_image"
			else {"remove_bg": true, "strength": 0.8}
		),
	}


func _provider_outcome(task: PFProviderTaskV2) -> Dictionary:
	var outcome := {"status": "pending", "value": null}
	task.completed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = value
	)
	task.failed.connect(
		func(value: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = value
	)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	return outcome


func _mock_post_count(path: String) -> int:
	var request := HTTPRequest.new()
	add_child(request)
	var outcome := {"done": false, "count": -1}
	request.request_completed.connect(
		func(
			_result: int, status_code: int, _headers: PackedStringArray, body: PackedByteArray
		) -> void:
			var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
			if status_code == 200 and payload is Dictionary:
				outcome["count"] = int(payload.get("count", -1))
			outcome["done"] = true
	)
	assert_eq(
		request.request(
			OS.get_environment("PF_HTTP_MOCK_URL") + "/request-count?path=" + path.uri_encode()
		),
		OK,
	)
	assert_true(await _wait_until(func() -> bool: return outcome["done"]))
	request.queue_free()
	return int(outcome["count"])


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _openai_descriptor() -> Dictionary:
	return {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"display_name": "GPT Image 2",
		"is_default": true,
		"ui_scope": "main",
		"provider_meta_keys": ["remote_task_id"],
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"max_reference_images": 4,
			"max_batch": 4,
			"target_size_constraints":
			{
				"min_width": 16,
				"max_width": 512,
				"width_step": 1,
				"min_height": 16,
				"max_height": 512,
				"height_step": 1,
				"allowed_sizes": [],
			},
			"provider_output_sizes": [[1024, 1024], [1536, 1024], [1024, 1536]],
			"native_pixel": false,
			"native_idempotency": false,
			"safe_validation": true,
			"seed": false,
			"transparent_bg": false,
			"cost_estimate": false,
		},
		"dynamic_params":
		[
			{
				"key": "quality",
				"kind": "enum",
				"default": "low",
				"required": false,
				"values": ["auto", "low", "medium", "high"],
				"min": null,
				"max": null,
				"step": null,
				"label_key": "GEN_PARAM_QUALITY",
				"help_key": "GEN_PARAM_QUALITY_HELP",
				"advanced": false,
				"template_safe": true,
			}
		],
	}


func _retro_descriptor(
	model_id: String, display_name: String, is_default: bool, max_side: int, cost_estimate: bool
) -> Dictionary:
	return {
		"provider_id": "retrodiffusion",
		"model_id": model_id,
		"display_name": display_name,
		"is_default": is_default,
		"ui_scope": "main",
		"provider_meta_keys": ["remote_task_id"],
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"max_reference_images": 1,
			"max_batch": 4,
			"target_size_constraints":
			{
				"min_width": 16,
				"max_width": max_side,
				"width_step": 1,
				"min_height": 16,
				"max_height": max_side,
				"height_step": 1,
				"allowed_sizes": [],
			},
			"provider_output_sizes": [],
			"native_pixel": true,
			"native_idempotency": false,
			"safe_validation": false,
			"seed": true,
			"transparent_bg": true,
			"cost_estimate": cost_estimate,
		},
		"dynamic_params":
		[
			{
				"key": "remove_bg",
				"kind": "bool",
				"default": true,
				"required": false,
				"values": [],
				"min": null,
				"max": null,
				"step": null,
				"label_key": "GEN_PARAM_REMOVE_BG",
				"help_key": "GEN_PARAM_REMOVE_BG_HELP",
				"advanced": false,
				"template_safe": true,
			},
			{
				"key": "strength",
				"kind": "float",
				"default": 0.8,
				"required": false,
				"values": [],
				"min": 0.0,
				"max": 1.0,
				"step": 0.01,
				"label_key": "GEN_PARAM_STRENGTH",
				"help_key": "GEN_PARAM_STRENGTH_HELP",
				"advanced": false,
				"template_safe": true,
				"visible_when": {"mode": "img2img"},
			},
		],
	}
