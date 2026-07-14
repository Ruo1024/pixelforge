class_name PFHttpClient
extends Node

## 生产级异步 HTTP 封装；每次尝试使用独立 HTTPRequest，并把终态归一化为 PFTask。
## contract: 02-contracts/PROVIDER-API.md §6；本层不知道凭据语义，只负责头部脱敏。

signal request_started(task_id: String, url: String, method: int)
signal request_attempted(task_id: String, attempt: int, timestamp_msec: int)
signal request_completed(task_id: String, result: Dictionary)

const TaskScript := preload("res://services/pf_task.gd")
const Log := preload("res://core/util/log_util.gd")
const RetrySchedulerScript := preload("res://infra/retry_scheduler.gd")

const DEFAULT_TIMEOUT_SECONDS := 60.0
const DEFAULT_RETRIES := 0
const DEFAULT_BACKOFF_SECONDS := 0.5
const GENERATION_TIMEOUT_SECONDS := 180.0

var _requests := {}
var _retry_scheduler: RefCounted = RetrySchedulerScript.new()


func set_retry_scheduler(scheduler: RefCounted) -> void:
	_retry_scheduler = scheduler if scheduler != null else RetrySchedulerScript.new()


func request_json(
	method: int,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: Variant = null,
	opts: Dictionary = {}
) -> Variant:
	var body_bytes := PackedByteArray()
	if body != null:
		body_bytes = JSON.stringify(body).to_utf8_buffer()
	return _make_task(method, url, headers, body_bytes, true, opts)


func request_raw(
	method: int,
	url: String,
	headers: PackedStringArray = PackedStringArray(),
	body: PackedByteArray = PackedByteArray(),
	opts: Dictionary = {}
) -> Variant:
	return _make_task(method, url, headers, body, false, opts)


func cancel_all() -> void:
	for task_id in _requests.keys():
		var task: Variant = _requests[task_id].get("task")
		if task != null:
			task.cancel()


func cancel(task_id: String) -> void:
	if _requests.has(task_id):
		var task: Variant = _requests[task_id].get("task")
		if task != null:
			task.cancel()


func map_error(result: int, status_code: int, detail: Dictionary = {}) -> Dictionary:
	var code := "provider_internal"
	var message := "The request failed"
	if result == HTTPRequest.RESULT_TIMEOUT:
		code = "timeout"
		message = "The request timed out; try again"
	elif result != HTTPRequest.RESULT_SUCCESS:
		code = "network"
		message = "The service could not be reached; check the network"
	else:
		match status_code:
			401, 403:
				code = "auth_failed"
				message = "The service rejected the credentials"
			402:
				code = "quota_exceeded"
				message = "The service quota is exhausted"
			429:
				code = "rate_limited"
				message = "The service is rate limited; retry later"
			400, 404, 405, 409, 422:
				code = "invalid_request"
				message = "The service rejected the request"
			_:
				if status_code >= 500:
					message = "The service failed; try again"
	return _error(code, message, detail)


func _make_task(
	method: int,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	expect_json: bool,
	opts: Dictionary
) -> Variant:
	var safe_opts := _normalize_opts(method, opts)
	var safe_url := _safe_log_url(url)
	var task := (
		TaskScript
		. new(
			"http_request",
			{
				"method": method,
				"url": safe_url,
				"timeout_seconds": safe_opts["timeout"],
				"retries": safe_opts["retries"],
			}
		)
	)
	task.configure_external(
		_start_request.bind(method, url, headers, body, expect_json, safe_opts), _cancel_task
	)
	return task


func _normalize_opts(method: int, opts: Dictionary) -> Dictionary:
	var requested_retries := maxi(0, int(opts.get("retries", DEFAULT_RETRIES)))
	var safe_get_retries := mini(requested_retries, 2) if method == HTTPClient.METHOD_GET else 0
	return {
		"timeout": maxf(0.01, float(opts.get("timeout", DEFAULT_TIMEOUT_SECONDS))),
		"retries": safe_get_retries,
		"backoff": maxf(0.0, float(opts.get("backoff", DEFAULT_BACKOFF_SECONDS))),
		"log_requests": bool(opts.get("log_requests", false)),
		"transform": opts.get("transform", Callable()),
		"worker_transform": bool(opts.get("worker_transform", false)),
		"error_mapper": opts.get("error_mapper", Callable()),
	}


func _start_request(
	task: Variant,
	method: int,
	url: String,
	headers: PackedStringArray,
	body: PackedByteArray,
	expect_json: bool,
	opts: Dictionary
) -> void:
	if not is_inside_tree():
		task.reject(_error("provider_internal", "HTTP request host is unavailable"))
		return
	_requests[task.id] = {
		"task": task,
		"request": null,
		"method": method,
		"url": url,
		"headers": headers,
		"body": body,
		"expect_json": expect_json,
		"opts": opts,
		"attempt": 0,
		"request_dispatched": false,
	}
	request_started.emit(task.id, _safe_log_url(url), method)
	_attempt_request(task.id)


func _attempt_request(task_id: String) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	var task: Variant = state["task"]
	if task.cancel_requested:
		_cancel_task(task)
		return
	var request := HTTPRequest.new()
	request.timeout = float(state["opts"]["timeout"])
	add_child(request)
	state["request"] = request
	state["request_dispatched"] = false
	_requests[task_id] = state
	request.request_completed.connect(_on_request_completed.bind(task_id))
	var attempt := int(state["attempt"])
	request_attempted.emit(task_id, attempt, _retry_scheduler.monotonic_msec())
	_log_request_if_enabled(state)
	var request_error := request.request_raw(
		String(state["url"]), state["headers"], int(state["method"]), state["body"]
	)
	if request_error != OK:
		_dispose_request(state)
		_handle_failure(
			task_id, HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()
		)
	else:
		state["request_dispatched"] = true
		_requests[task_id] = state


func _on_request_completed(
	result: int,
	status_code: int,
	response_headers: PackedStringArray,
	body: PackedByteArray,
	task_id: String
) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	_dispose_request(state)
	if result != HTTPRequest.RESULT_SUCCESS or status_code < 200 or status_code >= 300:
		_handle_failure(task_id, result, status_code, response_headers, body)
		return
	var response_body: Variant = body
	if bool(state["expect_json"]):
		var json := JSON.new()
		var parse_error := json.parse(body.get_string_from_utf8())
		if parse_error != OK:
			var error_mapper: Callable = state["opts"]["error_mapper"]
			var detail := {
				"status_code": status_code,
				"attempts": int(state["attempt"]) + 1,
				"request_dispatched": bool(state.get("request_dispatched", false)),
				"malformed_json": true,
			}
			var error: Dictionary = (
				error_mapper.call(HTTPRequest.RESULT_SUCCESS, status_code, detail)
				if error_mapper.is_valid()
				else (_error(
					"provider_internal",
					"The service returned malformed JSON",
					{"reason": "malformed_json", "status_code": status_code}
				))
			)
			_finish_failed(task_id, error)
			return
		response_body = json.data
	var response := {
		"ok": true,
		"status_code": status_code,
		"headers": response_headers,
		"body": response_body,
		"raw_body": body,
		"attempts": int(state["attempt"]) + 1,
	}
	var transform: Callable = state["opts"]["transform"]
	if transform.is_valid():
		if bool(state["opts"]["worker_transform"]):
			_transform_response_on_worker(task_id, response, transform)
			return
		response = _apply_response_transform(response, transform)
	else:
		response = {
			"ok": true,
			"status_code": status_code,
			"attempts": int(state["attempt"]) + 1,
		}
	_complete_success(task_id, response)


func _complete_success(task_id: String, response: Dictionary) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	if state.has("transform_worker_id"):
		WorkerThreadPool.wait_for_task_completion(int(state["transform_worker_id"]))
	var task: Variant = state["task"]
	if not bool(response.get("ok", true)) and response.has("error"):
		_finish_failed(task_id, response["error"])
		return
	_requests.erase(task_id)
	request_completed.emit(task_id, response)
	task.resolve(response)


func _transform_response_on_worker(
	task_id: String, response: Dictionary, transform: Callable
) -> void:
	var worker := func() -> void:
		var transformed := _apply_response_transform(response, transform)
		call_deferred("_complete_success", task_id, transformed)
	var worker_id := WorkerThreadPool.add_task(worker, false, "PFHttpTransform:%s" % task_id)
	var state: Dictionary = _requests[task_id]
	state["transform_worker_id"] = worker_id
	_requests[task_id] = state


func _apply_response_transform(response: Dictionary, transform: Callable) -> Dictionary:
	var transformed: Variant = transform.call(response)
	if transformed is Dictionary:
		return transformed
	return {
		"ok": false,
		"error": _error("provider_internal", "The service response could not be decoded"),
	}


func _handle_failure(
	task_id: String,
	result: int,
	status_code: int,
	response_headers: PackedStringArray,
	response_body: PackedByteArray
) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	var attempt := int(state["attempt"])
	var retries := int(state["opts"]["retries"])
	if attempt < retries and _is_retryable(result, status_code):
		var next_attempt := attempt + 1
		var delay_seconds: float = float(_retry_scheduler.delay_for(attempt, response_headers))
		state["attempt"] = next_attempt
		_requests[task_id] = state
		var task: Variant = state["task"]
		task.report_progress(0.0, "Retrying network request (%d/%d)" % [next_attempt, retries])
		_retry_after(task_id, delay_seconds)
		return
	var detail := {
		"status_code": status_code,
		"attempts": attempt + 1,
		"request_dispatched": bool(state.get("request_dispatched", false)),
	}
	var provider_code := _safe_provider_code(response_body)
	if not provider_code.is_empty():
		detail["provider_code"] = provider_code
	var error_mapper: Callable = state["opts"]["error_mapper"]
	var error: Dictionary = (
		error_mapper.call(result, status_code, detail)
		if error_mapper.is_valid()
		else map_error(result, status_code, {"status_code": status_code, "attempts": attempt + 1})
	)
	_finish_failed(task_id, error)


func _safe_provider_code(response_body: PackedByteArray) -> String:
	if response_body.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(response_body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return ""
	var body: Dictionary = parsed
	var code := String(body.get("code", "")).strip_edges()
	for container_key in ["error", "detail"]:
		var container: Variant = body.get(container_key, {})
		if code.is_empty() and container is Dictionary:
			code = String(container.get("code", "")).strip_edges()
	if code.is_empty() or code.length() > 64:
		return ""
	var allowed := RegEx.new()
	if allowed.compile("^[A-Za-z0-9._:-]{1,64}$") != OK or allowed.search(code) == null:
		return ""
	return code


func _retry_after(task_id: String, delay_seconds: float) -> void:
	await _retry_scheduler.wait(delay_seconds)
	if _requests.has(task_id):
		_attempt_request(task_id)


func _finish_failed(task_id: String, error: Dictionary) -> void:
	if not _requests.has(task_id):
		return
	var state: Dictionary = _requests[task_id]
	var task: Variant = state["task"]
	_dispose_request(state)
	_requests.erase(task_id)
	task.reject(error)


func _cancel_task(task: Variant) -> void:
	if _requests.has(task.id):
		var state: Dictionary = _requests[task.id]
		var request: HTTPRequest = state.get("request")
		if request != null:
			request.cancel_request()
		_dispose_request(state)
		_requests.erase(task.id)
	task.resolve(null)


func _dispose_request(state: Dictionary) -> void:
	var request: HTTPRequest = state.get("request")
	if request != null and is_instance_valid(request):
		request.queue_free()
	state["request"] = null


func _is_retryable(result: int, status_code: int) -> bool:
	return result != HTTPRequest.RESULT_SUCCESS or status_code == 429 or status_code >= 500


func _log_request_if_enabled(state: Dictionary) -> void:
	if not bool(state["opts"]["log_requests"]) and not _global_request_logging_enabled():
		return
	(
		Log
		. debug(
			"HTTP request",
			{
				"method": state["method"],
				"url": _safe_log_url(String(state["url"])),
				"headers": _redacted_headers(state["headers"]),
				"attempt": state["attempt"],
			}
		)
	)


func _global_request_logging_enabled() -> bool:
	var settings := get_tree().root.get_node_or_null("SettingsService")
	return settings != null and bool(settings.get_setting("network", "request_logging", false))


func _redacted_headers(headers: PackedStringArray) -> PackedStringArray:
	var redacted := PackedStringArray()
	for header in headers:
		var separator := header.find(":")
		var name := header.substr(0, separator).strip_edges() if separator >= 0 else header
		var normalized := name.to_lower()
		if _is_sensitive_header_name(normalized):
			redacted.append("%s: [REDACTED]" % name)
		else:
			redacted.append(header)
	return redacted


func _is_sensitive_header_name(normalized_name: String) -> bool:
	if (
		normalized_name
		in [
			"authorization",
			"proxy-authorization",
			"x-api-key",
			"api-key",
			"x-rd-token",
			"cookie",
			"set-cookie",
		]
	):
		return true
	for marker in ["token", "secret", "credential", "api-key"]:
		if normalized_name.contains(marker):
			return true
	return false


func _safe_log_url(url: String) -> String:
	var expression := RegEx.new()
	if expression.compile("^(https?)://([^/?#]+)([^?#]*)") != OK:
		return "[invalid-url]"
	var match_result := expression.search(url.strip_edges())
	if match_result == null:
		return "[invalid-url]"
	var authority := match_result.get_string(2)
	if authority.contains("@"):
		authority = authority.get_slice("@", authority.get_slice_count("@") - 1)
	var path := match_result.get_string(3)
	return "%s://%s%s" % [match_result.get_string(1), authority, path]


func _error(code: String, message: String, detail: Dictionary = {}) -> Dictionary:
	return {"code": code, "message": message, "detail": detail, "recoverable": true}
