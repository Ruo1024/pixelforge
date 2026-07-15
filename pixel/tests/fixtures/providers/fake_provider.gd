extends PFProvider

const LegacyTaskScript := preload("res://services/pf_task.gd")
const ProviderTaskV2Script := preload("res://core/provider/pf_provider_task_v2.gd")
const CancelTaskV2Script := preload("res://services/pf_cancel_task_v2.gd")

const PROVIDER_ID := "fixture_provider"
const MODEL_ID := "fixture-model"

var configured_key := ""
var configured_endpoint := ""
var safe_validation := true
var _generation_tasks := {}
var _cancel_tasks := {}
var _cancel_requested := {}


func get_api_version() -> int:
	return 2


func get_config_schema() -> Array[Dictionary]:
	return [
		{
			"key": "api_key",
			"kind": "password",
			"label_key": "OPENAI_FIELD_API_KEY",
			"help_key": "OPENAI_FIELD_API_KEY_HELP",
			"required": true,
			"default": "",
		},
		{
			"key": "endpoint",
			"kind": "string",
			"label_key": "RETRO_FIELD_ENDPOINT",
			"help_key": "RETRO_FIELD_ENDPOINT_HELP",
			"required": true,
			"default": "https://fixture.invalid",
		},
	]


func get_model_descriptors() -> Array[Dictionary]:
	return [
		{
			"provider_id": PROVIDER_ID,
			"model_id": MODEL_ID,
			"display_name": "Fixture Model",
			"is_default": true,
			"ui_scope": "main",
			"provider_meta_keys": [],
			"capabilities":
			{
				"txt2img": true,
				"img2img": false,
				"max_reference_images": 0,
				"max_batch": 2,
				"target_size_constraints":
				{
					"min_width": 1,
					"max_width": 64,
					"width_step": 1,
					"min_height": 1,
					"max_height": 64,
					"height_step": 1,
					"allowed_sizes": [],
				},
				"provider_output_sizes": [],
				"native_pixel": true,
				"native_idempotency": false,
				"safe_validation": safe_validation,
				"seed": true,
				"transparent_bg": false,
			},
			"dynamic_params": [],
		}
	]


func configure(config: Dictionary) -> Variant:
	configured_key = String(config.get("api_key", ""))
	configured_endpoint = String(config.get("endpoint", ""))
	if configured_key.is_empty():
		return {"code": "auth_failed", "field": "api_key", "args": {}}
	return null


func validate_credentials() -> Variant:
	var task := LegacyTaskScript.new("fixture_validate", {"provider_id": PROVIDER_ID})
	task.configure_external(
		func(task_ref: Variant) -> void:
			if configured_key == "fixture-good-key":
				task_ref.resolve({"ok": true})
			else:
				task_ref.reject({"code": "auth_failed", "message": "Fixture key rejected"})
	)
	return task


func generate(request: Dictionary) -> PFProviderTaskV2:
	var task := ProviderTaskV2Script.new(request, [])
	_generation_tasks[String(request.get("request_id", ""))] = task
	call_deferred("_finish_generation", task, request.duplicate(true))
	return task


func _fixture_actual_cost(request: Dictionary) -> Variant:
	var micro_usd := 250000 * maxi(1, int(request.get("batch", 1)))
	return "%d.%06d" % [micro_usd / 1000000, micro_usd % 1000000]


func cancel(request_id: String) -> PFCancelTaskV2:
	if _cancel_tasks.has(request_id):
		return _cancel_tasks[request_id]
	var task := CancelTaskV2Script.new(request_id, PROVIDER_ID)
	_cancel_tasks[request_id] = task
	_cancel_requested[request_id] = true
	call_deferred("_finish_cancel", task, request_id)
	return task


func clear_session_config() -> void:
	configured_key = ""
	configured_endpoint = ""
	_generation_tasks.clear()
	_cancel_tasks.clear()
	_cancel_requested.clear()


func _finish_generation(task: PFProviderTaskV2, request: Dictionary) -> void:
	var request_id := String(request.get("request_id", ""))
	if task.is_terminal():
		return
	if _cancel_requested.has(request_id):
		return
	if configured_key != "fixture-good-key":
		task.reject(_provider_error("auth_failed", request))
		_generation_tasks.erase(request_id)
		return
	var items := []
	for index in range(int(request.get("batch", 1))):
		var image := Image.create(
			int(request.get("target_width", 1)),
			int(request.get("target_height", 1)),
			false,
			Image.FORMAT_RGBA8
		)
		items.append({"index": index, "image": image, "actual_seed": index, "error": null})
	(
		task
		. resolve(
			{
				"request_id": String(request.get("request_id", "")),
				"items": items,
				"actual_cost_usd": _fixture_actual_cost(request),
				"charge_id": "",
				"provider_meta": {},
			}
		)
	)
	_generation_tasks.erase(request_id)
	_cancel_requested.erase(request_id)


func _finish_cancel(task: PFCancelTaskV2, request_id: String) -> void:
	var generation: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if generation != null:
		generation.mark_canceled(request_id)
	(
		task
		. resolve(
			{
				"request_id": request_id,
				"local_stopped": true,
				"remote_cancel_confirmed": false,
				"billing_update": null,
			}
		)
	)
	_generation_tasks.erase(request_id)
	_cancel_requested.erase(request_id)


func _provider_error(code: String, request: Dictionary) -> Dictionary:
	return {
		"code": code,
		"stage": "provider",
		"provider_id": PROVIDER_ID,
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": String(request.get("request_id", "fixture-request")),
		"attempts": 1,
		"expected_count": maxi(0, int(request.get("batch", 0))),
		"received_count": 0,
	}
