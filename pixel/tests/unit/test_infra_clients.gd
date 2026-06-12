extends "res://addons/gut/test.gd"

const HttpClientScript := preload("res://infra/http_client.gd")
const WsClientScript := preload("res://infra/ws_client.gd")


func test_http_client_stub_keeps_m4_result_shape() -> void:
	var client := HttpClientScript.new()
	var result: Dictionary = client.request_json(
		"https://example.test/api",
		HTTPClient.METHOD_POST,
		PackedStringArray(["Content-Type: application/json"]),
		{"hello": "world"},
		5.0
	)

	assert_false(result["ok"])
	assert_eq(result["status_code"], 0)
	assert_true(result.has("headers"))
	assert_true(result.has("body"))
	assert_eq(result["url"], "https://example.test/api")
	assert_eq(result["method"], HTTPClient.METHOD_POST)
	assert_eq(result["timeout_seconds"], 5.0)


func test_websocket_client_stub_keeps_m7_connection_shape() -> void:
	var client := WsClientScript.new()

	assert_false(client.is_socket_connected())
	assert_eq(client.connect_to_endpoint("ws://example.test/socket"), ERR_UNAVAILABLE)
	assert_eq(client.send_text("hello"), ERR_UNAVAILABLE)
	assert_eq(client.send_json({"hello": "world"}), ERR_UNAVAILABLE)
