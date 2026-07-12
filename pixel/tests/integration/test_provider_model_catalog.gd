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
	assert_true(_service.register_provider(OpenAIProviderScript.new()))
	assert_true(_service.register_provider(RetroProviderScript.new()))


func test_service_aggregates_catalog_and_resolves_provider_defaults() -> void:
	var catalog := _service.get_model_descriptors()
	assert_eq(catalog.size(), 4)
	assert_eq(_service.get_model_descriptors("openai_image").size(), 1)
	assert_eq(_service.resolve_model_id("openai_image"), "gpt-image-2")
	assert_eq(_service.resolve_model_id("retrodiffusion"), "rd_plus")
	assert_eq(_service.resolve_model_id("retrodiffusion", "rd_pro"), "rd_pro")
	assert_eq(_service.resolve_model_id("retrodiffusion", "missing"), "")
	assert_eq(_service.get_model_descriptor("retrodiffusion", "rd_fast")["display_name"], "RD Fast")


func test_openai_descriptor_and_validation_reject_unsupported_requests() -> void:
	var provider: PFProvider = _service.get_provider("openai_image")
	var descriptor := provider.get_model_descriptor()
	var capabilities: Dictionary = descriptor["capabilities"]
	assert_eq(descriptor["model_id"], "gpt-image-2")
	assert_true(descriptor["is_default"])
	assert_eq(capabilities["max_reference_images"], 4)
	assert_eq(capabilities["max_batch"], 4)
	assert_false(capabilities["seed"])
	assert_false(capabilities["transparent_bg"])
	assert_eq(capabilities["output_sizes"].size(), 3)

	assert_null(provider.validate_generation_request(_openai_request()))
	assert_eq(
		provider.validate_generation_request(_openai_request({"model_id": "missing"}))["code"],
		"invalid_request"
	)
	assert_eq(
		provider.validate_generation_request(_openai_request({"batch": 5}))["code"],
		"invalid_request"
	)
	assert_eq(
		(
			provider
			. validate_generation_request(_openai_request({"ref_images": _reference_images(5)}))["code"]
		),
		"invalid_request"
	)
	assert_eq(
		provider.validate_generation_request(_openai_request({"output_size": "512x512"}))["code"],
		"invalid_request"
	)
	assert_eq(
		provider.validate_generation_request(_openai_request({"transparent_bg": true}))["code"],
		"invalid_request"
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
	assert_null(provider.validate_generation_request(_retro_request({"model_id": "rd_pro"})))
	assert_eq(
		(
			provider
			. validate_generation_request(_retro_request({"model_id": "rd_plus", "width": 129}))["code"]
		),
		"invalid_request"
	)
	assert_eq(
		(
			provider
			. validate_generation_request(_retro_request({"ref_images": _reference_images(2)}))["code"]
		),
		"invalid_request"
	)


func test_invalid_generate_returns_rejected_task_without_creating_http_request() -> void:
	var provider: PFOpenAIImageProvider = _service.get_provider("openai_image")
	var host := Node.new()
	add_child_autofree(host)
	provider.attach_request_host(host)
	assert_null(provider.configure({"api_key": "fixture-only"}))
	var task: PFTask = provider.generate(_openai_request({"batch": 5}))
	assert_eq(task.kind, "openai_image_generate")
	assert_eq(task.payload, {"provider_id": "openai_image"})
	var observed_error := {}
	task.failed.connect(func(error: Dictionary) -> void: observed_error.merge(error, true))
	TaskQueue.submit(task)
	assert_true(await _wait_until(func() -> bool: return observed_error.has("code")))
	assert_true(await _wait_until(func() -> bool: return TaskQueue.is_idle()))
	assert_eq(observed_error["code"], "invalid_request")


func _openai_request(overrides: Dictionary = {}) -> Dictionary:
	var request := {
		"mode": "txt2img",
		"model_id": "",
		"prompt": "barrel",
		"width": 32,
		"height": 32,
		"batch": 1,
		"ref_images": [],
	}
	request.merge(overrides, true)
	return request


func _retro_request(overrides: Dictionary = {}) -> Dictionary:
	var request := {
		"mode": "txt2img",
		"model_id": "",
		"prompt": "barrel",
		"width": 64,
		"height": 64,
		"batch": 1,
		"ref_images": [],
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
