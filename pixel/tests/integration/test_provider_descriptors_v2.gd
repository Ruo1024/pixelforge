extends "res://addons/gut/test.gd"

const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const RetroProviderScript := preload(
	"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd"
)
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const ProviderServiceScript := preload("res://services/provider_service.gd")


func test_openai_exact_descriptor_and_schema() -> void:
	var provider: PFProvider = OpenAIProviderScript.new()
	assert_eq(provider.get_api_version(), 2)
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
	var provider: PFOpenAIImageProvider = OpenAIProviderScript.new()
	var host := Node.new()
	add_child_autofree(host)
	provider.attach_request_host(host)
	assert_null(
		(
			provider
			. configure(
				{
					"api_key": "fixture-key",
					"generation_url":
					OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-success",
				}
			)
		)
	)
	var task := provider.generate(_openai_request())
	var outcome := {"status": "pending", "value": null, "progress": 0}
	task.progress.connect(func(_value: Dictionary) -> void: outcome["progress"] += 1)
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
	assert_eq(outcome["progress"], 0)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["progress"], 1)
	assert_null(ContractV2.validate_gen_result(outcome["value"], [], ["remote_task_id"]))
	assert_eq(outcome["value"]["items"][0]["error"]["code"], "ambiguous_result")
	assert_false(outcome["value"]["items"][0]["error"].has("message"))
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
	var outcome := {"status": "pending", "value": null, "progress": 0}
	task.progress.connect(func(_value: Dictionary) -> void: outcome["progress"] += 1)
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
	assert_eq(outcome["progress"], 0)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["progress"], 1)
	assert_null(ContractV2.validate_gen_result(outcome["value"], [], ["remote_task_id"]))
	assert_null(outcome["value"]["items"][0]["error"])
	assert_eq(outcome["value"]["items"][0]["image"].get_size(), Vector2i(32, 32))
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


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
