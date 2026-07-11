class_name PFOpenAIImageProvider
extends PFProvider

## OpenAI Image API 的 M4-V1 最小 Provider。
## contract: 02-contracts/PROVIDER-API.md；API key 只驻留内存，不进入 task payload、日志或项目。

const TaskScript := preload("res://services/pf_task.gd")

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
var _api_key := ""
var _requests := {}


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
		"transparent_bg": false,
		"native_pixel": false,
		"max_batch": MAX_BATCH,
		"sizes": [[16, 16], [512, 512]],
		"animation": false,
		"cost_estimate": false,
	}


func get_config_schema() -> Array[Dictionary]:
	return [
		{
			"key": "api_key",
			"label": "OpenAI API key",
			"kind": "password",
		}
	]


func attach_request_host(host: Node) -> void:
	_request_host = host


func configure(config: Dictionary) -> Variant:
	var candidate := String(config.get("api_key", "")).strip_edges()
	if candidate.is_empty():
		return {"code": "auth_failed", "message": "Enter an OpenAI API key for this session"}
	_api_key = candidate
	return null


func clear_session_config() -> void:
	_api_key = ""
	for task_id in _requests.keys():
		var state: Dictionary = _requests[task_id]
		var task: Variant = state.get("task")
		if task != null:
			task.cancel()
	_requests.clear()


func has_session_credentials() -> bool:
	return not _api_key.is_empty()


func validate_credentials() -> Variant:
	var task := TaskScript.new("provider_validate", {"provider_id": PROVIDER_ID})
	task.configure_external(
		_start_request.bind(HTTPClient.METHOD_GET, VALIDATION_URL, {}, "validate"), _cancel_task
	)
	return task


func generate(request: Dictionary) -> Variant:
	var body := build_request_body(request)
	var task := TaskScript.new(
		"provider_generate", {"provider_id": PROVIDER_ID, "request": body.duplicate(true)}
	)
	task.configure_external(
		_start_request.bind(HTTPClient.METHOD_POST, GENERATION_URL, body, "generate"), _cancel_task
	)
	return task


func estimate_cost(_request: Dictionary) -> float:
	return -1.0


func cancel(task_id: String) -> void:
	if not _requests.has(task_id):
		return
	var task: Variant = _requests[task_id].get("task")
	if task != null:
		task.cancel()


func build_request_body(request: Dictionary) -> Dictionary:
	var width := maxi(1, int(request.get("width", 32)))
	var height := maxi(1, int(request.get("height", 32)))
	var prompt := String(request.get("prompt", "sprite")).strip_edges()
	var adapted_prompt := (
		(
			"%s. Pixel art game sprite designed for a %dx%d true-pixel target, flat colors, "
			+ "crisp hard edges, no anti-aliasing, isolated on a plain contrasting background."
		)
		% [prompt, width, height]
	)
	return {
		"model": MODEL_ID,
		"prompt": adapted_prompt,
		"n": clampi(int(request.get("batch", 1)), 1, MAX_BATCH),
		"size": _output_size(width, height),
		"quality": "low",
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
		var load_error := image.load_png_from_buffer(bytes)
		if load_error != OK:
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
		},
	}


func map_error(result: int, status_code: int, payload: Dictionary = {}) -> Dictionary:
	var code := "provider_internal"
	var result_message := "OpenAI image generation failed"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
		result_message = "OpenAI image generation timed out; try again"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
		result_message = "Could not reach OpenAI; check the network and try again"
	var api_error: Dictionary = (
		payload.get("error", {}) if payload.get("error", {}) is Dictionary else {}
	)
	var api_code := String(api_error.get("code", ""))
	var message := String(api_error.get("message", "")).strip_edges()
	if result == HTTPRequest.RESULT_SUCCESS:
		match status_code:
			401, 403:
				code = "auth_failed"
				result_message = "OpenAI rejected the session key"
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
	return _error(code, result_message)


func should_retry(result: int, status_code: int, attempt: int) -> bool:
	if attempt >= MAX_NETWORK_RETRIES:
		return false
	return result != HTTPRequest.RESULT_SUCCESS or status_code >= 500


func _start_request(
	task: Variant, method: int, url: String, body: Dictionary, mode: String
) -> void:
	if _api_key.is_empty():
		task.reject(_error("auth_failed", "Configure an OpenAI API key for this session"))
		return
	if _request_host == null or not is_instance_valid(_request_host):
		task.reject(_error("provider_internal", "OpenAI request host is unavailable"))
		return
	_attempt_request(task, method, url, body, mode, 0)


func _attempt_request(
	task: Variant, method: int, url: String, body: Dictionary, mode: String, attempt: int
) -> void:
	if task.cancel_requested:
		task.resolve(null)
		return
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT_SECONDS
	_request_host.add_child(request)
	_requests[task.id] = {
		"task": task,
		"request": request,
		"method": method,
		"url": url,
		"body": body,
		"mode": mode,
		"attempt": attempt,
	}
	request.request_completed.connect(_on_request_completed.bind(task.id))
	var headers := PackedStringArray(
		["Authorization: Bearer %s" % _api_key, "Content-Type: application/json"]
	)
	var request_error := request.request(
		url, headers, method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else ""
	)
	if request_error != OK:
		var failed_state: Dictionary = _requests[task.id]
		_finish_request_node(task.id)
		_handle_failed_attempt(
			task, HTTPRequest.RESULT_REQUEST_FAILED, 0, {}, attempt, failed_state
		)


func _on_request_completed(
	result: int,
	response_code: int,
	_response_headers: PackedStringArray,
	body_bytes: PackedByteArray,
	task_id: String
) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	var task: Variant = state["task"]
	var attempt := int(state["attempt"])
	var mode := String(state["mode"])
	var request_body: Dictionary = state["body"]
	_finish_request_node(task_id)
	var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
	var payload: Dictionary = parsed if parsed is Dictionary else {}
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_handle_failed_attempt(task, result, response_code, payload, attempt, state)
		return
	if mode == "validate":
		task.resolve({"ok": true, "provider_id": PROVIDER_ID})
		return
	var decoded := decode_success_payload(payload, request_body)
	if not bool(decoded.get("ok", false)):
		task.reject(decoded.get("error", {}))
		return
	task.resolve(decoded)


func _handle_failed_attempt(
	task: Variant,
	result: int,
	status_code: int,
	payload: Dictionary,
	attempt: int,
	state: Dictionary = {}
) -> void:
	if should_retry(result, status_code, attempt):
		task.report_progress(0.1, "Retrying network request (1/1)")
		_retry_request_later(task, state, attempt + 1)
		return
	task.reject(map_error(result, status_code, payload))


func _retry_request_later(task: Variant, state: Dictionary, next_attempt: int) -> void:
	state["task"] = task
	state["request"] = null
	_requests[task.id] = state
	await _request_host.get_tree().create_timer(RETRY_DELAY_SECONDS).timeout
	if task.cancel_requested:
		task.resolve(null)
		return
	if _api_key.is_empty():
		_finish_request_node(task.id)
		task.reject(_error("auth_failed", "Configure an OpenAI API key for this session"))
		return
	_attempt_request(
		task,
		int(state.get("method", HTTPClient.METHOD_POST)),
		String(state.get("url", GENERATION_URL)),
		state.get("body", {}),
		String(state.get("mode", "generate")),
		next_attempt
	)


func _cancel_task(task: Variant) -> void:
	if _requests.has(task.id):
		var request: HTTPRequest = _requests[task.id].get("request")
		if request != null:
			request.cancel_request()
	_finish_request_node(task.id)
	task.resolve(null)


func _finish_request_node(task_id: String) -> void:
	if not _requests.has(task_id):
		return
	var request: HTTPRequest = _requests[task_id].get("request")
	if request != null:
		request.queue_free()
	_requests.erase(task_id)


func _output_size(width: int, height: int) -> String:
	if width > height * 1.2:
		return "1536x1024"
	if height > width * 1.2:
		return "1024x1536"
	return "1024x1024"


func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "recoverable": true}


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": _error(code, message)}
