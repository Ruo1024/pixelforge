extends "res://addons/gut/test.gd"

const Catalog := preload("res://infra/localization_catalog.gd")
const UI_ROOT := "res://ui"
const STRINGS_PATH := "res://ui/shell/strings.gd"
const SCHEMA_RESOLVER_PATH := "res://services/schema_text_resolver.gd"


func test_strings_compatibility_entry_has_no_visible_constants() -> void:
	var source := FileAccess.get_file_as_string(STRINGS_PATH)
	assert_eq(_matches(source, "(?m)^\\s*const\\s+[A-Z][A-Z0-9_]*\\s*:="), [])
	assert_true("static func text(" in source)


func test_production_ui_has_no_direct_strings_constants() -> void:
	var failures := []
	for path in _gd_files(UI_ROOT):
		for token in _matches(
			FileAccess.get_file_as_string(path), "(?:PF)?Strings\\.[A-Z][A-Z0-9_]+"
		):
			failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func test_visible_control_properties_have_no_raw_english_literals() -> void:
	var failures := []
	var pattern := (
		"(?m)(?:text|title|dialog_text|tooltip_text|placeholder_text)" + '\\s*=\\s*"[A-Za-z][^"]*"'
	)
	for path in _gd_files(UI_ROOT):
		for token in _matches(FileAccess.get_file_as_string(path), pattern):
			failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func test_dynamic_catalog_access_is_confined_to_compatibility_and_schema_resolver() -> void:
	var failures := []
	var allowed_paths := [
		ProjectSettings.globalize_path(STRINGS_PATH),
		ProjectSettings.globalize_path(SCHEMA_RESOLVER_PATH),
	]
	for root in ["res://ui", "res://services", "res://plugins"]:
		for path in _gd_files(root):
			if path in allowed_paths:
				continue
			var source := FileAccess.get_file_as_string(path)
			for token in _matches(
				source, '(?:Strings|PFStrings|LocalizationService)\\.text\\(\\s*+(?!["&])'
			):
				failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func test_provider_and_node_schemas_have_no_raw_visible_fields() -> void:
	var failures := []
	var pattern := '(?m)"(?:label|help|placeholder|description)"' + '\\s*:\\s*"[A-Za-z][^"]*"'
	for root in ["res://core/graph/nodes", "res://plugins"]:
		for path in _gd_files(root):
			for token in _matches(FileAccess.get_file_as_string(path), pattern):
				failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func test_literal_catalog_keys_exist_in_both_languages() -> void:
	var english: Dictionary = Catalog.load_catalog("en")
	var chinese: Dictionary = Catalog.load_catalog("zh_CN")
	var failures := []
	for root in ["res://ui", "res://services", "res://plugins"]:
		for path in _gd_files(root):
			var source := FileAccess.get_file_as_string(path)
			for key in _captures(
				source, '(?:Strings|PFStrings|LocalizationService)\\.text\\(\\s*+["&]([^"]+)'
			):
				if not english.has(key) or String(english.get(key, "")).is_empty():
					failures.append("%s: en:%s" % [path, key])
				if not chinese.has(key) or String(chinese.get(key, "")).is_empty():
					failures.append("%s: zh_CN:%s" % [path, key])
	assert_eq(failures, [])


func _gd_files(root: String) -> Array[String]:
	var result: Array[String] = []
	_collect_gd(ProjectSettings.globalize_path(root), result)
	return result


func _collect_gd(root: String, result: Array[String]) -> void:
	var directory := DirAccess.open(root)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var path := root.path_join(entry)
		if directory.current_is_dir():
			_collect_gd(path, result)
		elif entry.ends_with(".gd"):
			result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _matches(source: String, pattern: String) -> Array[String]:
	var regex := RegEx.new()
	assert_eq(regex.compile(pattern), OK, pattern)
	var result: Array[String] = []
	for found in regex.search_all(source):
		result.append(found.get_string())
	return result


func _captures(source: String, pattern: String) -> Array[String]:
	var regex := RegEx.new()
	assert_eq(regex.compile(pattern), OK, pattern)
	var result: Array[String] = []
	for found in regex.search_all(source):
		result.append(found.get_string(1))
	return result
