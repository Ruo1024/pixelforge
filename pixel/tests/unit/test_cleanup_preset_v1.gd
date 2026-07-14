extends "res://addons/gut/test.gd"

const REGISTRY_PATH := "res://services/cleanup_preset_registry.gd"
const BUILTIN_DIR := "res://assets/cleanup_presets"

const CASES := {
	"cleanup-hibit": ["CLEANUP_PRESET_HIBIT", 48, true, "fixed_palette", "endesga64", 32, "none", 0.0],
	"cleanup-gb": ["CLEANUP_PRESET_GB", 16, true, "fixed_palette", "gb_4", 4, "bayer4", 0.35],
	"cleanup-hd2d-prop": ["CLEANUP_PRESET_HD2D_PROP", 64, false, "none", "custom", 64, "none", 0.0],
	"cleanup-1bit": ["CLEANUP_PRESET_1BIT", 32, true, "fixed_palette", "bw_2", 2, "bayer4", 0.5],
	"cleanup-nes": ["CLEANUP_PRESET_NES", 16, true, "fixed_palette", "nes_full", 4, "none", 0.0],
	"cleanup-16bit-db32":
	["CLEANUP_PRESET_16BIT_DB32", 32, true, "fixed_palette", "db32", 16, "none", 0.0],
}


func test_schema_and_six_full_snapshots() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script, "B7-2 must add CleanupPreset registry")
	if registry_script == null:
		return
	var registry: Variant = registry_script.new()
	var expected_ids: Array = CASES.keys()
	expected_ids.sort()
	assert_eq(registry.get_preset_ids(), expected_ids)
	for preset_id in CASES:
		var preset: Dictionary = registry.get_preset(preset_id)
		assert_eq(preset, _expected_preset(preset_id, CASES[preset_id]))
		assert_true(FileAccess.file_exists(BUILTIN_DIR.path_join("%s.json" % preset_id)))


func test_cleanup_settings_validator() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script)
	if registry_script == null:
		return
	var valid: Dictionary = _expected_preset(
		"user-cleanup", ["", 32, true, "fixed_palette", "db32", 16, "none", 0.0]
	)
	valid.erase("name_key")
	valid["name"] = "User cleanup"
	assert_true(bool(registry_script.validate_preset(valid).get("ok", false)))
	var invalid_cases := []
	var disabled_detect := valid.duplicate(true)
	disabled_detect["settings"]["detect_grid"]["enabled"] = false
	invalid_cases.append(disabled_detect)
	var split_scale := valid.duplicate(true)
	split_scale["settings"]["resample"]["scale"] = 3.0
	invalid_cases.append(split_scale)
	var split_offset := valid.duplicate(true)
	split_offset["settings"]["resample"]["offset"] = [1.0, 0.0]
	invalid_cases.append(split_offset)
	var split_strength := valid.duplicate(true)
	split_strength["settings"]["quantize"]["dither_contrast"] = 0.5
	invalid_cases.append(split_strength)
	var target_size := valid.duplicate(true)
	target_size["settings"]["target_size"] = [32, 32]
	invalid_cases.append(target_size)
	var string_version := valid.duplicate(true)
	string_version["cleanup_preset_version"] = "1"
	invalid_cases.append(string_version)
	var float_version := valid.duplicate(true)
	float_version["cleanup_preset_version"] = 1.0
	invalid_cases.append(float_version)
	var float_k := valid.duplicate(true)
	float_k["settings"]["quantize"]["k"] = 16.0
	invalid_cases.append(float_k)
	for invalid in invalid_cases:
		var validation: Dictionary = registry_script.validate_preset(invalid)
		assert_false(bool(validation.get("ok", false)))
		assert_false(validation.has("reason"), "validation errors store code+args only")


func test_registry_rejects_duplicates_and_returns_detached_settings() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script)
	if registry_script == null:
		return
	var registry: Variant = registry_script.new()
	var custom: Dictionary = _expected_preset(
		"user-cleanup", ["", 32, true, "fixed_palette", "db32", 16, "none", 0.0]
	)
	custom.erase("name_key")
	custom["name"] = "User cleanup"
	assert_true(registry.register_preset(custom))
	assert_false(registry.register_preset(custom))
	var snapshot: Dictionary = registry.get_preset("user-cleanup")
	snapshot["settings"]["detect_grid"]["base_size"] = 8
	assert_eq(registry.get_preset("user-cleanup")["settings"]["detect_grid"]["base_size"], 32)


func _expected_preset(preset_id: String, values: Array) -> Dictionary:
	return {
		"cleanup_preset_version": 1,
		"id": preset_id,
		"name_key": values[0],
		"settings":
		{
			"detect_grid":
			{"enabled": true, "mode": "auto", "scale": 4.0, "offset": [0.0, 0.0], "base_size": values[1]},
			"resample":
			{"enabled": true, "mode": "mode", "scale": 4.0, "offset": [0.0, 0.0]},
			"quantize":
			{
				"enabled": values[2],
				"mode": values[3],
				"palette_id": values[4],
				"auto_k_strategy": "median_cut",
				"k": values[5],
				"dither": values[6],
				"dither_strength": values[7],
				"dither_contrast": values[7],
				"dither_chroma": 0.0,
				"dither_density": 1.0,
			}
		}
	}
