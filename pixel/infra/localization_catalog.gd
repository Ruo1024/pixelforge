class_name PFLocalizationCatalog
extends RefCounted

## Loads stable localization keys and validates cross-locale catalog invariants.

const CATALOG_PATHS := {
	"en": "res://assets/i18n/en.json",
	"zh_CN": "res://assets/i18n/zh_CN.json",
}


static func load_catalog(locale: String) -> Dictionary:
	var path := String(CATALOG_PATHS.get(locale, ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


static func validate_catalogs(catalogs: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var english: Dictionary = catalogs.get("en", {})
	if english.is_empty():
		errors.append("English catalog is missing or empty")
		return errors
	var expected_keys := english.keys()
	expected_keys.sort()
	for locale_value in catalogs.keys():
		var locale := String(locale_value)
		var catalog: Dictionary = catalogs[locale_value]
		var actual_keys := catalog.keys()
		actual_keys.sort()
		if actual_keys != expected_keys:
			errors.append("%s catalog keys differ from en" % locale)
			continue
		for key_value in expected_keys:
			var key := String(key_value)
			if String(catalog[key]).is_empty():
				errors.append("%s:%s is empty" % [locale, key])
				continue
			var expected_placeholders := format_placeholders(String(english[key]))
			var actual_placeholders := format_placeholders(String(catalog[key]))
			if not _same_string_sequence(actual_placeholders, expected_placeholders):
				errors.append("%s:%s format placeholders differ from en" % [locale, key])
	return errors


static func load_and_validate() -> PackedStringArray:
	var catalogs := {}
	for locale_value in CATALOG_PATHS.keys():
		var locale := String(locale_value)
		catalogs[locale] = load_catalog(locale)
	return validate_catalogs(catalogs)


static func format_placeholders(text: String) -> PackedStringArray:
	var placeholders := PackedStringArray()
	var index := 0
	while index < text.length():
		if text.substr(index, 1) != "%":
			index += 1
			continue
		if index + 1 < text.length() and text.substr(index + 1, 1) == "%":
			index += 2
			continue
		var end := index + 1
		while end < text.length() and "+-0123456789.*".contains(text.substr(end, 1)):
			end += 1
		if end < text.length() and "sdfiouxXeEgGc".contains(text.substr(end, 1)):
			placeholders.append("%" + text.substr(index + 1, end - index))
			index = end + 1
		else:
			index += 1
	return placeholders


static func _same_string_sequence(left: PackedStringArray, right: PackedStringArray) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index] != right[index]:
			return false
	return true
