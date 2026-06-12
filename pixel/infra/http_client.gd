class_name PFHttpClient
extends RefCounted

## HTTP 客户端接口占位。
## M4 会实现重试、超时和 Provider 鉴权；M0 先固定调用形状，避免后续移动 infra 目录。
## 设计意图：上层只依赖 request_raw/request_json 的结果字典，不直接绑定 Godot HTTPRequest 节点。
## M4 实现时保持返回字段 ok/status_code/headers/body/error，调用方就不需要改签名。

signal request_started(url: String, method: int)
signal request_completed(result: Dictionary)


func request_raw(
	url: String,
	method: int = HTTPClient.METHOD_GET,
	headers: PackedStringArray = PackedStringArray(),
	body: PackedByteArray = PackedByteArray(),
	timeout_seconds: float = 30.0
) -> Dictionary:
	request_started.emit(url, method)
	var result := _unavailable_result(url, method, headers, body, timeout_seconds)
	request_completed.emit(result)
	return result


func request_json(
	url: String,
	method: int = HTTPClient.METHOD_GET,
	headers: PackedStringArray = PackedStringArray(),
	body: Variant = null,
	timeout_seconds: float = 30.0
) -> Dictionary:
	var body_bytes := PackedByteArray()
	if body != null:
		body_bytes = JSON.stringify(body).to_utf8_buffer()
	return request_raw(url, method, headers, body_bytes, timeout_seconds)


func cancel_all() -> void:
	return


func _unavailable_result(
	url: String,
	method: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	timeout_seconds: float
) -> Dictionary:
	return {
		"ok": false,
		"status_code": 0,
		"headers": PackedStringArray(),
		"body": PackedByteArray(),
		"error": "HTTP client is reserved for M4.",
		"url": url,
		"method": method,
		"request_headers": headers,
		"request_body": body,
		"timeout_seconds": timeout_seconds,
	}
