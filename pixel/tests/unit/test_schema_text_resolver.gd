extends "res://addons/gut/test.gd"

const RESOLVER_PATH := "res://services/schema_text_resolver.gd"


func test_schema_registration_requires_bilingual_keys() -> void:
	var resolver: Variant = load(RESOLVER_PATH)
	assert_not_null(resolver, "B7-2 must add the single SchemaTextResolver")
	if resolver == null:
		return
	var catalogs := {
		"en": {"FIELD_LABEL": "Field", "FIELD_HELP": "Help", "FIELD_PLACEHOLDER": "Value"},
		"zh_CN": {"FIELD_LABEL": "字段", "FIELD_HELP": "帮助", "FIELD_PLACEHOLDER": "值"},
	}
	var valid := [
		{
			"key": "field",
			"label_key": "FIELD_LABEL",
			"help_key": "FIELD_HELP",
			"placeholder_key": "FIELD_PLACEHOLDER",
		}
	]
	assert_true(bool(resolver.validate_schema(valid, catalogs).get("ok", false)))

	for invalid in [
		[{"key": "field", "label": "Raw label", "label_key": "FIELD_LABEL"}],
		[{"key": "field", "help": "Raw help", "label_key": "FIELD_LABEL"}],
		[{"key": "field", "description": "Raw description", "label_key": "FIELD_LABEL"}],
		[{"key": "field", "label_key": "MISSING"}],
	]:
		assert_false(bool(resolver.validate_schema(invalid, catalogs).get("ok", false)))

	var missing_zh := catalogs.duplicate(true)
	missing_zh["zh_CN"].erase("FIELD_HELP")
	assert_false(bool(resolver.validate_schema(valid, missing_zh).get("ok", false)))
	var empty_en := catalogs.duplicate(true)
	empty_en["en"]["FIELD_LABEL"] = ""
	assert_false(bool(resolver.validate_schema(valid, empty_en).get("ok", false)))


func test_resolver_validates_preset_name_keys_in_both_catalogs() -> void:
	var resolver: Variant = load(RESOLVER_PATH)
	assert_not_null(resolver)
	if resolver == null:
		return
	var catalogs := {"en": {"PRESET_NAME": "Preset"}, "zh_CN": {"PRESET_NAME": "预设"}}
	assert_true(bool(resolver.validate_key("PRESET_NAME", catalogs).get("ok", false)))
	assert_false(bool(resolver.validate_key("MISSING", catalogs).get("ok", false)))
	catalogs["zh_CN"]["PRESET_NAME"] = ""
	assert_false(bool(resolver.validate_key("PRESET_NAME", catalogs).get("ok", false)))


func test_all_key_fields_validate_but_only_graph_ui_fields_resolve() -> void:
	var resolver: Variant = load(RESOLVER_PATH)
	assert_not_null(resolver)
	if resolver == null:
		return
	var catalogs := {
		"en": {"PRESET_NAME": "Preset", "CUSTOM_VALUE": "Value %s"},
		"zh_CN": {"PRESET_NAME": "预设", "CUSTOM_VALUE": "值 %s"},
	}
	assert_true(
		bool(
			(
				resolver
				. validate_schema(
					[{"name_key": "PRESET_NAME", "custom_key": "CUSTOM_VALUE"}], catalogs
				)
				. get("ok", false)
			)
		)
	)
	assert_eq(resolver.resolve({"name_key": "PROMPT_PRESET_HIBIT"}, "name_key"), "")
	var mismatch := catalogs.duplicate(true)
	mismatch["zh_CN"]["CUSTOM_VALUE"] = "值"
	var invalid: Dictionary = resolver.validate_schema([{"custom_key": "CUSTOM_VALUE"}], mismatch)
	assert_false(bool(invalid.get("ok", false)))
	assert_eq(invalid.get("code", ""), "schema_text_placeholders_mismatch")
	assert_false(invalid.has("reason"), "validation errors store code+args, not rendered text")


func test_b7_provider_schema_keys_exist_in_both_catalogs() -> void:
	var resolver: Variant = load(RESOLVER_PATH)
	assert_not_null(resolver)
	if resolver == null:
		return
	for key in [
		"OPENAI_FIELD_API_KEY",
		"OPENAI_FIELD_API_KEY_HELP",
		"RETRO_FIELD_API_KEY",
		"RETRO_FIELD_API_KEY_HELP",
		"RETRO_FIELD_ENDPOINT",
		"RETRO_FIELD_ENDPOINT_HELP",
		"GEN_PARAM_QUALITY",
		"GEN_PARAM_QUALITY_HELP",
		"GEN_PARAM_REMOVE_BG",
		"GEN_PARAM_REMOVE_BG_HELP",
		"GEN_PARAM_STRENGTH",
		"GEN_PARAM_STRENGTH_HELP",
	]:
		assert_true(bool(resolver.validate_key(key).get("ok", false)), key)
