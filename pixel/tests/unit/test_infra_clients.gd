extends "res://addons/gut/test.gd"

const HttpClientScript := preload("res://infra/http_client.gd")
const WsClientScript := preload("res://infra/ws_client.gd")


func test_http_client_builds_external_task_without_leaking_request_headers() -> void:
	var client := HttpClientScript.new()
	var task: Variant = client.request_json(
		HTTPClient.METHOD_POST,
		"https://example.test/api",
		PackedStringArray(["Content-Type: application/json"]),
		{"hello": "world"},
		{"timeout": 5.0, "retries": 2}
	)

	assert_true(task.is_external_async())
	assert_eq(task.payload["url"], "https://example.test/api")
	assert_eq(task.payload["method"], HTTPClient.METHOD_POST)
	assert_eq(task.payload["timeout_seconds"], 5.0)
	assert_eq(task.payload["retries"], 2)
	assert_false(task.payload.has("headers"))
	assert_false(task.payload.has("body"))
	client.free()


func test_websocket_client_stub_keeps_m7_connection_shape() -> void:
	var client := WsClientScript.new()

	assert_false(client.is_socket_connected())
	assert_eq(client.connect_to_endpoint("ws://example.test/socket"), ERR_UNAVAILABLE)
	assert_eq(client.send_text("hello"), ERR_UNAVAILABLE)
	assert_eq(client.send_json({"hello": "world"}), ERR_UNAVAILABLE)
