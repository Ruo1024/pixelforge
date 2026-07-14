extends "res://addons/gut/test.gd"

const ADAPTER_PATH := "res://services/legacy_generation_v2_adapter.gd"


func test_no_v1_alias_or_migration() -> void:
	var matches: Array[String] = []
	for file_name in DirAccess.get_files_at("res://services"):
		var normalized := String(file_name)
		if "legacy" in normalized and "adapter" in normalized and normalized.ends_with(".gd"):
			matches.append(normalized)
	assert_eq(matches, ["legacy_generation_v2_adapter.gd"])
	assert_true(FileAccess.file_exists(ADAPTER_PATH))
	var source := FileAccess.get_file_as_string(ADAPTER_PATH)
	assert_false("migrate_v1" in source)
	assert_false("from_v1" in source)


func test_adapter_is_marked_for_b7_4_removal_and_has_no_overwrite_alias() -> void:
	var source := FileAccess.get_file_as_string(ADAPTER_PATH)
	assert_string_contains(source, "B7-4 DELETE")
	assert_false("replace_batch_assets" in source)
	assert_false("params[\"asset_ids\"]" in source)
