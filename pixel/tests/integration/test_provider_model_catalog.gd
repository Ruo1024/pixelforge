extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")
const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const RetroProviderScript := preload(
	"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd"
)

var _service: PFProviderService


func before_each() -> void:
	_service = ProviderServiceScript.new()
	_service.load_builtin_plugins = false
	add_child_autofree(_service)
	await wait_process_frames(1)
	assert_true(_service.register_provider(OpenAIProviderScript.new())["ok"])
	assert_true(_service.register_provider(RetroProviderScript.new())["ok"])


func test_service_aggregates_catalog_and_resolves_provider_defaults() -> void:
	var catalog := _service.get_model_descriptors()
	assert_eq(catalog.size(), 4)
	assert_eq(_service.get_selectable_model_descriptors().size(), 1)
	assert_eq(_service.get_selectable_model_descriptors()[0]["model_id"], "pixel_mock_v1")
	_service._set_validation_state("openai_image", "verified", "")
	assert_eq(_service.get_selectable_model_descriptors().size(), 2)
	assert_eq(_service.get_model_descriptors("openai_image").size(), 1)
	assert_eq(_service.resolve_model_id("mock"), "pixel_mock_v1")
	assert_eq(_service.get_model_descriptor("mock")["provider_id"], "mock")
	assert_eq(_service.resolve_model_id("openai_image"), "gpt-image-2")
	assert_eq(_service.resolve_model_id("retrodiffusion"), "rd_plus")
	assert_eq(_service.resolve_model_id("retrodiffusion", "rd_pro"), "rd_pro")
	assert_eq(_service.resolve_model_id("retrodiffusion", "missing"), "")
	assert_eq(_service.get_model_descriptor("retrodiffusion", "rd_fast")["display_name"], "RD Fast")


func test_openai_descriptor_and_validation_reject_unsupported_requests() -> void:
	var descriptor := _service.get_model_descriptor("openai_image")
	var capabilities: Dictionary = descriptor["capabilities"]
	assert_eq(descriptor["model_id"], "gpt-image-2")
	assert_true(descriptor["is_default"])
	assert_eq(capabilities["max_reference_images"], 4)
	assert_eq(capabilities["max_batch"], 4)
	assert_false(capabilities["seed"])
	assert_false(capabilities["transparent_bg"])
	assert_eq(capabilities["provider_output_sizes"].size(), 3)

	assert_null(_service.validate_generation_request("openai_image", _openai_request()))
	assert_eq(
		(_service.validate_generation_request(
			"openai_image", _openai_request({"model_id": "missing"})
		))["code"],
		"invalid_model"
	)
	assert_eq(
		_service.validate_generation_request("openai_image", _openai_request({"batch": 5}))["code"],
		"invalid_batch"
	)
	assert_eq(
		(
			_service
			. validate_generation_request(
				"openai_image",
				_openai_request({"mode": "img2img", "ref_images": _reference_images(5)})
			)["code"]
		),
		"invalid_reference_count"
	)
	assert_eq(
		(
			_service
			. validate_generation_request(
				"openai_image", _openai_request({"provider_output_size": [512, 512]})
			)["code"]
		),
		"invalid_provider_output_size"
	)


func test_retro_models_map_stably_and_enforce_model_dimensions_and_references() -> void:
	var provider: PFRetroDiffusionProvider = _service.get_provider("retrodiffusion")
	assert_eq(provider.get_model_descriptors().size(), 3)
	assert_eq(provider.build_request_body(_retro_request())["prompt_style"], "rd_plus__low_res")
	assert_eq(
		provider.build_request_body(_retro_request({"model_id": "rd_pro"}))["prompt_style"],
		"rd_pro__default"
	)
	assert_eq(
		provider.build_request_body(_retro_request({"model_id": "rd_fast"}))["prompt_style"],
		"rd_fast__default"
	)
	assert_null(
		_service.validate_generation_request(
			"retrodiffusion", _retro_request({"model_id": "rd_pro"})
		)
	)
	assert_eq(
		(
			_service
			. validate_generation_request(
				"retrodiffusion",
				_retro_request(
					{
						"model_id": "rd_plus",
						"target_width": 129,
						"provider_output_size": [129, 64],
					}
				)
			)["code"]
		),
		"invalid_target_size"
	)
	assert_eq(
		(
			_service
			. validate_generation_request(
				"retrodiffusion",
				_retro_request({"mode": "img2img", "ref_images": _reference_images(2)})
			)["code"]
		),
		"invalid_reference_count"
	)


func test_invalid_request_is_preflight_validation_issue_without_provider_task() -> void:
	var issue: Dictionary = _service.validate_generation_request(
		"openai_image", _openai_request({"batch": 5})
	)
	assert_eq(issue, {"code": "invalid_batch", "field": "batch", "args": {}})
	assert_true(TaskQueue.is_idle())


func _openai_request(overrides: Dictionary = {}) -> Dictionary:
	var request := {
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
	request.merge(overrides, true)
	return request


func _retro_request(overrides: Dictionary = {}) -> Dictionary:
	var request := {
		"run_id": "run-retro",
		"request_id": "request-retro",
		"idempotency_key": "idem-retro",
		"provider_id": "retrodiffusion",
		"mode": "txt2img",
		"model_id": "rd_plus",
		"prompt": "barrel",
		"target_width": 64,
		"target_height": 64,
		"provider_output_size": [64, 64],
		"batch": 1,
		"seed": 7,
		"ref_images": [],
		"extra": {"remove_bg": true, "strength": 0.8},
	}
	request.merge(overrides, true)
	return request


func _reference_images(count: int) -> Array:
	var images := []
	for _index in range(count):
		images.append(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	return images


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
