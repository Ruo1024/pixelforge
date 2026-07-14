class_name PFCleanupPresetRegistry
extends RefCounted

## Owns strict CleanupPreset v1 validation and immutable settings snapshots.

const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const BUILTIN_PATHS := [
	"res://assets/cleanup_presets/cleanup-hibit.json",
	"res://assets/cleanup_presets/cleanup-gb.json",
	"res://assets/cleanup_presets/cleanup-hd2d-prop.json",
	"res://assets/cleanup_presets/cleanup-1bit.json",
	"res://assets/cleanup_presets/cleanup-nes.json",
	"res://assets/cleanup_presets/cleanup-16bit-db32.json",
]
const ALLOWED_FIELDS := ["cleanup_preset_version", "id", "name", "name_key", "settings"]
const BASE_SIZES := [0, 8, 16, 24, 32, 48, 64, 96, 128]
const DETECT_MODES := ["auto", "manual"]
const RESAMPLE_MODES := ["mode", "center", "median", "edge_aware"]
const QUANTIZE_MODES := ["auto_k", "fixed_palette", "none"]
const AUTO_K_STRATEGIES := ["median_cut", "kmeans"]
const DITHER_MODES := ["none", "bayer2", "bayer4", "bayer8", "chromatic", "error_diffusion"]

var _presets := {}


func _init() -> void:
	for path in BUILTIN_PATHS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_normalize_builtin_integer_fields(parsed)
			register_preset(parsed)


static func validate_preset(preset: Dictionary) -> Dictionary:
	var schema_validation := SchemaTextResolverScript.validate_schema([preset])
	if not bool(schema_validation.get("ok", false)):
		return schema_validation
	for field in ["cleanup_preset_version", "id", "settings"]:
		if not preset.has(field):
			return _failure("invalid_cleanup_preset", {"field": field})
	if preset.size() != 4 or not _has_no_unknown_keys(preset, ALLOWED_FIELDS):
		return _failure("invalid_cleanup_preset")
	if not (preset["cleanup_preset_version"] is int) or preset["cleanup_preset_version"] != 1:
		return _failure("unsupported_cleanup_preset_version")
	if not (preset["id"] is String) or String(preset["id"]).is_empty():
		return _failure("invalid_cleanup_preset", {"field": "id"})
	if preset.has("name") == preset.has("name_key"):
		return _failure("invalid_cleanup_preset", {"field": "name"})
	if preset.has("name") and (
		not (preset["name"] is String) or String(preset["name"]).is_empty()
	):
		return _failure("invalid_cleanup_preset", {"field": "name"})
	if preset.has("name_key") and not (preset["name_key"] is String):
		return _failure("invalid_cleanup_preset", {"field": "name_key"})
	if not (preset["settings"] is Dictionary):
		return _failure("invalid_cleanup_preset", {"field": "settings"})
	return _validate_settings(preset["settings"])


func register_preset(preset: Dictionary) -> bool:
	if not bool(validate_preset(preset).get("ok", false)):
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


static func _validate_settings(settings: Dictionary) -> Dictionary:
	if not _has_only_keys(settings, ["detect_grid", "resample", "quantize"]):
		return _failure("invalid_cleanup_preset", {"field": "settings"})
	for group in ["detect_grid", "resample", "quantize"]:
		if not (settings.get(group) is Dictionary):
			return _failure("invalid_cleanup_preset", {"field": group})
	var detect: Dictionary = settings["detect_grid"]
	var resample: Dictionary = settings["resample"]
	var quantize: Dictionary = settings["quantize"]
	if not _has_only_keys(detect, ["enabled", "mode", "scale", "offset", "base_size"]):
		return _failure("invalid_cleanup_preset", {"field": "detect_grid"})
	if (
		detect.get("enabled") != true
		or not (detect.get("mode") is String)
		or detect["mode"] not in DETECT_MODES
	):
		return _failure("invalid_cleanup_preset", {"field": "detect_grid"})
	if not (detect.get("base_size") is int) or detect["base_size"] not in BASE_SIZES:
		return _failure("invalid_cleanup_preset", {"field": "base_size"})
	if not _valid_scale(detect.get("scale")) or not _valid_offset(detect.get("offset")):
		return _failure("invalid_cleanup_preset", {"field": "detect_grid"})
	if not _has_only_keys(resample, ["enabled", "mode", "scale", "offset"]):
		return _failure("invalid_cleanup_preset", {"field": "resample"})
	if (
		not (resample.get("enabled") is bool)
		or not (resample.get("mode") is String)
		or resample["mode"] not in RESAMPLE_MODES
	):
		return _failure("invalid_cleanup_preset", {"field": "resample"})
	if not _valid_scale(resample.get("scale")) or not _valid_offset(resample.get("offset")):
		return _failure("invalid_cleanup_preset", {"field": "resample"})
	if float(detect["scale"]) != float(resample["scale"]) or detect["offset"] != resample["offset"]:
		return _failure("invalid_cleanup_preset", {"field": "geometry"})
	var quantize_fields := [
		"enabled", "mode", "palette_id", "auto_k_strategy", "k", "dither",
		"dither_strength", "dither_contrast", "dither_chroma", "dither_density",
	]
	if not _has_only_keys(quantize, quantize_fields):
		return _failure("invalid_cleanup_preset", {"field": "quantize"})
	if not (quantize.get("enabled") is bool):
		return _failure("invalid_cleanup_preset", {"field": "enabled"})
	if not (quantize.get("mode") is String) or quantize["mode"] not in QUANTIZE_MODES:
		return _failure("invalid_cleanup_preset", {"field": "mode"})
	if not (quantize.get("palette_id") is String) or String(quantize["palette_id"]).is_empty():
		return _failure("invalid_cleanup_preset", {"field": "palette_id"})
	if (
		not (quantize.get("auto_k_strategy") is String)
		or quantize["auto_k_strategy"] not in AUTO_K_STRATEGIES
	):
		return _failure("invalid_cleanup_preset", {"field": "auto_k_strategy"})
	if not (quantize.get("k") is int):
		return _failure("invalid_cleanup_preset", {"field": "k"})
	var color_count: int = quantize["k"]
	if color_count < 2 or color_count > 256:
		return _failure("invalid_cleanup_preset", {"field": "k"})
	if not (quantize.get("dither") is String) or quantize["dither"] not in DITHER_MODES:
		return _failure("invalid_cleanup_preset", {"field": "dither"})
	for field in ["dither_strength", "dither_contrast", "dither_density"]:
		if not _in_range(quantize.get(field), 0.0, 1.0):
			return _failure("invalid_cleanup_preset", {"field": field})
	if not _in_range(quantize.get("dither_chroma"), 0.0, 0.25):
		return _failure("invalid_cleanup_preset", {"field": "dither_chroma"})
	if float(quantize["dither_strength"]) != float(quantize["dither_contrast"]):
		return _failure("invalid_cleanup_preset", {"field": "dither_strength"})
	return {"ok": true}


static func _has_only_keys(value: Dictionary, allowed: Array) -> bool:
	if value.size() != allowed.size():
		return false
	for field in allowed:
		if not value.has(field):
			return false
	return true


static func _has_no_unknown_keys(value: Dictionary, allowed: Array) -> bool:
	for field in value.keys():
		if String(field) not in allowed:
			return false
	return true


static func _normalize_builtin_integer_fields(preset: Dictionary) -> void:
	if preset.get("cleanup_preset_version") is float:
		preset["cleanup_preset_version"] = int(preset["cleanup_preset_version"])
	var settings: Dictionary = preset.get("settings", {})
	var detect: Dictionary = settings.get("detect_grid", {})
	var quantize: Dictionary = settings.get("quantize", {})
	if detect.get("base_size") is float:
		detect["base_size"] = int(detect["base_size"])
	if quantize.get("k") is float:
		quantize["k"] = int(quantize["k"])


static func _valid_scale(value: Variant) -> bool:
	return (value is int or value is float) and float(value) >= 1.0 and float(value) <= 64.0


static func _valid_offset(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and _in_range(value[0], 0.0, 64.0)
		and _in_range(value[1], 0.0, 64.0)
	)


static func _in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and float(value) >= minimum and float(value) <= maximum


static func _failure(code: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "args": args.duplicate(true)}
