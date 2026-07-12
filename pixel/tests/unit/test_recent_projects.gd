extends "res://addons/gut/test.gd"

const FileIO := preload("res://infra/file_io.gd")

const EXISTING_PATH := "user://tests/recent_exists.pxproj"


func before_each() -> void:
	SettingsService.set_setting("project", "recent_projects", [], false)
	FileIO.atomic_write(EXISTING_PATH, "fixture".to_utf8_buffer())


func after_each() -> void:
	SettingsService.set_setting("project", "recent_projects", [], false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXISTING_PATH))


func test_recent_projects_are_deduplicated_bounded_and_individually_removable() -> void:
	for index in range(12):
		SettingsService.add_recent_project("user://tests/project-%02d.pxproj" % index)
	SettingsService.add_recent_project("user://tests/project-05.pxproj")

	var recent: Array = SettingsService.get_recent_projects()
	assert_eq(recent.size(), 10)
	assert_eq(recent[0], "user://tests/project-05.pxproj")
	SettingsService.remove_recent_project(recent[0])
	assert_does_not_have(SettingsService.get_recent_projects(), "user://tests/project-05.pxproj")


func test_missing_recent_projects_can_be_removed_without_touching_existing_paths() -> void:
	SettingsService.set_setting(
		"project", "recent_projects", ["user://tests/missing.pxproj", EXISTING_PATH], false
	)

	assert_eq(SettingsService.remove_missing_recent_projects(), 1)
	assert_eq(SettingsService.get_recent_projects(), [EXISTING_PATH])
