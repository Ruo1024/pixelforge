class_name PFPromptPresetRegistry
extends RefCounted

## Owns strict PromptPreset v1 validation and immutable registry snapshots.

const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const BUILTIN_PATHS := [
	"res://assets/prompt_presets/prompt-hibit.json",
	"res://assets/prompt_presets/prompt-gb.json",
	"res://assets/prompt_presets/prompt-hd2d-prop.json",
	"res://assets/prompt_presets/prompt-1bit.json",
	"res://assets/prompt_presets/prompt-nes.json",
	"res://assets/prompt_presets/prompt-16bit-db32.json",
]
const REQUIRED_FIELDS := ["prompt_preset_version", "id", "prefix"]
const ALLOWED_FIELDS := ["prompt_preset_version", "id", "name", "name_key", "prefix"]

var _presets := {}


func _init() -> void:
	for path in BUILTIN_PATHS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			if parsed.get("prompt_preset_version") is float:
				parsed["prompt_preset_version"] = int(parsed["prompt_preset_version"])
			register_preset(parsed)


static func validate_preset(preset: Dictionary) -> Dictionary:
	var schema_validation := SchemaTextResolverScript.validate_schema([preset])
	if not bool(schema_validation.get("ok", false)):
		return schema_validation
	for field in REQUIRED_FIELDS:
		if not preset.has(field):
			return _failure("invalid_prompt_preset", {"field": field})
	for field_value in preset.keys():
		if String(field_value) not in ALLOWED_FIELDS:
			return _failure("invalid_prompt_preset", {"field": String(field_value)})
	if not (preset["prompt_preset_version"] is int) or preset["prompt_preset_version"] != 1:
		return _failure("unsupported_prompt_preset_version")
	if not (preset["id"] is String) or String(preset["id"]).is_empty():
		return _failure("invalid_prompt_preset", {"field": "id"})
	if not (preset["prefix"] is String):
		return _failure("invalid_prompt_preset", {"field": "prefix"})
	if preset.has("name") == preset.has("name_key"):
		return _failure("invalid_prompt_preset", {"field": "name"})
	if preset.has("name") and (
		not (preset["name"] is String) or String(preset["name"]).is_empty()
	):
		return _failure("invalid_prompt_preset", {"field": "name"})
	if preset.has("name_key") and not (preset["name_key"] is String):
		return _failure("invalid_prompt_preset", {"field": "name_key"})
	return {"ok": true}


func register_preset(preset: Dictionary) -> bool:
	var validation := validate_preset(preset)
	if not bool(validation.get("ok", false)):
		return false
	var preset_id := String(preset["id"])
	if _presets.has(preset_id):
		return false
	_presets[preset_id] = preset.duplicate(true)
	return true


func unregister_preset(preset_id: String) -> bool:
	return _presets.erase(preset_id)


func get_preset(preset_id: String) -> Dictionary:
	return Dictionary(_presets.get(preset_id, {})).duplicate(true)


func get_preset_ids() -> Array:
	var result: Array = _presets.keys()
	result.sort()
	return result


static func _failure(code: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "args": args.duplicate(true)}
