class_name PFRetroDiffusionProvider
extends PFProvider

## RetroDiffusion v1 inference adapter using the official 2026-07 API example fields.
## contract: 02-contracts/PROVIDER-API.md；official source: Retro-Diffusion/api-examples.

const HttpClientScript := preload("res://infra/http_client.gd")
const ProviderTaskV2Script := preload("res://core/provider/pf_provider_task_v2.gd")
const CancelTaskV2Script := preload("res://services/pf_cancel_task_v2.gd")
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

const PROVIDER_ID := "retrodiffusion"
const API_VERSION := 2
const DEFAULT_ENDPOINT := "https://api.retrodiffusion.ai/v1/inferences"
const DEFAULT_STYLE_LOW_RES := "rd_plus__low_res"
const DEFAULT_STYLE_STANDARD := "rd_pro__default"
const DEFAULT_STYLE_LARGE := "rd_fast__default"
const REQUEST_TIMEOUT_SECONDS := 180.0
const MAX_BATCH := 4
const MAX_RETRIES := 0
const RETRY_BACKOFF_SECONDS := 0.5
const DOCUMENTED_RD_PRO_UNIT_COST_MICRO_USD := 250000
const MODEL_STYLES := {
	"rd_plus": DEFAULT_STYLE_LOW_RES,
	"rd_pro": DEFAULT_STYLE_STANDARD,
	"rd_fast": DEFAULT_STYLE_LARGE,
}

var _request_host: Node = null
var _http: Node = null
var _api_key := ""
var _endpoint := DEFAULT_ENDPOINT
var _generation_tasks := {}
var _transport_tasks := {}
var _cancel_tasks := {}
var _cancel_requested := {}


func get_api_version() -> int:
	return API_VERSION


func get_model_descriptors() -> Array[Dictionary]:
	return [
		_model_descriptor("rd_plus", "RD Plus", true, 128),
		_model_descriptor("rd_pro", "RD Pro", false, 256),
		_model_descriptor("rd_fast", "RD Fast", false, 384),
	]


func get_config_schema() -> Array[Dictionary]:
	return [
		{
			"key": "api_key",
			"kind": "password",
			"label_key": "RETRO_FIELD_API_KEY",
			"help_key": "RETRO_FIELD_API_KEY_HELP",
			"required": true,
			"default": "",
		},
		{
			"key": "endpoint",
			"kind": "string",
			"label_key": "RETRO_FIELD_ENDPOINT",
			"help_key": "RETRO_FIELD_ENDPOINT_HELP",
			"required": true,
			"default": DEFAULT_ENDPOINT,
		},
	]


func attach_request_host(host: Node) -> void:
	_request_host = host
	if _http == null:
		_http = HttpClientScript.new()
		_http.name = "RetroDiffusionHttpClient"
		host.add_child(_http)


func configure(config: Dictionary) -> Variant:
	var candidate := String(config.get("api_key", "")).strip_edges()
	if candidate.is_empty():
		return {"code": "auth_failed", "field": "api_key", "args": {}}
	_api_key = candidate
	_endpoint = String(config.get("endpoint", DEFAULT_ENDPOINT)).strip_edges()
	if _endpoint.is_empty():
		_endpoint = DEFAULT_ENDPOINT
	return null


func clear_session_config() -> void:
	_api_key = ""
	if _http != null:
		_http.cancel_all()


func has_session_credentials() -> bool:
	return not _api_key.is_empty()


func validate_credentials() -> Variant:
	return null


func generate(request: Dictionary) -> PFProviderTaskV2:
	var wrapper := ProviderTaskV2Script.new(request, ["remote_task_id"])
	var request_copy := request.duplicate(true)
	if not _is_ready_for_request():
		call_deferred("_reject_unavailable", wrapper, request_copy)
		return wrapper
	var request_id := String(request["request_id"])
	_generation_tasks[request_id] = wrapper
	call_deferred("_start_generation", request_copy, wrapper)
	return wrapper


func _start_generation(request: Dictionary, wrapper: PFProviderTaskV2) -> void:
	var request_id := String(request["request_id"])
	if wrapper.is_terminal():
		return
	if _cancel_requested.has(request_id):
		_finish_canceled(request_id)
		return
	(
		wrapper
		. emit_progress(
			{
				"phase": "submitting",
				"determinate": false,
				"ratio": null,
				"completed_items": 0,
				"total_items": request["batch"],
			}
		)
	)
	var body := build_request_body(request)
	var transport: PFTask = (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint,
			_headers(),
			body,
			{
				"timeout": REQUEST_TIMEOUT_SECONDS,
				"retries": MAX_RETRIES,
				"backoff": RETRY_BACKOFF_SECONDS,
				"transform": _decode_generation_response.bind(request),
				"worker_transform": true,
				"error_mapper": map_error.bind(request),
			}
		)
	)
	_transport_tasks[request_id] = transport
	transport.finished.connect(_on_transport_completed.bind(request_id))
	transport.failed.connect(_on_transport_failed.bind(request, request_id))
	transport.canceled.connect(_finish_canceled.bind(request_id))
	TaskQueue.submit(transport)


func estimate_cost(request: Dictionary) -> Variant:
	if String(request.get("model_id", "")) != "rd_pro":
		return null
	var micro_usd := DOCUMENTED_RD_PRO_UNIT_COST_MICRO_USD * int(request.get("batch", 0))
	return "%d.%06d" % [micro_usd / 1000000, micro_usd % 1000000]


func cancel(request_id: String) -> PFCancelTaskV2:
	if _cancel_tasks.has(request_id):
		return _cancel_tasks[request_id]
	var wrapper := CancelTaskV2Script.new(request_id, PROVIDER_ID)
	_cancel_tasks[request_id] = wrapper
	_cancel_requested[request_id] = true
	var transport: PFTask = _transport_tasks.get(request_id)
	if transport != null:
		transport.cancel()
	else:
		call_deferred("_finish_canceled", request_id)
	return wrapper


func build_request_body(request: Dictionary) -> Dictionary:
	var output_size: Array = request.get("provider_output_size", [32, 32])
	var width := int(output_size[0])
	var height := int(output_size[1])
	var extra: Dictionary = request.get("extra", {})
	var body := {
		"width": width,
		"height": height,
		"prompt": String(request.get("prompt", "sprite")).strip_edges(),
		"prompt_style": String(MODEL_STYLES.get(String(request.get("model_id", "")), "")),
		"num_images": clampi(int(request.get("batch", 1)), 1, MAX_BATCH),
		"remove_bg": bool(extra.get("remove_bg", true)),
	}
	var seed := int(request.get("seed", -1))
	if seed >= 0:
		body["seed"] = seed
	var reference_images: Array = request["ref_images"]
	if not reference_images.is_empty():
		body["input_image"] = Marshalls.raw_to_base64(
			(reference_images[0] as Image).save_png_to_buffer()
		)
		body["strength"] = clampf(float(extra.get("strength", 0.8)), 0.0, 1.0)
	return body


func decode_success_payload(payload: Dictionary, request: Dictionary) -> Dictionary:
	var items := []
	var encoded_images: Variant = payload.get("base64_images", [])
	if not (encoded_images is Array):
		return _failure("ambiguous_result", request)
	for index in range(encoded_images.size()):
		var encoded_value: Variant = encoded_images[index]
		var bytes := Marshalls.base64_to_raw(String(encoded_value))
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			items.append(_failed_item(index, request, "ambiguous_result"))
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var base_seed := int(request.get("seed", -1))
		var expected_size: Array = request.get("provider_output_size", [])
		if (
			expected_size.size() == 2
			and (
				image.get_width() != int(expected_size[0])
				or image.get_height() != int(expected_size[1])
			)
		):
			items.append(_failed_item(index, request, "ambiguous_result"))
		else:
			(
				items
				. append(
					{
						"index": index,
						"image": image,
						"actual_seed": base_seed + index if base_seed >= 0 else null,
						"error": null,
					}
				)
			)
	if items.is_empty():
		return _failure("ambiguous_result", request)
	return {
		"request_id": String(request.get("request_id", "")),
		"items": items,
		"actual_cost_usd": _actual_cost(payload.get("balance_cost")),
		"charge_id": _safe_identifier(payload.get("charge_id", ""), true),
		"provider_meta": _provider_meta(payload),
	}


func map_error(
	result: int, status_code: int, detail: Dictionary = {}, request: Dictionary = {}
) -> Dictionary:
	var code := "provider_internal"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
	if result == HTTPRequest.RESULT_SUCCESS:
		var provider_code := String(detail.get("provider_code", "")).to_lower()
		match status_code:
			401, 403:
				code = "auth_failed"
			429:
				code = "rate_limited"
			400:
				var insufficient := "credit" in provider_code or "balance" in provider_code
				code = "quota_exceeded" if insufficient else "invalid_request"
	var normalized := _provider_error(
		code,
		"http",
		request if not request.is_empty() else _validation_request(),
		maxi(1, int(detail.get("attempts", 1)))
	)
	if status_code >= 100 and status_code <= 599:
		normalized["status_code"] = status_code
	var safe_code := String(detail.get("provider_code", "")).to_lower()
	if "credit" in safe_code or "balance" in safe_code:
		normalized["provider_code"] = safe_code
	return normalized


func _decode_generation_response(response: Dictionary, request: Dictionary) -> Dictionary:
	var payload: Variant = response.get("body", {})
	if not (payload is Dictionary):
		return _failure("ambiguous_result", request)
	return decode_success_payload(payload, request)


func _headers() -> PackedStringArray:
	return PackedStringArray(["X-RD-Token: %s" % _api_key, "Content-Type: application/json"])


func _is_ready_for_request() -> bool:
	return (
		not _api_key.is_empty()
		and _request_host != null
		and is_instance_valid(_request_host)
		and _http != null
	)


func _on_transport_completed(result: Variant, request_id: String) -> void:
	var wrapper: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if wrapper != null and result is Dictionary:
		wrapper.resolve(result)
	_clear_active_request(request_id)


func _on_transport_failed(error: Dictionary, request: Dictionary, request_id: String) -> void:
	var wrapper: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if wrapper != null:
		wrapper.reject(_normalize_transport_error(error, request))
	_clear_active_request(request_id)


func _finish_canceled(request_id: String) -> void:
	var generation: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if generation != null:
		generation.mark_canceled(request_id)
	var cancel_task: PFCancelTaskV2 = _cancel_tasks.get(request_id)
	if cancel_task != null:
		(
			cancel_task
			. resolve(
				{
					"request_id": request_id,
					"local_stopped": true,
					"remote_cancel_confirmed": false,
					"billing_update": null,
				}
			)
		)
	_clear_active_request(request_id)


func _reject_unavailable(wrapper: PFProviderTaskV2, request: Dictionary) -> void:
	wrapper.reject(_provider_error("provider_internal", "queue", request, 0))


func _normalize_transport_error(error: Dictionary, request: Dictionary) -> Dictionary:
	if ContractV2.validate_pf_error(error) == null:
		return error.duplicate(true)
	return _provider_error("provider_internal", "http", request, 1)


func _provider_error(
	code: String, stage: String, request: Dictionary, attempts: int, received_count: int = 0
) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": PROVIDER_ID,
		"retryable": code in ["result_count_mismatch", "interrupted"],
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": String(request.get("request_id", "")),
		"attempts": attempts,
		"expected_count": maxi(0, int(request.get("batch", 0))),
		"received_count": maxi(0, received_count),
	}


func _failed_item(index: int, request: Dictionary, code: String) -> Dictionary:
	return {
		"index": index,
		"image": null,
		"actual_seed": null,
		"error": _provider_error(code, "decode", request, 1, index),
	}


func _actual_cost(value: Variant) -> Variant:
	if value is int or value is float:
		var amount := float(value)
		if is_finite(amount) and amount >= 0.0:
			var micro_usd := int(floor(amount * 1000000.0 + 0.5))
			return "%d.%06d" % [micro_usd / 1000000, micro_usd % 1000000]
	return null


func _provider_meta(payload: Dictionary) -> Dictionary:
	var remote_id := _safe_identifier(payload.get("remote_task_id", payload.get("id", "")), false)
	return {"remote_task_id": remote_id} if not remote_id.is_empty() else {}


func _safe_identifier(value: Variant, allow_empty: bool) -> String:
	var text := String(value)
	if allow_empty and text.is_empty():
		return ""
	var expression := RegEx.new()
	var minimum := 0 if allow_empty else 1
	var pattern := "^[A-Za-z0-9._:-]{%d,128}$" % minimum
	return text if expression.compile(pattern) == OK and expression.search(text) != null else ""


func _clear_active_request(request_id: String) -> void:
	_generation_tasks.erase(request_id)
	_transport_tasks.erase(request_id)
	_cancel_requested.erase(request_id)


func _validation_request() -> Dictionary:
	return {"request_id": "credential-validation", "provider_id": PROVIDER_ID, "batch": 0}


func _failure(code: String, request: Dictionary) -> Dictionary:
	return {"ok": false, "error": _provider_error(code, "decode", request, 1)}


func _model_descriptor(
	model_id: String, display_name: String, is_default: bool, max_side: int
) -> Dictionary:
	return {
		"provider_id": PROVIDER_ID,
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
			"max_batch": MAX_BATCH,
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
			"cost_estimate": model_id == "rd_pro",
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
