extends "res://addons/gut/test.gd"

const Catalog := preload("res://infra/localization_catalog.gd")
const Localization := preload("res://services/localization_service.gd")
const LanguageSelector := preload("res://ui/widgets/language_selector.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")


func test_system_locale_resolution_is_deliberately_narrow() -> void:
	assert_eq(Localization.resolve_locale("auto", "zh_CN"), "zh_CN")
	assert_eq(Localization.resolve_locale("auto", "zh-Hans-CN"), "zh_CN")
	assert_eq(Localization.resolve_locale("auto", "zh_TW"), "en")
	assert_eq(Localization.resolve_locale("auto", "zh_HK"), "en")
	assert_eq(Localization.resolve_locale("auto", "en_US"), "en")
	assert_eq(Localization.resolve_locale("zh_CN", "en_US"), "zh_CN")
	assert_eq(Localization.resolve_locale("en", "zh_CN"), "en")


func test_catalog_keys_and_format_placeholders_match() -> void:
	assert_eq(Catalog.load_and_validate(), PackedStringArray())


func test_catalog_validator_reports_key_and_placeholder_drift() -> void:
	assert_eq(Catalog.format_placeholders("Processed %d in %s"), PackedStringArray(["%d", "%s"]))
	assert_eq(Catalog.format_placeholders("在 %s 中处理 %d"), PackedStringArray(["%s", "%d"]))
	var key_errors := (
		Catalog
		. validate_catalogs(
			{
				"en": {"A": "Value %d", "B": "Name %s"},
				"zh_CN": {"A": "值 %s", "C": "额外"},
			}
		)
	)
	assert_has(key_errors, "zh_CN catalog keys differ from en")
	var placeholder_errors := (
		Catalog
		. validate_catalogs(
			{
				"en": {"A": "Processed %d in %s"},
				"zh_CN": {"A": "在 %s 中处理 %d"},
			}
		)
	)
	assert_has(placeholder_errors, "zh_CN:A format placeholders differ from en")


func test_language_preference_persists_and_applies_translation() -> void:
	var settings := get_tree().root.get_node("SettingsService")
	var localization := get_tree().root.get_node("LocalizationService")
	var original := String(settings.get_setting("ui", "language", "auto"))
	assert_true(localization.set_language("zh_CN"))
	assert_eq(settings.get_setting("ui", "language"), "zh_CN")
	assert_eq(localization.current_locale, "zh_CN")
	assert_eq(localization.text("LANGUAGE_LABEL"), "语言")
	assert_false(localization.set_language("unsupported"))
	localization.set_language(original)


func test_language_selector_refreshes_after_language_change() -> void:
	var localization := get_tree().root.get_node("LocalizationService")
	var original: String = String(localization.current_preference)
	var selector: PFLanguageSelector = autofree(LanguageSelector.new())
	add_child(selector)
	assert_eq(selector._options.item_count, 3)
	localization.set_language("zh_CN")
	assert_eq(selector._label.text, "语言")
	assert_eq(selector._options.get_item_text(0), "跟随系统")
	localization.set_language(original)


func test_bundled_ui_font_covers_representative_english_and_simplified_chinese() -> void:
	var font := UIFont.get_font()
	assert_not_null(font)
	for character in ["A", "中", "文", "像", "素"]:
		assert_true(font.has_char(character.unicode_at(0)), "Missing UI glyph: %s" % character)
	assert_true(FileAccess.file_exists("res://assets/fonts/OFL.txt"))
