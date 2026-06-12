class_name PFLogger
extends Node

## 分级日志 autoload。
## 职责：统一写控制台和 user://logs/app_YYYY-MM-DD.log，并滚动保留最近 7 天。

enum Level { DEBUG, INFO, WARN, ERROR }

const LOG_DIR := "user://logs"
const LOG_RETENTION_DAYS := 7
const IdUtil := preload("res://core/util/id_util.gd")

var _log_path := ""
var _minimum_level := Level.DEBUG


func _ready() -> void:
	_prepare_log_file()
	info("Logger ready")


func set_minimum_level(level: int) -> void:
	_minimum_level = clampi(level, Level.DEBUG, Level.ERROR)


func debug(message: String, detail: Variant = null) -> void:
	_write(Level.DEBUG, message, detail)


func info(message: String, detail: Variant = null) -> void:
	_write(Level.INFO, message, detail)


func warn(message: String, detail: Variant = null) -> void:
	_write(Level.WARN, message, detail)


func error(message: String, detail: Variant = null) -> void:
	_write(Level.ERROR, message, detail)


func get_current_log_path() -> String:
	if _log_path.is_empty():
		_prepare_log_file()
	return _log_path


func cleanup_old_logs(now_unix: float = -1.0) -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return

	var current_time := now_unix
	if current_time < 0.0:
		current_time = Time.get_unix_time_from_system()

	var cutoff := current_time - float(LOG_RETENTION_DAYS * 24 * 60 * 60)
	for file_name in dir.get_files():
		if not file_name.begins_with("app_") or not file_name.ends_with(".log"):
			continue

		var file_path := "%s/%s" % [LOG_DIR, file_name]
		if _log_file_time(file_name, file_path) < cutoff:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


func _prepare_log_file() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	_log_path = "%s/app_%s.log" % [LOG_DIR, _date_stamp()]
	cleanup_old_logs()


func _write(level: int, message: String, detail: Variant) -> void:
	if level < _minimum_level:
		return

	if _log_path.is_empty():
		_prepare_log_file()

	var level_name := _level_to_name(level)
	var line := "[%s] [%s] %s" % [_timestamp(), level_name, message]
	if detail != null:
		line += " | " + var_to_str(detail)

	# Logger 是唯一允许直接写控制台的位置；其他模块都通过本服务记录。
	print(line)

	var file := _open_log_for_append()
	if file != null:
		file.store_line(line)


func _open_log_for_append() -> FileAccess:
	if FileAccess.file_exists(_log_path):
		var existing := FileAccess.open(_log_path, FileAccess.READ_WRITE)
		if existing != null:
			existing.seek_end()
		return existing
	return FileAccess.open(_log_path, FileAccess.WRITE)


func _log_file_time(file_name: String, file_path: String) -> float:
	var date_text := file_name.substr(4, file_name.length() - 8)
	var parts := date_text.split("-")
	if parts.size() == 3:
		return (
			Time
			. get_unix_time_from_datetime_dict(
				{
					"year": int(parts[0]),
					"month": int(parts[1]),
					"day": int(parts[2]),
					"hour": 0,
					"minute": 0,
					"second": 0,
				}
			)
		)

	return float(FileAccess.get_modified_time(file_path))


func _level_to_name(level: int) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN"


func _date_stamp() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


func _timestamp() -> String:
	return IdUtil.utc_now_iso()
