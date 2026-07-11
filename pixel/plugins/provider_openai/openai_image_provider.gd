class_name PFOpenAIImageProvider
extends PFProvider

## OpenAI GPT Image 2 provider using the shared asynchronous HTTP transport.
## contract: 02-contracts/PROVIDER-API.md; credentials stay in memory and redacted headers.

const HttpClientScript := preload("res://infra/http_client.gd")

const PROVIDER_ID := "openai_image"
const API_VERSION := 1
const MODEL_ID := "gpt-image-2"
const GENERATION_URL := "https://api.openai.com/v1/images/generations"
const VALIDATION_URL := "https://api.openai.com/v1/models/gpt-image-2"
const REQUEST_TIMEOUT_SECONDS := 180.0
const MAX_NETWORK_RETRIES := 1
const RETRY_DELAY_SECONDS := 0.25
const MAX_BATCH := 4

var _request_host: Node = null
var _http: Node = null
var _api_key := ""
var _generation_url := GENERATION_URL
var _validation_url := VALIDATION_URL


func get_id() -> String:
	return PROVIDER_ID


func get_display_name() -> String:
	return "OpenAI GPT Image 2"


func get_api_version() -> int:
	return API_VERSION


func get_capabilities() -> Dictionary:
	return {
		"txt2img": true,
		"img2img": false,
		"inpaint": false,
		"transparent_bg": true,
		"native_pixel": false,
		"max_batch": MAX_BATCH,
		"sizes": [[16, 16], [512, 512]],
		"animation": false,
		"cost_estimate": false,
	}


func get_config_schema() -> Array[Dictionary]:
	return [{"key": "api_key", "label": "OpenAI API key", "kind": "password"}]


func attach_request_host(host: Node) -> void:
	_request_host = host
	if _http == null:
		_http = HttpClientScript.new()
		_http.name = "OpenAIHttpClient"
		host.add_child(_http)


func configure(config: Dictionary) -> Variant:
	var candidate := String(config.get("api_key", "")).strip_edges()
	if candidate.is_empty():
		return _error("auth_failed", "Enter an OpenAI API key")
	_api_key = candidate
	_generation_url = String(config.get("generation_url", GENERATION_URL)).strip_edges()
	_validation_url = String(config.get("validation_url", VALIDATION_URL)).strip_edges()
	if _generation_url.is_empty():
		_generation_url = GENERATION_URL
	if _validation_url.is_empty():
		_validation_url = VALIDATION_URL
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
	return (
		_http
		. request_json(
			HTTPClient.METHOD_GET,
			_validation_url,
			_headers(),
			null,
			{
				"timeout": REQUEST_TIMEOUT_SECONDS,
				"retries": 0,
				"transform": _decode_validation_response,
				"error_mapper": map_error,
			}
		)
	)


func generate(request: Dictionary) -> Variant:
	if not _is_ready_for_request():
		return null
	return (
		_http
		. request_json(
			HTTPClient.METHOD_POST,
			_generation_url,
			_headers(),
			build_request_body(request),
			{
				"timeout": REQUEST_TIMEOUT_SECONDS,
				"retries": MAX_NETWORK_RETRIES,
				"backoff": RETRY_DELAY_SECONDS,
				"transform": _decode_generation_response.bind(request),
				"worker_transform": true,
				"error_mapper": map_error,
			}
		)
	)


func estimate_cost(_request: Dictionary) -> float:
	# GPT Image 2's official page currently points to a dynamic calculator rather than a stable
	# per-image table. Unknown is safer than a stale hard-coded amount.
	return -1.0


func cancel(task_id: String) -> void:
	if _http != null:
		_http.cancel(task_id)


func build_request_body(request: Dictionary) -> Dictionary:
	var width := maxi(1, int(request.get("width", 32)))
	var height := maxi(1, int(request.get("height", 32)))
	var prompt := String(request.get("prompt", "sprite")).strip_edges()
	var adapted_prompt := (
		(
			"%s. Pixel art game sprite designed for a %dx%d true-pixel target, flat colors, "
			+ "crisp hard edges, no anti-aliasing, isolated on a transparent background."
		)
		% [prompt, width, height]
	)
	return {
		"model": MODEL_ID,
		"prompt": adapted_prompt,
		"n": clampi(int(request.get("batch", 1)), 1, MAX_BATCH),
		"size": _output_size(width, height),
		"quality": "low",
		"background": "transparent",
		"output_format": "png",
	}


func decode_success_payload(payload: Dictionary, request: Dictionary) -> Dictionary:
	var images := []
	var revised_prompts := []
	var data: Variant = payload.get("data", [])
	if not (data is Array):
		return _failure("provider_internal", "OpenAI response did not contain an image list")
	for item_value in data:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var encoded := String(item.get("b64_json", ""))
		if encoded.is_empty():
			continue
		var bytes := Marshalls.base64_to_raw(encoded)
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		images.append(image)
		revised_prompts.append(String(item.get("revised_prompt", "")))
	if images.is_empty():
		return _failure("provider_internal", "OpenAI returned no decodable PNG images")
	var seeds := []
	for _image in images:
		seeds.append(null)
	return {
		"ok": true,
		"images": images,
		"raw_pixel": false,
		"seeds": seeds,
		"cost": -1.0,
		"provider_meta":
		{
			"model": MODEL_ID,
			"usage": payload.get("usage", {}),
			"revised_prompts": revised_prompts,
			"target_size": [int(request.get("width", 32)), int(request.get("height", 32))],
			"output_size":
			String(
				payload.get(
					"size",
					_output_size(int(request.get("width", 32)), int(request.get("height", 32)))
				)
			),
			"quality": String(payload.get("quality", "low")),
			"background": String(payload.get("background", "transparent")),
			"output_format": String(payload.get("output_format", "png")),
		},
	}


func map_error(result: int, status_code: int, detail: Dictionary = {}) -> Dictionary:
	var code := "provider_internal"
	var result_message := "OpenAI image generation failed"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
		result_message = "OpenAI image generation timed out; try again"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
		result_message = "Could not reach OpenAI; check the network and try again"
	var response: Dictionary = detail.get("response", detail)
	var api_error: Dictionary = (
		response.get("error", {}) if response.get("error", {}) is Dictionary else {}
	)
	var api_code := String(api_error.get("code", ""))
	var message := String(api_error.get("message", "")).strip_edges()
	if result == HTTPRequest.RESULT_SUCCESS:
		match status_code:
			401, 403:
				code = "auth_failed"
				result_message = "OpenAI rejected the API key"
			429:
				code = "rate_limited"
				result_message = "OpenAI is rate limited; wait and try again"
			400:
				code = (
					"content_policy"
					if api_code in ["moderation_blocked", "content_policy_violation"]
					else "invalid_request"
				)
				result_message = (
					"The prompt was blocked by OpenAI content policy"
					if code == "content_policy"
					else message if not message.is_empty() else "OpenAI rejected the request"
				)
			_:
				if status_code >= 500:
					result_message = "OpenAI image service failed; try again"
				elif not message.is_empty():
					result_message = message
	return _error(code, result_message, detail)


func should_retry(result: int, status_code: int, attempt: int) -> bool:
	if attempt >= MAX_NETWORK_RETRIES:
		return false
	return result != HTTPRequest.RESULT_SUCCESS or status_code >= 500


func _decode_generation_response(response: Dictionary, request: Dictionary) -> Dictionary:
	var payload: Variant = response.get("body", {})
	if not (payload is Dictionary):
		return _failure("provider_internal", "OpenAI returned an invalid response")
	return decode_success_payload(payload, request)


func _decode_validation_response(_response: Dictionary) -> Dictionary:
	return {"ok": true, "provider_id": PROVIDER_ID}


func _output_size(width: int, height: int) -> String:
	if width > height * 1.2:
		return "1536x1024"
	if height > width * 1.2:
		return "1024x1536"
	return "1024x1024"


func _headers() -> PackedStringArray:
	return PackedStringArray(
		["Authorization: Bearer %s" % _api_key, "Content-Type: application/json"]
	)


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
