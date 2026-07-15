class_name PFOpenAIImageProvider
extends PFProvider

## OpenAI GPT Image 2 provider using the shared asynchronous HTTP transport.
## contract: 02-contracts/PROVIDER-API.md; credentials stay in memory and redacted headers.

const HttpClientScript := preload("res://infra/http_client.gd")
const ProviderTaskV2Script := preload("res://core/provider/pf_provider_task_v2.gd")
const CancelSettlementV2Script := preload("res://services/provider_cancel_settlement_v2.gd")
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

const PROVIDER_ID := "openai_image"
const API_VERSION := 2
const MODEL_ID := "gpt-image-2"
const DEFAULT_BASE_URL := "https://api.openai.com/v1"
const GENERATION_URL := DEFAULT_BASE_URL + "/images/generations"
const EDIT_URL := DEFAULT_BASE_URL + "/images/edits"
const VALIDATION_URL := DEFAULT_BASE_URL + "/models/" + MODEL_ID
const MULTIPART_BOUNDARY := "----PixelForgeImageBoundary7MA4YWxkTrZu0gW"
const REQUEST_TIMEOUT_SECONDS := 180.0
const MAX_NETWORK_RETRIES := 0
const PING_NETWORK_RETRIES := 0
const RETRY_DELAY_SECONDS := 0.25
const MAX_BATCH := 4

var _request_host: Node = null
var _http: Node = null
var _api_key := ""
var _base_url := DEFAULT_BASE_URL
var _generation_url := GENERATION_URL
var _edit_url := EDIT_URL
var _validation_url := VALIDATION_URL
var _request_timeout_seconds := REQUEST_TIMEOUT_SECONDS
var _generation_tasks := {}
var _generation_requests := {}
var _transport_tasks := {}
var _cancel_requested := {}
var _cancel_settlement: Variant = CancelSettlementV2Script.new(PROVIDER_ID)


func _init(
	generation_url: String = GENERATION_URL,
	edit_url: String = EDIT_URL,
	validation_url: String = VALIDATION_URL,
	request_timeout_seconds: float = REQUEST_TIMEOUT_SECONDS
) -> void:
	_generation_url = (
		generation_url.strip_edges() if not generation_url.is_empty() else GENERATION_URL
	)
	_edit_url = edit_url.strip_edges() if not edit_url.is_empty() else EDIT_URL
	_validation_url = (
		validation_url.strip_edges() if not validation_url.is_empty() else VALIDATION_URL
	)
	_request_timeout_seconds = maxf(0.01, request_timeout_seconds)


func get_api_version() -> int:
	return API_VERSION


func get_model_descriptors() -> Array[Dictionary]:
	return [
		{
			"provider_id": PROVIDER_ID,
			"model_id": MODEL_ID,
			"display_name": "GPT Image 2",
			"is_default": true,
			"ui_scope": "main",
			"provider_meta_keys": ["remote_task_id"],
			"capabilities":
			{
				"txt2img": true,
				"img2img": true,
				"max_reference_images": 4,
				"max_batch": MAX_BATCH,
				"target_size_constraints":
				{
					"min_width": 720,
					"max_width": 3840,
					"width_step": 1,
					"min_height": 720,
					"max_height": 3840,
					"height_step": 1,
					"allowed_sizes": _fixed_delivery_sizes(),
				},
				"provider_output_sizes": _fixed_request_sizes(),
				"native_pixel": false,
				"native_idempotency": false,
				"safe_validation": true,
				"seed": false,
				"transparent_bg": false,
			},
			"dynamic_params": [],
		}
	]


static func _fixed_delivery_sizes() -> Array:
	return [
		[1280, 720],
		[720, 1280],
		[720, 720],
		[1920, 1080],
		[1080, 1920],
		[1080, 1080],
		[2560, 1440],
		[1440, 2560],
		[1440, 1440],
		[3840, 2160],
		[2160, 3840],
		[2160, 2160],
	]


static func _fixed_request_sizes() -> Array:
	return [
		[1280, 720],
		[720, 1280],
		[720, 720],
		[1920, 1088],
		[1088, 1920],
		[1088, 1088],
		[2560, 1440],
		[1440, 2560],
		[1440, 1440],
		[3840, 2160],
		[2160, 3840],
		[2160, 2160],
	]


func get_config_schema() -> Array[Dictionary]:
	return [
		{
			"key": "base_url",
			"kind": "string",
			"label_key": "OPENAI_FIELD_BASE_URL",
			"help_key": "OPENAI_FIELD_BASE_URL_HELP",
			"required": true,
			"default": DEFAULT_BASE_URL,
		},
		{
			"key": "api_key",
			"kind": "password",
			"label_key": "OPENAI_FIELD_API_KEY",
			"help_key": "OPENAI_FIELD_API_KEY_HELP",
			"required": true,
			"default": "",
		}
	]


func attach_request_host(host: Node) -> void:
	_request_host = host
	if _http == null:
		_http = HttpClientScript.new()
		_http.name = "OpenAIHttpClient"
		host.add_child(_http)


func configure(config: Dictionary) -> Variant:
	for key_value in config.keys():
		var key := String(key_value)
		if key not in ["api_key", "base_url"]:
			return {"code": "invalid_request", "field": key, "args": {}}
	var candidate := String(config.get("api_key", "")).strip_edges()
	if candidate.is_empty():
		return {"code": "auth_failed", "field": "api_key", "args": {}}
	if config.has("base_url"):
		var normalized_base_url := _normalize_base_url(String(config["base_url"]))
		if normalized_base_url.is_empty():
			return {"code": "invalid_request", "field": "base_url", "args": {}}
		_base_url = normalized_base_url
		_generation_url = _base_url + "/images/generations"
		_edit_url = _base_url + "/images/edits"
		_validation_url = _base_url + "/models/" + MODEL_ID
	_api_key = candidate
	return null


func get_base_url() -> String:
	return _base_url


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
				"timeout": _request_timeout_seconds,
				"retries": PING_NETWORK_RETRIES,
				"max_redirects": 0,
				"transform": _decode_validation_response,
				"error_mapper": map_validation_error,
			}
		)
	)


func generate(request: Dictionary) -> PFProviderTaskV2:
	var wrapper := ProviderTaskV2Script.new(request, ["remote_task_id"])
	var request_copy := request.duplicate(true)
	if not _is_ready_for_request():
		call_deferred("_reject_unavailable", wrapper, request_copy)
		return wrapper
	var request_id := String(request["request_id"])
	_generation_tasks[request_id] = wrapper
	_generation_requests[request_id] = request_copy
	call_deferred("_start_generation", request_copy, wrapper)
	return wrapper


func _start_generation(request: Dictionary, wrapper: PFProviderTaskV2) -> void:
	var request_id := String(request["request_id"])
	if wrapper.is_terminal():
		return
	if _cancel_requested.has(request_id):
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
	var references: Array = request["ref_images"]
	var transport: PFTask
	if not references.is_empty():
		var multipart := build_edit_request(request)
		transport = (
			_http
			. request_raw(
				HTTPClient.METHOD_POST,
				_edit_url,
				_headers("multipart/form-data; boundary=%s" % MULTIPART_BOUNDARY),
				multipart,
				{
					"timeout": _request_timeout_seconds,
					"retries": MAX_NETWORK_RETRIES,
					"backoff": RETRY_DELAY_SECONDS,
					"transform": _decode_raw_generation_response.bind(request),
					"worker_transform": true,
					"error_mapper": map_error.bind(request),
				}
			)
		)
	else:
		transport = (
			_http
			. request_json(
				HTTPClient.METHOD_POST,
				_generation_url,
				_headers(),
				build_request_body(request),
				{
					"timeout": _request_timeout_seconds,
					"retries": MAX_NETWORK_RETRIES,
					"backoff": RETRY_DELAY_SECONDS,
					"transform": _decode_generation_response.bind(request),
					"worker_transform": true,
					"error_mapper": map_error.bind(request),
				}
			)
		)
	_transport_tasks[request_id] = transport
	transport.finished.connect(_on_transport_completed.bind(request_id))
	transport.failed.connect(_on_transport_failed.bind(request, request_id))
	transport.canceled.connect(_on_transport_canceled.bind(request_id))
	TaskQueue.submit(transport)
	(
		wrapper
		. emit_progress(
			{
				"phase": "provider_processing",
				"determinate": false,
				"ratio": null,
				"completed_items": 0,
				"total_items": request["batch"],
			}
		)
	)


func cancel(request_id: String) -> PFCancelTaskV2:
	var existing: Variant = _cancel_settlement.get_cancel_task(request_id)
	if existing != null:
		return existing
	var generation: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if generation == null:
		generation = ProviderTaskV2Script.new(
			{"request_id": request_id, "provider_id": PROVIDER_ID, "batch": 0}, []
		)
	_cancel_requested[request_id] = true
	var transport: PFTask = _transport_tasks.get(request_id)
	var wrapper: PFCancelTaskV2 = _cancel_settlement.cancel(
		request_id,
		generation,
		transport == null,
		func() -> void:
			if transport != null:
				transport.cancel()
	)
	wrapper.resolved.connect(func(_result: Dictionary) -> void: _clear_active_request(request_id))
	wrapper.rejected.connect(func(_error: Dictionary) -> void: _clear_active_request(request_id))
	return wrapper


func build_request_body(request: Dictionary) -> Dictionary:
	var prompt := String(request.get("prompt", "sprite")).strip_edges()
	var output_size: Array = request.get("provider_output_size", [1024, 1024])
	return {
		"model": MODEL_ID,
		"prompt": prompt,
		"n": clampi(int(request.get("batch", 1)), 1, MAX_BATCH),
		"size": "%dx%d" % [output_size[0], output_size[1]],
		"background": "opaque",
		"output_format": "png",
	}


func build_edit_request(request: Dictionary) -> PackedByteArray:
	var body := PackedByteArray()
	var fields := build_request_body(request)
	for key in ["model", "prompt", "n", "size", "background", "output_format"]:
		_append_multipart_text(body, str(key), str(fields[key]))
	var references: Array = request["ref_images"]
	for index in range(references.size()):
		var image: Image = references[index]
		_append_utf8(
			body,
			(
				(
					"--%s\r\n"
					+ 'Content-Disposition: form-data; name="image[]"; filename="reference-%02d.png"\r\n'
					+ "Content-Type: image/png\r\n\r\n"
				)
				% [MULTIPART_BOUNDARY, index + 1]
			)
		)
		body.append_array(image.save_png_to_buffer())
		_append_utf8(body, "\r\n")
	_append_utf8(body, "--%s--\r\n" % MULTIPART_BOUNDARY)
	return body


func decode_success_payload(payload: Dictionary, request: Dictionary) -> Dictionary:
	var items := []
	var data: Variant = payload.get("data", [])
	if not (data is Array):
		return _failure("ambiguous_result", request)
	for index in range(data.size()):
		var item_value: Variant = data[index]
		if not (item_value is Dictionary):
			items.append(_failed_item(index, request, "ambiguous_result"))
			continue
		var item: Dictionary = item_value
		var encoded := String(item.get("b64_json", ""))
		if encoded.is_empty():
			items.append(_failed_item(index, request, "ambiguous_result"))
			continue
		var bytes := Marshalls.base64_to_raw(encoded)
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			items.append(_failed_item(index, request, "ambiguous_result"))
			continue
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
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
			items.append({"index": index, "image": image, "actual_seed": null, "error": null})
	return {
		"request_id": String(request.get("request_id", "")),
		"items": items,
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": _provider_meta(payload),
	}


func map_error(
	result: int, status_code: int, detail: Dictionary = {}, request: Dictionary = {}
) -> Dictionary:
	var code := "provider_internal"
	var is_generation := int(request.get("batch", 0)) > 0
	if is_generation and bool(detail.get("malformed_json", false)):
		code = "ambiguous_result"
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			code = "timeout"
		elif not is_generation or not bool(detail.get("request_dispatched", true)):
			code = "network"
		else:
			code = "ambiguous_result"
	if result == HTTPRequest.RESULT_SUCCESS:
		var provider_code := String(detail.get("provider_code", ""))
		match status_code:
			401, 403:
				code = "auth_failed"
			429:
				code = "rate_limited"
			400:
				code = (
					"content_policy"
					if provider_code in ["moderation_blocked", "content_policy_violation"]
					else "invalid_request"
				)
			500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511:
				code = "ambiguous_result" if is_generation else "provider_internal"
	var normalized := _provider_error(
		code,
		"http",
		request if not request.is_empty() else _validation_request(),
		maxi(1, int(detail.get("attempts", 1)))
	)
	if status_code >= 100 and status_code <= 599:
		normalized["status_code"] = status_code
	var provider_code := String(detail.get("provider_code", ""))
	if provider_code in ["moderation_blocked", "content_policy_violation"]:
		normalized["provider_code"] = provider_code
	return normalized


func should_retry(result: int, status_code: int, attempt: int) -> bool:
	if attempt >= MAX_NETWORK_RETRIES:
		return false
	return result != HTTPRequest.RESULT_SUCCESS or status_code >= 500


func _decode_generation_response(response: Dictionary, request: Dictionary) -> Dictionary:
	var payload: Variant = response.get("body", {})
	if not (payload is Dictionary):
		return _failure("ambiguous_result", request)
	return decode_success_payload(payload, request)


func _decode_raw_generation_response(response: Dictionary, request: Dictionary) -> Dictionary:
	var body: Variant = response.get("body", PackedByteArray())
	if not (body is PackedByteArray):
		return _failure("ambiguous_result", request)
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (payload is Dictionary):
		return _failure("ambiguous_result", request)
	return decode_success_payload(payload, request)


func _decode_validation_response(response: Dictionary) -> Dictionary:
	var payload: Variant = response.get("body", {})
	if payload is Dictionary and String(payload.get("id", "")) == MODEL_ID:
		return {"ok": true, "status": "success", "provider_id": PROVIDER_ID}
	return {"ok": true, "status": "model_unconfirmed", "provider_id": PROVIDER_ID}


func map_validation_error(result: int, status_code: int, detail: Dictionary = {}) -> Dictionary:
	var code := "protocol_error"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
	else:
		match status_code:
			401, 403:
				code = "auth_failed"
			404:
				code = "model_unconfirmed"
			429:
				code = "rate_limited"
			_:
				code = "protocol_error"
	if bool(detail.get("malformed_json", false)):
		code = "protocol_error"
	return {"code": code}


func _normalize_base_url(value: String) -> String:
	var candidate := value.strip_edges()
	while candidate.ends_with("/"):
		candidate = candidate.left(-1)
	if candidate.is_empty() or candidate.contains("?") or candidate.contains("#"):
		return ""
	var pattern := RegEx.new()
	var expression := (
		"^https?://(?:[A-Za-z0-9._-]+|\\[[0-9A-Fa-f:]+\\])"
		+ "(?::([0-9]{1,5}))?(?:/[A-Za-z0-9._~!$&'()*+,;=:@%/-]*)?$"
	)
	if pattern.compile(expression) != OK:
		return ""
	var result := pattern.search(candidate)
	if result == null:
		return ""
	var port := result.get_string(1)
	if not port.is_empty() and int(port) > 65535:
		return ""
	return candidate


func _headers(content_type: String = "application/json") -> PackedStringArray:
	return PackedStringArray(
		["Authorization: Bearer %s" % _api_key, "Content-Type: %s" % content_type]
	)


func _append_multipart_text(body: PackedByteArray, field_name: String, value: String) -> void:
	_append_utf8(
		body,
		(
			("--%s\r\n" + 'Content-Disposition: form-data; name="%s"\r\n\r\n' + "%s\r\n")
			% [MULTIPART_BOUNDARY, field_name, value]
		)
	)


func _append_utf8(body: PackedByteArray, text: String) -> void:
	body.append_array(text.to_utf8_buffer())


func _is_ready_for_request() -> bool:
	return (
		not _api_key.is_empty()
		and _request_host != null
		and is_instance_valid(_request_host)
		and _http != null
	)


func _on_transport_completed(result: Variant, request_id: String) -> void:
	var wrapper: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if _cancel_requested.has(request_id):
		_cancel_settlement.confirm_local_stopped(request_id, _billing_update(result))
		return
	if wrapper != null and result is Dictionary:
		_emit_decode_progress(wrapper, request_id)
		wrapper.resolve(result)
	_clear_active_request(request_id)


func _on_transport_failed(error: Dictionary, request: Dictionary, request_id: String) -> void:
	var wrapper: PFProviderTaskV2 = _generation_tasks.get(request_id)
	if _cancel_requested.has(request_id):
		_cancel_settlement.confirm_local_stopped(request_id, null)
		return
	if wrapper != null:
		wrapper.reject(_normalize_transport_error(error, request))
	_clear_active_request(request_id)


func _on_transport_canceled(request_id: String) -> void:
	_cancel_settlement.confirm_local_stopped(request_id, null)


func _billing_update(result: Variant) -> Variant:
	if not (result is Dictionary) or result.get("actual_cost_usd") == null:
		return null
	return {
		"actual_cost_usd": result.get("actual_cost_usd"),
		"charge_id": result.get("charge_id", ""),
		"provider_meta": result.get("provider_meta", {}).duplicate(true),
	}


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
		"retryable":
		(
			code
			in [
				"rate_limited",
				"network",
				"malformed_response",
				"result_count_mismatch",
				"interrupted"
			]
		),
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


func _provider_meta(payload: Dictionary) -> Dictionary:
	for key in ["remote_task_id", "id"]:
		var value := String(payload.get(key, ""))
		var expression := RegEx.new()
		if (
			expression.compile("^[A-Za-z0-9._:-]{1,128}$") == OK
			and expression.search(value) != null
		):
			return {"remote_task_id": value}
	return {}


func _clear_active_request(request_id: String) -> void:
	_generation_tasks.erase(request_id)
	_generation_requests.erase(request_id)
	_transport_tasks.erase(request_id)
	_cancel_requested.erase(request_id)


func _emit_decode_progress(wrapper: PFProviderTaskV2, request_id: String) -> void:
	var request: Dictionary = _generation_requests.get(request_id, {})
	var total := maxi(1, int(request.get("batch", 1)))
	for progress in [
		{
			"phase": "downloading",
			"determinate": false,
			"ratio": null,
			"completed_items": 0,
			"total_items": total,
		},
		{
			"phase": "decoding",
			"determinate": true,
			"ratio": 1.0,
			"completed_items": total,
			"total_items": total,
		},
	]:
		wrapper.emit_progress(progress)


func _validation_request() -> Dictionary:
	return {"request_id": "credential-validation", "provider_id": PROVIDER_ID, "batch": 0}


func _failure(code: String, request: Dictionary) -> Dictionary:
	return {"ok": false, "error": _provider_error(code, "decode", request, 1)}
