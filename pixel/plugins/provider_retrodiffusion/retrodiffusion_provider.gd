class_name PFRetroDiffusionProvider
extends PFProvider

## RetroDiffusion v1 inference adapter using the official 2026-07 API example fields.
## contract: 02-contracts/PROVIDER-API.md；official source: Retro-Diffusion/api-examples.

const HttpClientScript := preload("res://infra/http_client.gd")
const TaskScript := preload("res://services/pf_task.gd")

const PROVIDER_ID := "retrodiffusion"
const API_VERSION := 1
const DEFAULT_ENDPOINT := "https://api.retrodiffusion.ai/v1/inferences"
const DEFAULT_STYLE_LOW_RES := "rd_plus__low_res"
const DEFAULT_STYLE_STANDARD := "rd_pro__default"
const DEFAULT_STYLE_LARGE := "rd_fast__default"
const REQUEST_TIMEOUT_SECONDS := 180.0
const MAX_BATCH := 4
const MAX_RETRIES := 3
const RETRY_BACKOFF_SECONDS := 0.5
const DOCUMENTED_RD_PRO_UNIT_COST := 0.25
const MODEL_STYLES := {
	"rd_plus": DEFAULT_STYLE_LOW_RES,
	"rd_pro": DEFAULT_STYLE_STANDARD,
	"rd_fast": DEFAULT_STYLE_LARGE,
}

var _request_host: Node = null
var _http: Node = null
var _api_key := ""
var _endpoint := DEFAULT_ENDPOINT


func get_id() -> String:
	return PROVIDER_ID


func get_display_name() -> String:
	return "RetroDiffusion"


func get_api_version() -> int:
	return API_VERSION


func get_capabilities() -> Dictionary:
	return {
		"txt2img": true,
		"img2img": true,
		"inpaint": false,
		"transparent_bg": true,
		"native_pixel": true,
		"max_batch": MAX_BATCH,
		"sizes": [[16, 16], [384, 384]],
		"animation": false,
		"cost_estimate": true,
	}


func get_model_descriptors() -> Array[Dictionary]:
	return [
		_model_descriptor("rd_plus", "RD Plus", true, 128),
		_model_descriptor("rd_pro", "RD Pro", false, 256),
		_model_descriptor("rd_fast", "RD Fast", false, 384),
	]


func validate_generation_request(request: Dictionary) -> Variant:
	var normalized_request := request.duplicate(true)
	if String(normalized_request.get("model_id", "")).strip_edges().is_empty():
		normalized_request["model_id"] = _legacy_model_for_request(normalized_request)
	return super.validate_generation_request(normalized_request)


func get_config_schema() -> Array[Dictionary]:
	return [
		{"key": "api_key", "label": "RetroDiffusion API key", "kind": "password"},
		{
			"key": "endpoint",
			"label": "Inference endpoint",
			"kind": "text",
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
		return _error("auth_failed", "Enter a RetroDiffusion API key")
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
	if not _is_ready_for_request():
		return null
	var body := {
		"width": 64,
		"height": 64,
		"prompt": "credential validation",
		"prompt_style": DEFAULT_STYLE_LOW_RES,
		"num_images": 1,
		"check_cost": true,
	}
	return (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_endpoint,
			_headers(),
			body,
			{
				"timeout": REQUEST_TIMEOUT_SECONDS,
				"retries": 0,
				"transform": _decode_validation_response,
				"error_mapper": map_error,
			}
		)
	)


func generate(request: Dictionary) -> Variant:
	var request_error: Variant = validate_generation_request(request)
	if request_error != null:
		return _rejected_task(request_error)
	if not _is_ready_for_request():
		return null
	var body := build_request_body(request)
	return (
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
				"error_mapper": map_error,
			}
		)
	)


func estimate_cost(request: Dictionary) -> float:
	var style := _style_for_request(request)
	if style != DEFAULT_STYLE_STANDARD:
		return -1.0
	return DOCUMENTED_RD_PRO_UNIT_COST * clampi(int(request.get("batch", 1)), 1, MAX_BATCH)


func cancel(task_id: String) -> void:
	if _http != null:
		_http.cancel(task_id)


func build_request_body(request: Dictionary) -> Dictionary:
	var width := clampi(int(request.get("width", 32)), 16, 384)
	var height := clampi(int(request.get("height", 32)), 16, 384)
	var extra: Dictionary = request.get("extra", {})
	var body := {
		"width": width,
		"height": height,
		"prompt": String(request.get("prompt", "sprite")).strip_edges(),
		"prompt_style": _style_for_request(request),
		"num_images": clampi(int(request.get("batch", 1)), 1, MAX_BATCH),
		"remove_bg": bool(extra.get("remove_bg", true)),
	}
	var seed := int(request.get("seed", -1))
	if seed >= 0:
		body["seed"] = seed
	var reference_images := get_reference_images(request)
	if not reference_images.is_empty():
		body["input_image"] = Marshalls.raw_to_base64(
			(reference_images[0] as Image).save_png_to_buffer()
		)
		body["strength"] = clampf(float(extra.get("strength", 0.8)), 0.0, 1.0)
	return body


func decode_success_payload(payload: Dictionary, request: Dictionary) -> Dictionary:
	var images := []
	for encoded_value in payload.get("base64_images", []):
		var bytes := Marshalls.base64_to_raw(String(encoded_value))
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		images.append(image)
	if images.is_empty():
		return _failure("provider_internal", "RetroDiffusion returned no decodable PNG images")
	var seeds := []
	var base_seed := int(request.get("seed", -1))
	for index in range(images.size()):
		seeds.append(base_seed + index if base_seed >= 0 else null)
	return {
		"ok": true,
		"images": images,
		"raw_pixel": true,
		"seeds": seeds,
		"cost": float(payload.get("balance_cost", -1.0)),
		"provider_meta":
		{
			"model": String(payload.get("model", "")),
			"remaining_balance": payload.get("remaining_balance", null),
			"created_at": payload.get("created_at", null),
			"prompt_style": _style_for_request(request),
		},
	}


func map_error(result: int, status_code: int, detail: Dictionary = {}) -> Dictionary:
	var code := "provider_internal"
	var result_message := "RetroDiffusion request failed"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
		result_message = "RetroDiffusion request timed out; try again"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
		result_message = "Could not reach RetroDiffusion; check the network"
	var response: Dictionary = detail.get("response", {})
	var api_detail: Dictionary = response.get("detail", {})
	var api_code := String(api_detail.get("code", "")).to_lower()
	var api_message := String(api_detail.get("message", "")).strip_edges()
	if result == HTTPRequest.RESULT_SUCCESS:
		match status_code:
			401, 403:
				code = "auth_failed"
				result_message = "RetroDiffusion rejected the API key"
			429:
				code = "rate_limited"
				result_message = "RetroDiffusion is rate limited; retry later"
			400:
				var insufficient := (
					"credit" in api_code
					or "balance" in api_code
					or "insufficient" in api_message.to_lower()
				)
				code = "quota_exceeded" if insufficient else "invalid_request"
				result_message = (
					"RetroDiffusion balance is insufficient"
					if insufficient
					else (
						api_message
						if not api_message.is_empty()
						else "RetroDiffusion rejected the request"
					)
				)
			_:
				if status_code >= 500:
					result_message = "RetroDiffusion inference failed"
	return _error(code, result_message, detail)


func _decode_generation_response(response: Dictionary, request: Dictionary) -> Dictionary:
	var payload: Variant = response.get("body", {})
	if not (payload is Dictionary):
		return _failure("provider_internal", "RetroDiffusion returned an invalid response")
	return decode_success_payload(payload, request)


func _decode_validation_response(response: Dictionary) -> Dictionary:
	var payload: Dictionary = response.get("body", {})
	return {
		"ok": true,
		"provider_id": PROVIDER_ID,
		"estimated_cost": float(payload.get("balance_cost", -1.0)),
		"remaining_balance": payload.get("remaining_balance", null),
	}


func _style_for_request(request: Dictionary) -> String:
	var requested_model := String(request.get("model_id", "")).strip_edges()
	if not requested_model.is_empty():
		var resolved_model := resolve_model_id(requested_model)
		if MODEL_STYLES.has(resolved_model):
			return String(MODEL_STYLES[resolved_model])
	var style: Dictionary = request.get("style", {})
	var hints: Dictionary = style.get("provider_hints", {})
	var retro_hint: Dictionary = hints.get("retrodiffusion", {})
	var hinted := String(retro_hint.get("style", "")).strip_edges()
	if not hinted.is_empty():
		return hinted
	var largest_side := maxi(int(request.get("width", 32)), int(request.get("height", 32)))
	if largest_side <= 128:
		return DEFAULT_STYLE_LOW_RES
	if largest_side <= 256:
		return DEFAULT_STYLE_STANDARD
	return DEFAULT_STYLE_LARGE


func _legacy_model_for_request(request: Dictionary) -> String:
	var largest_side := maxi(int(request.get("width", 32)), int(request.get("height", 32)))
	if largest_side <= 128:
		return "rd_plus"
	if largest_side <= 256:
		return "rd_pro"
	return "rd_fast"


func _headers() -> PackedStringArray:
	return PackedStringArray(["X-RD-Token: %s" % _api_key, "Content-Type: application/json"])


func _is_ready_for_request() -> bool:
	return (
		not _api_key.is_empty()
		and _request_host != null
		and is_instance_valid(_request_host)
		and _http != null
	)


func _error(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	return {"code": code, "message": message, "detail": detail, "recoverable": true}


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": _error(code, message)}


func _model_descriptor(
	model_id: String, display_name: String, is_default: bool, max_side: int
) -> Dictionary:
	return {
		"provider_id": PROVIDER_ID,
		"model_id": model_id,
		"display_name": display_name,
		"is_default": is_default,
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"max_reference_images": 1,
			"output_size_constraints": {"min_side": 16, "max_side": max_side},
			"max_batch": MAX_BATCH,
			"seed": true,
			"transparent_bg": true,
			"cost_estimate": model_id == "rd_pro",
		}
	}


func _rejected_task(error: Dictionary) -> PFTask:
	var task := TaskScript.new("retrodiffusion_generate", {"provider_id": PROVIDER_ID})
	task.configure_external(func(task_ref: PFTask) -> void: task_ref.reject(error))
	return task
