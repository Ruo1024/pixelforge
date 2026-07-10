extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")


func test_pending_recovery_before_main_ready_still_reaches_dialog() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var previous_pending: Array = project_service._pending_recovery_autosaves.duplicate()
	project_service._pending_recovery_autosaves = ["user://autosave/recovery-test.pxproj"]
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)

	var recovery_dialog: ConfirmationDialog = main.get_node("RecoveryDialog")
	assert_true(recovery_dialog.visible)
	assert_string_contains(recovery_dialog.dialog_text, "unsaved copy")
	assert_false(get_tree().auto_accept_quit)
	recovery_dialog.hide()
	project_service._pending_recovery_autosaves = previous_pending


func test_project_file_failures_are_visible_and_actionable() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	get_tree().root.get_node("ProjectService").new_project("Failure Feedback")

	main.call("_perform_open_project", "user://tests/missing-project.pxproj")
	assert_string_contains(_status_label(main).text, "Open failed")
	assert_string_contains(_status_label(main).text, "valid PixelForge project")

	main.call("_save_project_path", "/dev/null/pixelforge-save-test.pxproj")
	assert_string_contains(_status_label(main).text, "Save failed")
	assert_string_contains(_status_label(main).text, "choose Save As")


func _status_label(main: Control) -> Label:
	return main.get_node("Root/BottomBar").get_child(0)
