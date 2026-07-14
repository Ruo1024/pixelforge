extends "res://addons/gut/test.gd"

const REGISTRY_PATH := "res://services/prompt_preset_registry.gd"
const BUILTIN_DIR := "res://assets/prompt_presets"

const EXPECTED := {
	"prompt-hibit":
	{
		"name_key": "PROMPT_PRESET_HIBIT",
		"prefix": "high detail pixel art, controlled palette, modern hi-bit game asset",
	},
	"prompt-gb":
	{
		"name_key": "PROMPT_PRESET_GB",
		"prefix": "Game Boy pixel art, four color palette, monochrome handheld sprite",
	},
	"prompt-hd2d-prop":
	{
		"name_key": "PROMPT_PRESET_HD2D_PROP",
		"prefix": "HD-2D pixel prop, crisp sprite, high resolution pixel prop",
	},
	"prompt-1bit":
	{
		"name_key": "PROMPT_PRESET_1BIT",
		"prefix": "1-bit pixel art, black and white, binary monochrome sprite",
	},
	"prompt-nes":
	{
		"name_key": "PROMPT_PRESET_NES",
		"prefix": "NES pixel art sprite, limited hardware palette, 8-bit console sprite",
	},
	"prompt-16bit-db32":
	{
		"name_key": "PROMPT_PRESET_16BIT_DB32",
		"prefix": (
			"pixel art, 16-bit style, limited palette, clean pixel grid, "
			+ "retro game asset, DawnBringer palette"
		),
	},
}


func test_schema_and_six_exact_builtins() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script, "B7-2 must add PromptPreset registry")
	if registry_script == null:
		return
	var registry: Variant = registry_script.new()
	var expected_ids: Array = EXPECTED.keys()
	expected_ids.sort()
	assert_eq(registry.get_preset_ids(), expected_ids)
	for preset_id in EXPECTED:
		var preset: Dictionary = registry.get_preset(preset_id)
		assert_eq(
			preset,
			{
				"prompt_preset_version": 1,
				"id": preset_id,
				"name_key": EXPECTED[preset_id]["name_key"],
				"prefix": EXPECTED[preset_id]["prefix"],
			}
		)
		assert_true(FileAccess.file_exists(BUILTIN_DIR.path_join("%s.json" % preset_id)))


func test_prefix_only_and_name_xor() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script)
	if registry_script == null:
		return
	var user := {
		"prompt_preset_version": 1,
		"id": "user-prompt",
		"name": "User prompt",
		"prefix": "literal {subject} prefix",
	}
	assert_true(bool(registry_script.validate_preset(user).get("ok", false)))
	for invalid in [
		user.merged({"name_key": "PROMPT_PRESET_HIBIT"}),
		user.duplicate(true).merged({"name": null}, true),
		user.merged({"prompt_preset_version": "1"}, true),
		user.merged({"prompt_preset_version": 1.0}, true),
		user.merged({"palette": "db32"}),
		user.merged({"negative_prompt": "blur"}),
		user.merged({"provider_hints": {}}),
		user.merged({"based_on": "prompt-hibit"}),
	]:
		var validation: Dictionary = registry_script.validate_preset(invalid)
		assert_false(bool(validation.get("ok", false)))
		assert_false(validation.has("reason"), "validation errors store code+args only")


func test_registry_rejects_duplicates_and_returns_detached_snapshots() -> void:
	var registry_script: Variant = load(REGISTRY_PATH)
	assert_not_null(registry_script)
	if registry_script == null:
		return
	var registry: Variant = registry_script.new()
	var custom := {
		"prompt_preset_version": 1,
		"id": "user-prompt",
		"name": "User prompt",
		"prefix": "user prefix",
	}
	assert_true(registry.register_preset(custom))
	assert_false(registry.register_preset(custom))
	var snapshot: Dictionary = registry.get_preset("user-prompt")
	snapshot["prefix"] = "mutated"
	assert_eq(registry.get_preset("user-prompt")["prefix"], "user prefix")
