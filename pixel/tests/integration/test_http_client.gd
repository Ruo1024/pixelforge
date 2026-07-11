extends "res://addons/gut/test.gd"

const HttpClientScript := preload("res://infra/http_client.gd")

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
	assert_eq(outcome["value"]["body"], {"ok": true})


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


func test_429_retries_three_times_with_exponential_backoff() -> void:
	var timestamps := []
	_client.request_attempted.connect(
		func(_task_id: String, _attempt: int, timestamp_msec: int) -> void:
			timestamps.append(timestamp_msec)
	)
	var outcome := await _run_request(
		"/retry-three", {"retries": 3, "backoff": 0.04, "timeout": 1.0}, 3.0
	)

	assert_eq(outcome["status"], "finished")
	assert_eq(outcome["value"]["attempts"], 4)
	assert_eq(timestamps.size(), 4)
	assert_gte(timestamps[1] - timestamps[0], 30)
	assert_gte(timestamps[2] - timestamps[1], 65)
	assert_gte(timestamps[3] - timestamps[2], 130)


func test_sensitive_headers_are_redacted_for_request_logs() -> void:
	var redacted: PackedStringArray = _client.call(
		"_redacted_headers",
		PackedStringArray(["Authorization: Bearer secret", "X-Api-Key: secret", "Accept: */*"])
	)

	assert_eq(redacted[0], "Authorization: [REDACTED]")
	assert_eq(redacted[1], "X-Api-Key: [REDACTED]")
	assert_eq(redacted[2], "Accept: */*")


func _run_request(path: String, opts: Dictionary = {}, timeout_seconds: float = 2.0) -> Dictionary:
	var outcome := {"status": "pending", "value": null}
	var task: Variant = _client.request_json(
		HTTPClient.METHOD_POST,
		_base_url + path,
		PackedStringArray(["Content-Type: application/json"]),
		{"fixture": true},
		opts
	)
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
	_queue.submit(task)
	var elapsed := 0.0
	while outcome["status"] == "pending" and elapsed < timeout_seconds:
		await wait_seconds(0.02)
		elapsed += 0.02
	assert_ne(outcome["status"], "pending", "HTTP task did not reach a terminal state")
	return outcome
