extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const ScaleAudit := preload("res://ui/shell/scale_audit.gd")
const Strings := preload("res://ui/shell/strings.gd")
const V1OnboardingDialogScript := preload("res://ui/dialogs/v1_onboarding_dialog.gd")


func test_onboarding_uses_one_content_layout_without_native_dialog_text() -> void:
	var dialog: ConfirmationDialog = V1OnboardingDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(2)

	var content: VBoxContainer = dialog.get_label().get_parent().get_node("Content")
	var intro: Label = content.get_node("Intro")
	assert_eq(dialog.dialog_text, "")
	assert_eq(intro.text, Strings.text("ONBOARDING_INTRO"))
	assert_eq(intro.get_parent(), content)
	assert_eq(content.get_child(0), intro)


func test_onboarding_content_rows_do_not_intersect_after_layout() -> void:
	var dialog: ConfirmationDialog = V1OnboardingDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(2)
	dialog.show_setup()
	await wait_process_frames(2)

	var content: VBoxContainer = dialog.get_label().get_parent().get_node("Content")
	for index in range(content.get_child_count() - 1):
		var current := content.get_child(index) as Control
		var following := content.get_child(index + 1) as Control
		assert_not_null(current)
		assert_not_null(following)
		assert_lte(current.get_global_rect().end.y, following.get_global_rect().position.y)
	assert_lte(content.get_global_rect().end.y, dialog.get_ok_button().get_global_rect().position.y)
	assert_lte(
		content.get_global_rect().end.y, dialog.get_cancel_button().get_global_rect().position.y
	)
	assert_lte(dialog.size.y, 300)

	dialog.hide()


func test_recovery_confirmation_text_and_buttons_do_not_intersect() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	main.call("_on_recovery_available", ["user://autosave/recovery-geometry-test.pxproj"])
	await wait_process_frames(2)

	var dialog: ConfirmationDialog = main.get_node("RecoveryDialog")
	_assert_confirmation_geometry(dialog)
	dialog.hide()


func test_onboarding_waits_until_recovery_dialog_is_closed() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	var recovery: ConfirmationDialog = main.get_node("RecoveryDialog")
	var onboarding: ConfirmationDialog = main.get_node("M21UiController/V1OnboardingDialog")
	recovery.popup_centered()
	await wait_process_frames(1)
	main.get_node("M21UiController").call("_show_onboarding_after_blocker", recovery)
	await wait_process_frames(1)
	assert_true(recovery.visible)
	assert_false(onboarding.visible)

	recovery.hide()
	await wait_process_frames(2)
	assert_true(onboarding.visible)
	onboarding.hide()


func test_standard_confirmation_text_and_buttons_do_not_intersect() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "First diagnostic line.\nSecond diagnostic line."
	add_child_autofree(dialog)
	dialog.popup_centered()
	await wait_process_frames(2)

	_assert_confirmation_geometry(dialog)
	dialog.hide()


func test_workspace_settings_content_and_buttons_remain_reachable() -> void:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	main.get_node("RecoveryDialog").hide()
	await wait_process_frames(1)
	var controller: Node = main.get_node("WorkspaceSettingsController")
	controller.call("_show_settings")
	await wait_process_frames(2)

	var dialog: ConfirmationDialog = controller.get_node("WorkspaceSettingsDialog")
	var selector: Control = dialog.get_node("LanguageSelector")
	assert_true(dialog.visible)
	assert_lte(dialog.size.y, 260)
	assert_lte(
		selector.get_global_rect().end.y, dialog.get_ok_button().get_global_rect().position.y
	)
	dialog.hide()


func test_dialog_audit_reports_geometry_parent_chain_and_font_metrics() -> void:
	var dialog: ConfirmationDialog = V1OnboardingDialogScript.new()
	dialog.name = "V1OnboardingDialog"
	add_child_autofree(dialog)
	await wait_process_frames(2)

	var audits: Array = ScaleAudit.collect_dialog_audit(self)
	assert_eq(audits.size(), 1)
	var controls: Array = audits[0]["controls"]
	var content_parent := dialog.get_label().get_parent()
	var intro_path := String(dialog.get_path_to(content_parent.get_node("Content/Intro")))
	var intro_audit := _find_control_audit(controls, intro_path)
	assert_false(intro_audit.is_empty())
	assert_eq(intro_audit["parent_chain"], ["V1OnboardingDialog", "Content", "Intro"])
	assert_gt(float(intro_audit["font"]["ascent"]), 0.0)
	assert_gte(float(intro_audit["font"]["descent"]), 0.0)
	assert_true(intro_audit["font"]["coverage"].has("U+50CF"))


func _assert_confirmation_geometry(dialog: ConfirmationDialog) -> void:
	var label := dialog.get_label()
	var ok_button := dialog.get_ok_button()
	var cancel_button := dialog.get_cancel_button()
	assert_true(dialog.visible)
	assert_gt(label.get_global_rect().size.y, 0.0)
	assert_lte(label.get_global_rect().end.y, ok_button.get_global_rect().position.y)
	assert_lte(label.get_global_rect().end.y, cancel_button.get_global_rect().position.y)


func _find_control_audit(controls: Array, path: String) -> Dictionary:
	for value in controls:
		var audit: Dictionary = value
		if String(audit.get("path", "")) == path:
			return audit
	return {}
