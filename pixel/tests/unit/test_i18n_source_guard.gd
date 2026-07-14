extends "res://addons/gut/test.gd"

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
		"(?m)(?:text|title|dialog_text|tooltip_text|placeholder_text)"
		+ "\\s*=\\s*\"[A-Za-z][^\"]*\""
	)
	for path in _gd_files(UI_ROOT):
		for token in _matches(FileAccess.get_file_as_string(path), pattern):
			failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func test_dynamic_catalog_access_is_confined_to_compatibility_and_schema_resolver() -> void:
	var failures := []
	for root in ["res://ui", "res://services", "res://plugins"]:
		for path in _gd_files(root):
			if path in [STRINGS_PATH, SCHEMA_RESOLVER_PATH]:
				continue
			var source := FileAccess.get_file_as_string(path)
			for token in _matches(
				source,
				"(?:Strings|PFStrings|LocalizationService)\\.text\\(\\s*(?![\"&])"
			):
				failures.append("%s: %s" % [path, token])
	assert_eq(failures, [])


func _gd_files(root: String) -> Array[String]:
	var result: Array[String] = []
	_collect_gd(root, result)
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
