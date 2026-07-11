class_name PFSettingsService
extends Node

## 用户设置服务。
## 使用 ConfigFile 包装 user://settings.cfg，并通过 setting_changed 信号通知 UI 刷新。

signal setting_changed(section: String, key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"
const Log := preload("res://core/util/log_util.gd")

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> Error:
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		Log.warn("Failed to load settings", {"error": error})
		return error

	_ensure_defaults()
	return OK


func save_settings() -> Error:
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		Log.warn("Failed to save settings", {"error": error})
	return error


func get_setting(section: String, key: String, default_value: Variant = null) -> Variant:
	return _config.get_value(section, key, default_value)


func set_setting(section: String, key: String, value: Variant, save_now: bool = true) -> void:
	var old_value: Variant = (
		_config.get_value(section, key) if _config.has_section_key(section, key) else null
	)
	_config.set_value(section, key, value)
	if old_value != value:
		setting_changed.emit(section, key, value)

	if save_now:
		save_settings()


func get_recent_projects() -> Array:
	return _config.get_value("project", "recent_projects", [])


func add_recent_project(path: String) -> void:
	if path.is_empty():
		return

	var recent := get_recent_projects()
	recent.erase(path)
	recent.push_front(path)
	while recent.size() > 10:
		recent.pop_back()
	set_setting("project", "recent_projects", recent)


func _ensure_defaults() -> void:
	var changed := false
	changed = _set_default("ui", "language", "en") or changed
	changed = _set_default("ui", "interface_scale", 0.0) or changed
	changed = _set_default("ui", "live_rescale", true) or changed
	changed = _set_default("project", "recent_projects", []) or changed
	changed = _set_default("tasks", "max_concurrency", 2) or changed
	if changed:
		save_settings()


func _set_default(section: String, key: String, value: Variant) -> bool:
	if _config.has_section_key(section, key):
		return false
	_config.set_value(section, key, value)
	return true
