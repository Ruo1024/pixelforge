class_name SchemaTextResolver
extends RefCounted

## The only dynamic localization access point for provider, node, and preset schemas.

const Catalog := preload("res://infra/localization_catalog.gd")
const RESOLVABLE_SCHEMA_FIELDS := ["label_key", "help_key", "placeholder_key"]
const RAW_TEXT_FIELDS := ["label", "help", "description"]


static func validate_schema(schema: Array, catalogs: Dictionary = {}) -> Dictionary:
	var resolved_catalogs := catalogs if not catalogs.is_empty() else _load_catalogs()
	for locale in ["en", "zh_CN"]:
		if not (resolved_catalogs.get(locale) is Dictionary):
			return _failure("missing_catalog", {"locale": locale})
	for entry_value in schema:
		if not (entry_value is Dictionary):
			return _failure("invalid_schema_entry")
		var entry: Dictionary = entry_value
		for raw_field in RAW_TEXT_FIELDS:
			if entry.has(raw_field):
				return _failure("raw_schema_text", {"field": raw_field})
		for field_value in entry.keys():
			var field := String(field_value)
			if not field.ends_with("_key"):
				continue
			if not (entry[field] is String):
				return _failure("invalid_schema_key", {"field": field})
			var validation := validate_key(entry[field], resolved_catalogs)
			if not bool(validation.get("ok", false)):
				return validation
	return {"ok": true}


static func validate_key(key: String, catalogs: Dictionary = {}) -> Dictionary:
	if key.is_empty():
		return _failure("invalid_schema_key")
	var resolved_catalogs := catalogs if not catalogs.is_empty() else _load_catalogs()
	for locale in ["en", "zh_CN"]:
		var catalog_value: Variant = resolved_catalogs.get(locale)
		if not (catalog_value is Dictionary):
			return _failure("missing_catalog", {"locale": locale})
		var catalog: Dictionary = catalog_value
		if not catalog.has(key) or not (catalog[key] is String) or catalog[key].is_empty():
			return _failure("missing_schema_text", {"locale": locale, "key": key})
	var english: Dictionary = resolved_catalogs["en"]
	var chinese: Dictionary = resolved_catalogs["zh_CN"]
	if (
		Catalog.format_placeholders(String(english[key]))
		!= Catalog.format_placeholders(String(chinese[key]))
	):
		return _failure("schema_text_placeholders_mismatch", {"key": key})
	return {"ok": true}


static func resolve(schema_entry: Dictionary, field: String, args: Array = []) -> String:
	if field not in RESOLVABLE_SCHEMA_FIELDS or not schema_entry.has(field):
		return ""
	var dynamic_key := String(schema_entry[field])
	if not bool(validate_key(dynamic_key).get("ok", false)):
		return ""
	return LocalizationService.text(dynamic_key, args)


static func _load_catalogs() -> Dictionary:
	return {
		"en": Catalog.load_catalog("en"),
		"zh_CN": Catalog.load_catalog("zh_CN"),
	}


static func _failure(code: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "args": args.duplicate(true)}
