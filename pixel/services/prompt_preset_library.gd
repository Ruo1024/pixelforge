class_name PFPromptPresetLibrary
extends RefCounted

## Persistent user PromptPreset library layered over immutable built-in and plugin presets.

const PromptPresetRegistry := preload("res://services/prompt_preset_registry.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const IdUtil := preload("res://core/util/id_util.gd")

const SETTINGS_SECTION := "prompt_presets"
const SETTINGS_KEY := "user_presets"


static func list_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var known_ids := {}
	var registry := PromptPresetRegistry.new()
	for preset_id in registry.get_preset_ids():
		var preset := registry.get_preset(String(preset_id))
		result.append(_entry(preset, "builtin", true))
		known_ids[String(preset_id)] = true
	for preset_id in PluginService.list_capabilities("prompt_preset"):
		var plugin_value: Variant = PluginService.get_capability("prompt_preset", String(preset_id))
		if not (plugin_value is Dictionary) or known_ids.has(String(preset_id)):
			continue
		result.append(_entry(plugin_value, "plugin", true))
		known_ids[String(preset_id)] = true
	for preset in user_presets():
		var preset_id := String(preset.get("id", ""))
		if known_ids.has(preset_id):
			continue
		result.append(_entry(preset, "user", false))
		known_ids[preset_id] = true
	return result


static func user_presets() -> Array[Dictionary]:
	var stored: Variant = SettingsService.get_setting(SETTINGS_SECTION, SETTINGS_KEY, [])
	var result: Array[Dictionary] = []
	if not (stored is Array):
		return result
	for preset_value in stored:
		if not (preset_value is Dictionary):
			continue
		var preset: Dictionary = preset_value
		if not preset.has("name") or preset.has("name_key"):
			continue
		if bool(PromptPresetRegistry.validate_preset(preset).get("ok", false)):
			result.append(preset.duplicate(true))
	return result


static func create_user_preset(name: String, prefix: String) -> Dictionary:
	var preset := {
		"prompt_preset_version": 1,
		"id": "user-prompt-%s" % IdUtil.uuid_v4(),
		"name": name.strip_edges(),
		"prefix": prefix,
	}
	var validation := PromptPresetRegistry.validate_preset(preset)
	if not bool(validation.get("ok", false)):
		return validation
	var presets := user_presets()
	presets.append(preset)
	_persist(presets)
	return {"ok": true, "preset": preset.duplicate(true)}


static func duplicate_as_user(source: Dictionary, name: String) -> Dictionary:
	return create_user_preset(name, String(source.get("prefix", "")))


static func save_user_preset(preset: Dictionary) -> Dictionary:
	var validation := PromptPresetRegistry.validate_preset(preset)
	if not bool(validation.get("ok", false)) or not preset.has("name") or preset.has("name_key"):
		return validation if not bool(validation.get("ok", false)) else {"ok": false}
	var presets := user_presets()
	var preset_id := String(preset.get("id", ""))
	for index in range(presets.size()):
		if String(presets[index].get("id", "")) != preset_id:
			continue
		presets[index] = preset.duplicate(true)
		_persist(presets)
		return {"ok": true, "preset": preset.duplicate(true)}
	return {"ok": false, "code": "prompt_preset_not_user"}


static func delete_user_preset(preset_id: String) -> bool:
	var presets := user_presets()
	for index in range(presets.size()):
		if String(presets[index].get("id", "")) != preset_id:
			continue
		presets.remove_at(index)
		_persist(presets)
		return true
	return false


static func display_name(preset: Dictionary) -> String:
	if preset.has("name"):
		return String(preset.get("name", ""))
	var name_key := String(preset.get("name_key", ""))
	if name_key.is_empty():
		return String(preset.get("id", ""))
	var resolved := SchemaTextResolverScript.resolve({"label_key": name_key}, "label_key")
	return resolved if not resolved.is_empty() else String(preset.get("id", ""))


static func _entry(preset: Dictionary, source: String, read_only: bool) -> Dictionary:
	return {
		"id": String(preset.get("id", "")),
		"name": display_name(preset),
		"source": source,
		"read_only": read_only,
		"preset": preset.duplicate(true),
	}


static func _persist(presets: Array[Dictionary]) -> void:
	SettingsService.set_setting(
		SETTINGS_SECTION,
		SETTINGS_KEY,
		presets.map(func(value: Dictionary) -> Dictionary: return value.duplicate(true))
	)
