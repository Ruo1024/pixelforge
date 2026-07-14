extends "res://addons/gut/test.gd"

const REGISTRY_PATH := "res://services/prompt_preset_registry.gd"
const BUILTIN_DIR := "res://assets/prompt_presets"
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const PromptPresetNode := preload("res://core/graph/nodes/prompt_preset_node.gd")
const Catalog := preload("res://infra/localization_catalog.gd")

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
		"prefix":
		(
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


func test_rejects_negative_template_and_multidomain_fields() -> void:
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
	var invalid_presets := [
		user.merged({"name_key": "PROMPT_PRESET_HIBIT"}),
		user.duplicate(true).merged({"name": null}, true),
		user.merged({"prompt_preset_version": "1"}, true),
		user.merged({"prompt_preset_version": 1.0}, true),
	]
	for field in [
		"palette",
		"base_size",
		"outline",
		"dither",
		"perspective",
		"provider_mapping",
		"provider_hints",
		"editor_settings",
		"map_settings",
		"negative_prompt",
		"prompt_template",
		"based_on",
	]:
		invalid_presets.append(user.merged({field: "forbidden"}))
	for invalid in invalid_presets:
		var validation: Dictionary = registry_script.validate_preset(invalid)
		assert_false(bool(validation.get("ok", false)))
		assert_false(validation.has("reason"), "validation errors store code+args only")
	assert_true(user["prefix"].contains("{subject}"))


func test_name_modes_default_and_canvas_contract() -> void:
	assert_eq(Catalog.load_catalog("en")["NODE_PROMPT_PRESET"], "Style Prompt")
	assert_eq(Catalog.load_catalog("zh_CN")["NODE_PROMPT_PRESET"], "风格提示词")
	assert_eq(PromptPresetNode.DEFAULT_PRESET["id"], "prompt-16bit-db32")
	assert_eq(CardContract.default_size_for_type("prompt_preset"), Vector2i(320, 280))
	assert_eq(CardContract.minimum_size_for_type("prompt_preset"), Vector2i(280, 220))
	assert_eq(
		CardContract.normalize_requested_size("prompt_preset", Vector2i(9999, 9999)),
		Vector2i(1600, 1200)
	)


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
