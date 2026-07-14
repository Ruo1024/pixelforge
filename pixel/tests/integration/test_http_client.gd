extends "res://addons/gut/test.gd"

const HttpClientScript := preload("res://infra/http_client.gd")
const RetrySchedulerScript := preload("res://infra/retry_scheduler.gd")
const ManualRetryWaiterScript := preload("res://tests/fixtures/http/manual_retry_waiter.gd")
const SentinelScanner := preload("res://tests/helpers/credential_sentinel_scanner.gd")
const FileIOScript := preload("res://infra/file_io.gd")

const CREDENTIAL_SENTINEL := SentinelScanner.VALUE
const SENTINEL_PROJECT_PATH := "user://tests/b7_1_sentinel_project.pxproj"

var _client: Node
var _queue: Node
var _base_url := ""


func before_each() -> void:
	_base_url = OS.get_environment("PF_HTTP_MOCK_URL")
	assert_false(_base_url.is_empty(), "run_tests.sh must start the local HTTP fixture server")
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_queue.set_max_concurrency(2)
	_client = HttpClientScript.new()
	add_child_autofree(_client)


func test_success_returns_parsed_json_result() -> void:
	var outcome := await _run_request("/success")

	assert_eq(outcome["status"], "finished")
	assert_true(outcome["value"]["ok"])
	assert_eq(outcome["value"]["status_code"], 200)
	assert_false(outcome["value"].has("body"))
	assert_false(outcome["value"].has("headers"))
	assert_false(outcome["value"].has("raw_body"))


func test_401_maps_to_auth_failed() -> void:
	var outcome := await _run_request("/auth")

	assert_eq(outcome["status"], "failed")
	assert_eq(outcome["value"]["code"], "auth_failed")


func test_429_without_retry_maps_to_rate_limited() -> void:
	var outcome := await _run_request("/rate-limit")

	assert_eq(outcome["status"], "failed")
	assert_eq(outcome["value"]["code"], "rate_limited")


func test_timeout_maps_to_timeout() -> void:
	var outcome := await _run_request("/timeout", {"timeout": 0.05})

	assert_eq(outcome["status"], "failed")
	assert_eq(outcome["value"]["code"], "timeout")


func test_malformed_json_maps_to_provider_internal() -> void:
	var outcome := await _run_request("/malformed")

	assert_eq(outcome["status"], "failed")
	assert_eq(outcome["value"]["code"], "provider_internal")
	assert_eq(outcome["value"]["detail"]["reason"], "malformed_json")


func test_safe_get_retries_at_most_three_attempts_with_fake_scheduler() -> void:
	var timestamps := []
	var waiter := ManualRetryWaiterScript.new()
	var clock := {"value": 1000}
	var scheduler := RetrySchedulerScript.new(
		func() -> float: return 1445412420.0,
		func() -> int:
			clock["value"] += 10
			return int(clock["value"]),
		waiter.wait
	)
	_client.set_retry_scheduler(scheduler)
	_client.request_attempted.connect(
		func(_task_id: String, _attempt: int, timestamp_msec: int) -> void:
			timestamps.append(timestamp_msec)
	)
	var task: Variant = _client.request_json(
		HTTPClient.METHOD_GET,
		_base_url + "/safe-retry",
		PackedStringArray(),
		null,
		{"retries": 99, "timeout": 1.0}
	)
	var outcome := _watch_task(task)
	_queue.submit(task)

	assert_true(
		await _wait_until(func() -> bool: return timestamps.size() == 1 and waiter.pending_count == 1)
	)
	assert_eq(timestamps, [1010])
	assert_eq(waiter.delays, [30.0])
	waiter.advance()
	assert_true(
		await _wait_until(func() -> bool: return timestamps.size() == 2 and waiter.pending_count == 1)
	)
	assert_eq(timestamps, [1010, 1020])
	assert_eq(waiter.delays, [30.0, 30.0])
	waiter.advance()
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "finished")
	assert_eq(outcome["value"]["attempts"], 3)
	assert_eq(timestamps, [1010, 1020, 1030])


func test_retry_scheduler_parses_http_date_clamps_and_uses_fixed_fallbacks() -> void:
	var scheduler := RetrySchedulerScript.new(func() -> float: return 1445412420.0)
	assert_eq(
		scheduler.delay_for(0, PackedStringArray(["Retry-After: Wed, 21 Oct 2015 07:28:00 GMT"])),
		30.0
	)
	assert_eq(scheduler.delay_for(0, PackedStringArray(["Retry-After: 0"])), 0.25)
	assert_eq(
		scheduler.delay_for(0, PackedStringArray(["Retry-After: Wed, 21 Oct 2015 07:26:00 GMT"])),
		0.25
	)
	assert_eq(scheduler.delay_for(0, PackedStringArray()), 0.5)
	assert_eq(scheduler.delay_for(1, PackedStringArray()), 1.0)


func test_sensitive_headers_are_redacted_for_request_logs() -> void:
	var redacted: PackedStringArray = _client.call(
		"_redacted_headers",
		PackedStringArray(["Authorization: Bearer secret", "X-Api-Key: secret", "Accept: */*"])
	)

	assert_eq(redacted[0], "Authorization: [REDACTED]")
	assert_eq(redacted[1], "X-Api-Key: [REDACTED]")
	assert_eq(redacted[2], "Accept: */*")


func test_sensitive_header_names_are_case_insensitive_trimmed_and_pattern_redacted() -> void:
	var redacted: PackedStringArray = _client.call(
		"_redacted_headers",
		PackedStringArray(
			[
				"  x-rD-ToKeN  : sentinel",
				"Cookie: sentinel",
				"Set-Cookie: sentinel",
				"X-Custom-Secret: sentinel",
				"Credential-Bag: sentinel",
				"X-Session-Token: sentinel",
				"Accept: */*",
			]
		)
	)

	for index in range(6):
		assert_false(redacted[index].contains("sentinel"), "sensitive header %d leaked" % index)
		assert_true(redacted[index].ends_with(": [REDACTED]"))
	assert_eq(redacted[6], "Accept: */*")


func test_generation_post_never_retries_timeout_network_429_or_5xx() -> void:
	var cases := [
		{"name": "timeout", "path": "/post-timeout", "timeout": 0.02},
		{"name": "network", "path": "/network-drop", "timeout": 0.1},
		{"name": "429", "path": "/post-rate-limit", "timeout": 1.0},
		{"name": "5xx", "path": "/post-server-error", "timeout": 1.0},
	]
	for case in cases:
		var client := HttpClientScript.new()
		add_child_autofree(client)
		var attempts := []
		client.request_attempted.connect(
			func(_task_id: String, attempt: int, _timestamp_msec: int) -> void:
				attempts.append(attempt)
		)
		var outcome := await _run_request_on(
			client,
			HTTPClient.METHOD_POST,
			_base_url + String(case["path"]),
			{"retries": 3, "backoff": 0.0, "timeout": case["timeout"]},
			2.0
		)
		assert_eq(outcome["status"], "failed", String(case["name"]))
		assert_eq(attempts.size(), 1, "%s generation POST must have one attempt" % case["name"])
		var count_outcome := await _run_request(
			"/request-count?path=" + String(case["path"]),
			{"transform": _safe_request_count},
			2.0,
			HTTPClient.METHOD_GET
		)
		assert_eq(
			count_outcome["value"]["count"],
			1,
			"%s mock transport must receive exactly one POST" % case["name"]
		)


func test_credential_sentinel_reaches_transport_but_not_log_task_error_or_project() -> void:
	ProjectService.new_project("B7-1 sentinel persistence")
	var logger := get_tree().root.get_node("Logger")
	var log_path: String = logger.get_current_log_path()
	var log_offset := FileAccess.get_file_as_bytes(log_path).size()
	var task: Variant = _client.request_json(
		HTTPClient.METHOD_POST,
		_base_url + "/credential-sentinel?credential=" + CREDENTIAL_SENTINEL,
		PackedStringArray(
			[
				"Content-Type: application/json",
				"X-RD-Token: " + CREDENTIAL_SENTINEL,
			]
		),
		{"prompt": CREDENTIAL_SENTINEL},
		{"log_requests": true, "retries": 3}
	)
	var outcome := await _submit_and_wait(task)
	var success_task: Variant = _client.request_json(
		HTTPClient.METHOD_POST,
		_base_url + "/credential-sentinel-success",
		PackedStringArray(["X-RD-Token: " + CREDENTIAL_SENTINEL]),
		{"prompt": CREDENTIAL_SENTINEL},
		{"log_requests": true}
	)
	var success_outcome := await _submit_and_wait(success_task)
	var transport_status := await _run_request(
		"/credential-sentinel-status",
		{"transform": _safe_transport_status},
		2.0,
		HTTPClient.METHOD_GET
	)

	assert_true(transport_status["value"]["received"])
	assert_false(SentinelScanner.contains(task.payload, CREDENTIAL_SENTINEL))
	assert_false(SentinelScanner.contains(outcome, CREDENTIAL_SENTINEL))
	assert_false(SentinelScanner.contains(success_task.payload, CREDENTIAL_SENTINEL))
	assert_false(SentinelScanner.contains(success_outcome, CREDENTIAL_SENTINEL))
	assert_false(
		SentinelScanner.contains(
			{
				"manifest": ProjectService.current_project.manifest,
				"canvas": ProjectService.current_project.canvas,
				"graphs": ProjectService.current_project.graphs,
				"boards": ProjectService.current_project.boards,
				"animations": ProjectService.current_project.animations,
				"asset_metadata": AssetLibrary._metadata,
			},
			CREDENTIAL_SENTINEL
		),
		"current project/persistence surface leaked the credential sentinel"
	)
	assert_false(SentinelScanner.file_contains(log_path, CREDENTIAL_SENTINEL, log_offset))
	assert_eq(ProjectService.save_project(SENTINEL_PROJECT_PATH), OK)
	var unpacked: Dictionary = FileIOScript.zip_unpack(SENTINEL_PROJECT_PATH)
	assert_true(unpacked.get("ok", false))
	assert_false(
		SentinelScanner.contains(unpacked.get("files", {}), CREDENTIAL_SENTINEL),
		"serialized project archive leaked the credential sentinel"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SENTINEL_PROJECT_PATH))


func _safe_transport_status(response: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"received": bool(response.get("body", {}).get("received", false)),
	}


func _safe_request_count(response: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"count": int(response.get("body", {}).get("count", -1)),
	}


func _run_request(
	path: String,
	opts: Dictionary = {},
	timeout_seconds: float = 2.0,
	method: int = HTTPClient.METHOD_POST
) -> Dictionary:
	return await _run_request_on(_client, method, _base_url + path, opts, timeout_seconds)


func _run_request_on(
	client: Node,
	method: int,
	url: String,
	opts: Dictionary = {},
	timeout_seconds: float = 2.0
) -> Dictionary:
	var task: Variant = client.request_json(
		method,
		url,
		PackedStringArray(["Content-Type: application/json"]),
		{"fixture": true},
		opts
	)
	return await _submit_and_wait(task, timeout_seconds)


func _submit_and_wait(task: Variant, timeout_seconds: float = 2.0) -> Dictionary:
	var outcome := _watch_task(task)
	_queue.submit(task)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending", timeout_seconds))
	return outcome


func _watch_task(task: Variant) -> Dictionary:
	var outcome := {"status": "pending", "value": null}
	task.finished.connect(
		func(result: Variant) -> void:
			outcome["status"] = "finished"
			outcome["value"] = result
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = error
	)
	return outcome


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
