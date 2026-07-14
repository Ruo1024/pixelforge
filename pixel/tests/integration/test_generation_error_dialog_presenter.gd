extends "res://addons/gut/test.gd"

const PRESENTER_PATH := "res://ui/dialogs/generation_error_dialog_presenter.gd"
const TERMINAL_STEPS := [
	"edge_stopped",
	"successes_saved",
	"failed_slots_updated",
	"safe_errors_recorded",
	"dialog_ready",
]

var _original_language := "en"


func before_each() -> void:
	_original_language = LocalizationService.current_preference
	LocalizationService.set_language("en")


func after_each() -> void:
	LocalizationService.set_language(_original_language)


func test_real_dialog_has_exact_safe_sections_and_is_at_most_once_per_run() -> void:
	var presenter: Variant = await _new_presenter()
	if presenter == null:
		return
	var sentinel := "PF_SECRET_SENTINEL_DO_NOT_LEAK"
	var summary := _terminal_summary(
		[
			_slot(
				"slot-a",
				_error("provider_internal", false, "request-safe-12345678")
			)
		],
		"run-safe"
	)
	summary["prompt"] = "draw %s" % sentinel
	summary["headers"] = {"Authorization": sentinel}
	summary["raw_body"] = sentinel

	var first: Dictionary = presenter.present(summary)
	assert_true(first["show"])
	assert_eq(presenter.get_presented_count(), 1)
	var dialog: Window = presenter.get_dialog()
	assert_not_null(dialog)
	assert_true(dialog.visible)
	assert_not_null(dialog.find_child("GenerationErrorReason", true, false))
	assert_not_null(dialog.find_child("GenerationErrorAffectedCount", true, false))
	assert_not_null(dialog.find_child("GenerationErrorNextStep", true, false))
	assert_not_null(dialog.find_child("GenerationErrorPrimaryAction", true, false))
	assert_not_null(dialog.find_child("GenerationErrorClose", true, false))
	var technical_toggle := dialog.find_child("GenerationErrorTechnicalToggle", true, false)
	var technical_body := dialog.find_child("GenerationErrorTechnicalBody", true, false)
	assert_not_null(technical_toggle)
	assert_not_null(technical_body)
	assert_false(technical_body.visible, "technical details must be folded by default")
	var visible_surface: String = presenter.visible_text_for_test()
	assert_false(visible_surface.contains(sentinel))
	assert_false(visible_surface.contains("Authorization"))
	assert_false(visible_surface.contains("draw "))
	assert_false(visible_surface.contains("request-safe-12345678"))
	assert_true(visible_surface.contains("…5678"))

	var duplicate: Dictionary = presenter.present(summary)
	assert_false(duplicate["show"])
	assert_eq(duplicate["feedback"], "already_presented")
	assert_eq(presenter.get_presented_count(), 1)


func test_hidden_modes_never_open_a_window_and_cancel_failed_is_terminal() -> void:
	var presenter: Variant = await _new_presenter()
	if presenter == null:
		return
	for summary in [
		{"mode": "preflight_validation", "run_id": "preflight"},
		{"mode": "retry_in_progress", "run_id": "retrying"},
		{"mode": "user_canceled", "run_id": "canceled", "cancel_failed": false},
		{
			"mode": "startup_recovery",
			"run_id": "recovered",
			"failed_slots": [_slot("slot-r", _error("interrupted", true))],
		},
	]:
		var hidden: Dictionary = presenter.present(summary)
		assert_false(hidden["show"], String(summary["mode"]))
		assert_false(presenter.get_dialog().visible, String(summary["mode"]))
	assert_eq(presenter.get_presented_count(), 0)

	var cancel_failed := _terminal_summary(
		[_slot("slot-c", _error("cancel_failed", false))], "cancel-failed"
	)
	cancel_failed["mode"] = "user_canceled"
	cancel_failed["cancel_failed"] = true
	assert_true(presenter.present(cancel_failed)["show"])
	assert_eq(presenter.get_presented_count(), 1)


func test_primary_action_emits_only_safe_routing_context() -> void:
	var presenter: Variant = await _new_presenter()
	if presenter == null:
		return
	var routed := []
	presenter.action_requested.connect(
		func(run_id: String, action_id: String, context: Dictionary) -> void:
			routed.append({"run_id": run_id, "action_id": action_id, "context": context})
	)
	var summary := _terminal_summary(
		[
			_slot("slot-retry", _error("result_count_mismatch", true)),
			_slot("slot-fixed", _error("content_policy", false)),
		],
		"partial-action"
	)
	summary["succeeded_count"] = 6
	assert_true(presenter.present(summary)["show"])
	var primary_button: Button = presenter.get_dialog().find_child(
		"GenerationErrorPrimaryAction", true, false
	)
	primary_button.pressed.emit()
	assert_eq(routed.size(), 1)
	assert_eq(routed[0]["run_id"], "partial-action")
	assert_eq(routed[0]["action_id"], "retry_failed")
	assert_eq(routed[0]["context"].keys(), ["requires_confirmation", "retry_slot_ids"])
	assert_eq(routed[0]["context"]["retry_slot_ids"], PackedStringArray(["slot-retry"]))
	assert_false(JSON.stringify(routed).contains("content_policy"))


func test_rate_limit_and_network_dialog_actions_close_instead_of_retrying() -> void:
	var presenter: Variant = await _new_presenter()
	if presenter == null:
		return
	for code in ["rate_limited", "network"]:
		var decision: Dictionary = presenter.present(
			_terminal_summary([_slot("slot-%s" % code, _error(code, true))], "run-%s" % code)
		)
		assert_true(decision["show"], code)
		assert_eq(decision["model"]["primary_action_id"], "close", code)
		if code == "rate_limited":
			assert_true(presenter.visible_text_for_test().contains("30"))


func test_visible_dialog_rerenders_en_zh_en_without_changing_safe_model() -> void:
	var presenter: Variant = await _new_presenter()
	if presenter == null:
		return
	assert_true(
		presenter.present(
			_terminal_summary([_slot("slot-auth", _error("auth_failed", false))], "locale")
		)["show"]
	)
	var dialog: Window = presenter.get_dialog()
	var english_title := dialog.title
	var english_surface: String = presenter.visible_text_for_test()
	var safe_model: Dictionary = presenter.get_active_model_for_test()

	LocalizationService.set_language("zh_CN")
	await get_tree().process_frame
	var chinese_title := dialog.title
	var chinese_surface: String = presenter.visible_text_for_test()
	assert_ne(english_title, chinese_title)
	assert_ne(english_surface, chinese_surface)
	assert_eq(presenter.get_active_model_for_test(), safe_model)
	assert_true(dialog.visible)

	LocalizationService.set_language("en")
	await get_tree().process_frame
	assert_eq(dialog.title, english_title)
	assert_eq(presenter.visible_text_for_test(), english_surface)
	assert_eq(presenter.get_active_model_for_test(), safe_model)


func _new_presenter() -> Variant:
	assert_true(
		FileAccess.file_exists(PRESENTER_PATH),
		"real generation error dialog presenter is missing"
	)
	if not FileAccess.file_exists(PRESENTER_PATH):
		return null
	var presenter: Node = load(PRESENTER_PATH).new()
	add_child_autofree(presenter)
	await get_tree().process_frame
	return presenter


func _terminal_summary(failed_slots: Array, run_id: String) -> Dictionary:
	return {
		"mode": "terminal",
		"run_id": run_id,
		"settled": true,
		"succeeded_count": 0,
		"failed_slots": failed_slots,
		"terminal_steps": TERMINAL_STEPS.duplicate(),
	}


func _slot(slot_id: String, error: Dictionary) -> Dictionary:
	return {"slot_id": slot_id, "status": "failed", "error": error}


func _error(code: String, retryable: bool, request_id: String = "request-12345678") -> Dictionary:
	return {
		"code": code,
		"stage": "provider",
		"provider_id": "retrodiffusion",
		"retryable": retryable,
		"retry_after_seconds": 30.0 if code == "rate_limited" else null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
