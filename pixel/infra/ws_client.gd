class_name PFWsClient
extends RefCounted

## WebSocket 客户端接口占位。
## M7 ComfyUI 桥接会在这里补连接、心跳和消息分发。
## 设计意图：先固定连接、发送、轮询和关闭签名；M7 只替换内部实现，不改变调用方。

signal connected(url: String)
signal connection_failed(error: Dictionary)
signal message_received(message: Variant)
signal closed(code: int, reason: String)

const Log := preload("res://core/util/log_util.gd")


func connect_to_endpoint(url: String) -> Error:
	Log.debug("WebSocket client is reserved for M7", {"url": url})
	connection_failed.emit({"error": ERR_UNAVAILABLE, "url": url})
	return ERR_UNAVAILABLE


func is_socket_connected() -> bool:
	return false


func send_text(message: String) -> Error:
	Log.debug("WebSocket send_text ignored before M7", {"bytes": message.length()})
	return ERR_UNAVAILABLE


func send_json(message: Variant) -> Error:
	return send_text(JSON.stringify(message))


func poll() -> void:
	return


func close() -> void:
	closed.emit(0, "not connected")
