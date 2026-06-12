class_name PFLogUtil
extends RefCounted

## 日志转发工具。
## 用途：避免 autoload 解析顺序导致 `Logger.warn()` 被当作静态类调用。


static func debug(message: String, detail: Variant = null) -> void:
	_call_logger("debug", message, detail)


static func info(message: String, detail: Variant = null) -> void:
	_call_logger("info", message, detail)


static func warn(message: String, detail: Variant = null) -> void:
	_call_logger("warn", message, detail)


static func error(message: String, detail: Variant = null) -> void:
	_call_logger("error", message, detail)


static func _call_logger(method: String, message: String, detail: Variant) -> void:
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var tree := main_loop as SceneTree
		var logger := tree.root.get_node_or_null("Logger")
		if logger != null:
			logger.call(method, message, detail)
			return

	var text := message
	if detail != null:
		text += " | " + var_to_str(detail)

	if method == "error":
		push_error(text)
	elif method == "warn":
		push_warning(text)
