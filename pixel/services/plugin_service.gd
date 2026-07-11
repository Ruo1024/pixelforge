class_name PFPluginService
extends Node

## Runtime GDScript/PCK plugin loader with manifest validation, isolation, and reversible APIs.

signal plugins_changed
signal plugin_status_changed(plugin_id: String, state: String, reason: String)

const PluginAPIScript := preload("res://services/plugin_api.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")

const API_VERSION := 1
const REQUIRED_FIELDS := ["id", "name", "version", "api_version", "min_app_version", "entry"]
const BUILTIN_MANIFESTS := [
	"res://plugins/provider_openai/plugin.json",
	"res://plugins/provider_retrodiffusion/plugin.json",
	"res://plugins/bridge_comfyui/plugin.json",
]

var plugin_root := "user://plugins"
var scan_on_ready := true
var _records := {}
var _capabilities := {}


func _ready() -> void:
	_register_builtin_records()
	if scan_on_ready:
		scan_plugins()


func _exit_tree() -> void:
	for plugin_id in _records.keys():
		if not bool(Dictionary(_records[plugin_id]).get("builtin", false)):
			unload_plugin(String(plugin_id))


func scan_plugins() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(plugin_root))
	var directory := DirAccess.open(plugin_root)
	if directory == null:
		return
	for entry in directory.get_directories():
		load_directory_plugin(plugin_root.path_join(entry))
	for file_name in directory.get_files():
		if file_name.to_lower().ends_with(".pck"):
			load_pck_plugin(plugin_root.path_join(file_name))
	plugins_changed.emit()


func load_directory_plugin(directory_path: String) -> Dictionary:
	var manifest_path := directory_path.path_join("plugin.json")
	var parsed := _read_manifest(manifest_path)
	if not bool(parsed.get("ok", false)):
		return _record_failure(
			directory_path.get_file(), parsed.get("reason", "Invalid manifest"), directory_path
		)
	var manifest: Dictionary = parsed["manifest"]
	var plugin_id := String(manifest["id"])
	if not is_plugin_enabled(plugin_id):
		return _record(manifest, "disabled", "Disabled by user", directory_path, false)
	var packed := _mount_directory_plugin(directory_path, plugin_id)
	if not bool(packed.get("ok", false)):
		return _record(
			manifest, "failed", String(packed.get("reason", "Pack failed")), directory_path, false
		)
	return _activate(
		manifest,
		"res://plugins/%s/%s" % [plugin_id, String(manifest["entry"])],
		directory_path,
		false
	)


func load_pck_plugin(pck_path: String) -> Dictionary:
	var expected_id := pck_path.get_file().get_basename()
	if expected_id.is_empty() or not ProjectSettings.load_resource_pack(pck_path, false):
		return _record_failure(expected_id, "Resource pack could not be loaded", pck_path)
	var root := "res://plugins/%s" % expected_id
	var parsed := _read_manifest(root.path_join("plugin.json"))
	if not bool(parsed.get("ok", false)):
		return _record_failure(expected_id, parsed.get("reason", "Invalid PCK manifest"), pck_path)
	var manifest: Dictionary = parsed["manifest"]
	if String(manifest["id"]) != expected_id:
		return _record_failure(expected_id, "PCK file name must match manifest id", pck_path)
	if not is_plugin_enabled(expected_id):
		return _record(manifest, "disabled", "Disabled by user", pck_path, false)
	return _activate(manifest, root.path_join(String(manifest["entry"])), pck_path, false)


func unload_plugin(plugin_id: String) -> bool:
	if not _records.has(plugin_id):
		return false
	var record: Dictionary = _records[plugin_id]
	if bool(record.get("builtin", false)):
		return false
	var plugin: Variant = record.get("instance")
	if plugin != null and plugin.has_method("_exit_app"):
		plugin._exit_app()
	var api: Variant = record.get("api")
	if api != null:
		api.revoke_all()
	record["instance"] = null
	record["api"] = null
	record["state"] = "disabled"
	record["reason"] = "Unloaded"
	_records[plugin_id] = record
	plugin_status_changed.emit(plugin_id, "disabled", "Unloaded")
	plugins_changed.emit()
	return true


func reload_plugin(plugin_id: String) -> Dictionary:
	if not _records.has(plugin_id):
		return {"ok": false, "reason": "Plugin is unknown"}
	var record: Dictionary = _records[plugin_id]
	var source := String(record.get("source", ""))
	unload_plugin(plugin_id)
	return load_pck_plugin(source) if source.ends_with(".pck") else load_directory_plugin(source)


func set_plugin_enabled(plugin_id: String, enabled: bool) -> bool:
	SettingsService.set_setting("plugins", "enabled_%s" % plugin_id, enabled)
	if not enabled:
		return unload_plugin(plugin_id)
	if _records.has(plugin_id):
		return bool(reload_plugin(plugin_id).get("ok", false))
	return false


func is_plugin_enabled(plugin_id: String) -> bool:
	return bool(SettingsService.get_setting("plugins", "enabled_%s" % plugin_id, true))


func install_pck(source_path: String) -> Dictionary:
	if not source_path.to_lower().ends_with(".pck") or not FileAccess.file_exists(source_path):
		return {"ok": false, "reason": "Choose a .pck plugin package"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(plugin_root))
	var destination := plugin_root.path_join(source_path.get_file())
	var error := DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(destination)
	)
	return (
		{"ok": false, "reason": error_string(error)}
		if error != OK
		else load_pck_plugin(destination)
	)


func uninstall_plugin(plugin_id: String) -> Error:
	if not _records.has(plugin_id) or bool(Dictionary(_records[plugin_id]).get("builtin", false)):
		return ERR_UNAUTHORIZED
	var source := String(Dictionary(_records[plugin_id]).get("source", ""))
	unload_plugin(plugin_id)
	_records.erase(plugin_id)
	var absolute := ProjectSettings.globalize_path(source)
	if source.ends_with(".pck"):
		return DirAccess.remove_absolute(absolute)
	return _remove_directory_recursive(absolute)


func get_plugin_records() -> Array:
	var result := []
	var ids: Array = _records.keys()
	ids.sort()
	for plugin_id in ids:
		var record: Dictionary = _records[plugin_id].duplicate(true)
		record.erase("instance")
		record.erase("api")
		result.append(record)
	return result


func get_plugin_root_absolute() -> String:
	return ProjectSettings.globalize_path(plugin_root)


func register_capability(
	kind: String, capability_id: String, value: Variant, plugin_id: String
) -> bool:
	if not _capabilities.has(kind):
		_capabilities[kind] = {}
	if Dictionary(_capabilities[kind]).has(capability_id):
		return false
	_capabilities[kind][capability_id] = {"plugin_id": plugin_id, "value": value}
	return true


func unregister_capability(kind: String, capability_id: String, plugin_id: String) -> bool:
	if not _capabilities.has(kind) or not Dictionary(_capabilities[kind]).has(capability_id):
		return false
	if String(_capabilities[kind][capability_id].get("plugin_id", "")) != plugin_id:
		return false
	return _capabilities[kind].erase(capability_id)


func get_capability(kind: String, capability_id: String) -> Variant:
	return _capabilities.get(kind, {}).get(capability_id, {}).get("value", null)


func list_capabilities(kind: String) -> Array:
	var ids: Array = Dictionary(_capabilities.get(kind, {})).keys()
	ids.sort()
	return ids


func validate_manifest(manifest: Dictionary) -> Dictionary:
	for field in REQUIRED_FIELDS:
		if not manifest.has(field):
			return {"ok": false, "reason": "Manifest is missing required field: %s" % field}
	var plugin_id := String(manifest["id"])
	if plugin_id.is_empty() or plugin_id != plugin_id.to_snake_case():
		return {"ok": false, "reason": "Plugin id must be non-empty snake_case"}
	if int(manifest["api_version"]) != API_VERSION:
		return {"ok": false, "reason": "Plugin API version is incompatible"}
	if _compare_versions(AppInfo.APP_VERSION, String(manifest["min_app_version"])) < 0:
		return {"ok": false, "reason": "Plugin requires a newer PixelForge version"}
	if String(manifest["entry"]).get_extension() != "gd":
		return {"ok": false, "reason": "Plugin entry must be a GDScript file"}
	return {"ok": true}


func _activate(
	manifest: Dictionary, entry_path: String, source: String, builtin: bool
) -> Dictionary:
	var validation := validate_manifest(manifest)
	if not bool(validation.get("ok", false)):
		return _record(manifest, "failed", String(validation["reason"]), source, builtin)
	var plugin_id := String(manifest["id"])
	if _records.has(plugin_id) and String(_records[plugin_id].get("state", "")) == "loaded":
		return {"ok": false, "reason": "Plugin id is already loaded", "id": plugin_id}
	var script: Script = load(entry_path)
	if script == null or not script.can_instantiate():
		return _record(manifest, "failed", "Entry script could not be loaded", source, builtin)
	var instance: Variant = script.new()
	if (
		instance == null
		or not instance.has_method("_enter_app")
		or not instance.has_method("_exit_app")
	):
		return _record(
			manifest, "failed", "Entry must implement PFPlugin lifecycle", source, builtin
		)
	var api := PluginAPIScript.new(self, ProviderService, plugin_id)
	instance._enter_app(api)
	var record := _record(manifest, "loaded", "", source, builtin)
	record["instance"] = instance
	record["api"] = api
	_records[plugin_id] = record
	plugin_status_changed.emit(plugin_id, "loaded", "")
	return {"ok": true, "id": plugin_id, "record": record}


func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "plugin.json is missing"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "plugin.json is invalid JSON"}
	var validation := validate_manifest(parsed)
	return (
		{"ok": false, "reason": validation["reason"]}
		if not validation["ok"]
		else {"ok": true, "manifest": parsed}
	)


func _record(
	manifest: Dictionary, state: String, reason: String, source: String, builtin: bool
) -> Dictionary:
	var plugin_id := String(manifest.get("id", source.get_file().get_basename()))
	var record := {
		"id": plugin_id,
		"name": String(manifest.get("name", plugin_id)),
		"version": String(manifest.get("version", "")),
		"permissions": Array(manifest.get("permissions", [])),
		"description": String(manifest.get("description", "")),
		"source": source,
		"builtin": builtin,
		"state": state,
		"reason": reason,
		"manifest": manifest.duplicate(true),
	}
	_records[plugin_id] = record
	if state == "failed":
		Log.warn("Plugin load isolated", {"plugin_id": plugin_id, "reason": reason})
	plugin_status_changed.emit(plugin_id, state, reason)
	return {"ok": state == "loaded", "id": plugin_id, "reason": reason, "record": record}


func _record_failure(plugin_id: String, reason: String, source: String) -> Dictionary:
	return _record({"id": plugin_id, "name": plugin_id}, "failed", reason, source, false)


func _register_builtin_records() -> void:
	for path in BUILTIN_MANIFESTS:
		var parsed := _read_manifest(path)
		if bool(parsed.get("ok", false)):
			_record(parsed["manifest"], "loaded", "", path.get_base_dir(), true)


func _compare_versions(left: String, right: String) -> int:
	var left_numbers := _version_numbers(left)
	var right_numbers := _version_numbers(right)
	for index in range(3):
		if left_numbers[index] != right_numbers[index]:
			return 1 if left_numbers[index] > right_numbers[index] else -1
	return 0


func _version_numbers(version: String) -> Array[int]:
	var result: Array[int] = [0, 0, 0]
	var parts := version.split("-")[0].split(".")
	for index in range(mini(3, parts.size())):
		result[index] = int(parts[index])
	return result


func _remove_directory_recursive(absolute_path: String) -> Error:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return ERR_DOES_NOT_EXIST
	for file_name in directory.get_files():
		var error := DirAccess.remove_absolute(absolute_path.path_join(file_name))
		if error != OK:
			return error
	for child in directory.get_directories():
		var error := _remove_directory_recursive(absolute_path.path_join(child))
		if error != OK:
			return error
	return DirAccess.remove_absolute(absolute_path)


func _mount_directory_plugin(directory_path: String, plugin_id: String) -> Dictionary:
	var cache_root := "user://plugin_cache"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_root))
	var cache_path := cache_root.path_join("%s.pck" % plugin_id)
	var packer := PCKPacker.new()
	var error := packer.pck_start(cache_path)
	if error == OK:
		error = _pack_directory_recursive(
			packer,
			ProjectSettings.globalize_path(directory_path),
			ProjectSettings.globalize_path(directory_path),
			"res://plugins/%s" % plugin_id
		)
	if error == OK:
		error = packer.flush()
	if error != OK:
		return {"ok": false, "reason": "Directory plugin pack failed: %s" % error_string(error)}
	if not ProjectSettings.load_resource_pack(cache_path, true):
		return {"ok": false, "reason": "Directory plugin cache could not be mounted"}
	return {"ok": true, "cache_path": cache_path}


func _pack_directory_recursive(
	packer: PCKPacker, root: String, current: String, virtual_root: String
) -> Error:
	var directory := DirAccess.open(current)
	if directory == null:
		return ERR_CANT_OPEN
	var relative := current.trim_prefix(root).trim_prefix("/")
	for file_name in directory.get_files():
		var error := packer.add_file(
			virtual_root.path_join(relative).path_join(file_name), current.path_join(file_name)
		)
		if error != OK:
			return error
	for child in directory.get_directories():
		var error := _pack_directory_recursive(packer, root, current.path_join(child), virtual_root)
		if error != OK:
			return error
	return OK
