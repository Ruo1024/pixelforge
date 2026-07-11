class_name PFLocalizationService
extends Node

## Owns locale resolution and TranslationServer registration for application UI text.

signal language_changed(preference: String, locale: String)

const Catalog := preload("res://infra/localization_catalog.gd")
const LANGUAGE_SECTION := "ui"
const LANGUAGE_KEY := "language"
const LANGUAGE_AUTO := "auto"
const LANGUAGE_ENGLISH := "en"
const LANGUAGE_SIMPLIFIED_CHINESE := "zh_CN"
const SUPPORTED_PREFERENCES := [LANGUAGE_AUTO, LANGUAGE_ENGLISH, LANGUAGE_SIMPLIFIED_CHINESE]

var current_preference := LANGUAGE_AUTO
var current_locale := LANGUAGE_ENGLISH
var _translations: Array[Translation] = []


func _ready() -> void:
	_register_catalogs()
	SettingsService.setting_changed.connect(_on_setting_changed)
	apply_language(
		String(SettingsService.get_setting(LANGUAGE_SECTION, LANGUAGE_KEY, LANGUAGE_AUTO))
	)


func set_language(preference: String) -> bool:
	if preference not in SUPPORTED_PREFERENCES:
		return false
	SettingsService.set_setting(LANGUAGE_SECTION, LANGUAGE_KEY, preference)
	if preference == current_preference:
		apply_language(preference)
	return true


func apply_language(preference: String, system_locale: String = "") -> String:
	current_preference = preference if preference in SUPPORTED_PREFERENCES else LANGUAGE_AUTO
	var detected_locale := system_locale if not system_locale.is_empty() else OS.get_locale()
	current_locale = resolve_locale(current_preference, detected_locale)
	TranslationServer.set_locale(current_locale)
	language_changed.emit(current_preference, current_locale)
	return current_locale


func text(key: StringName, fallback: String = "") -> String:
	var translated := TranslationServer.translate(key)
	if translated != String(key):
		return translated
	return fallback if not fallback.is_empty() else String(key)


static func resolve_locale(preference: String, system_locale: String) -> String:
	if preference == LANGUAGE_SIMPLIFIED_CHINESE:
		return LANGUAGE_SIMPLIFIED_CHINESE
	if preference == LANGUAGE_ENGLISH:
		return LANGUAGE_ENGLISH
	var normalized := system_locale.replace("-", "_")
	var lower := normalized.to_lower()
	if lower == "zh" or lower.begins_with("zh_cn") or lower.begins_with("zh_hans"):
		return LANGUAGE_SIMPLIFIED_CHINESE
	return LANGUAGE_ENGLISH


func _register_catalogs() -> void:
	for locale_value in Catalog.CATALOG_PATHS.keys():
		var locale := String(locale_value)
		var catalog := Catalog.load_catalog(locale)
		var translation := Translation.new()
		translation.locale = locale
		for key_value in catalog.keys():
			var key := String(key_value)
			translation.add_message(StringName(key), StringName(String(catalog[key])))
		TranslationServer.add_translation(translation)
		_translations.append(translation)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == LANGUAGE_SECTION and key == LANGUAGE_KEY:
		apply_language(String(value))
