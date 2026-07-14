class_name PFGenerationErrorDialogPolicy
extends RefCounted

## Builds a safe, locale-independent terminal error model for the UI to render.
## The run coordinator remains responsible for state changes and the actual dialog.

const Catalog := preload("res://infra/localization_catalog.gd")
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

const ERROR_CODES := ContractV2.ERROR_CODES
const TERMINAL_STEPS := [
	"edge_stopped",
	"successes_saved",
	"failed_slots_updated",
	"safe_errors_recorded",
	"dialog_ready",
]
const NO_DIALOG_MODES := {
	"preflight_validation": "inline_validation",
	"retry_in_progress": "running_feedback",
	"user_canceled": "canceled_without_error",
	"startup_recovery": "interrupted_slots",
}
const CODE_ACTIONS := {
	"auth_failed": "open_provider_settings",
	"rate_limited": "close",
	"quota_exceeded": "open_provider_settings",
	"invalid_request": "return_generation_card",
	"network": "close",
	"timeout": "regenerate_confirm",
	"content_policy": "edit_prompt",
	"provider_internal": "close",
	"cancel_failed": "close",
	"ambiguous_result": "regenerate_confirm",
	"malformed_response": "retry_failed",
	"result_count_mismatch": "retry_failed",
	"interrupted": "retry_failed",
	"cleanup_failed": "adjust_cleanup",
}
const ACTION_KEYS := {
	"retry_failed": "GEN_ERROR_ACTION_RETRY_FAILED",
	"open_provider_settings": "GEN_ERROR_ACTION_PROVIDER_SETTINGS",
	"edit_prompt": "GEN_ERROR_ACTION_EDIT_PROMPT",
	"return_generation_card": "GEN_ERROR_ACTION_RETURN_CARD",
	"regenerate_confirm": "GEN_ERROR_ACTION_REGENERATE_CONFIRM",
	"adjust_cleanup": "GEN_ERROR_ACTION_ADJUST_CLEANUP",
	"close": "GEN_ERROR_ACTION_CLOSE",
}
const NON_RETRYABLE_PRIORITY := [
	"auth_failed",
	"quota_exceeded",
	"content_policy",
	"invalid_request",
	"timeout",
	"ambiguous_result",
	"cancel_failed",
	"provider_internal",
	"cleanup_failed",
]
const KNOWN_PROVIDER_NAMES := {
	"openai": "OpenAI Image",
	"openai_image": "OpenAI Image",
	"retrodiffusion": "RetroDiffusion",
}
const SAFE_REQUEST_PATTERN := "^[A-Za-z0-9._:-]{4,128}$"

var _presented_runs: Dictionary = {}


func evaluate(summary: Dictionary) -> Dictionary:
	var mode := String(summary.get("mode", ""))
	if NO_DIALOG_MODES.has(mode):
		if mode != "user_canceled" or not bool(summary.get("cancel_failed", false)):
			return _hidden(String(NO_DIALOG_MODES[mode]))
		mode = "terminal"
	var run_id := String(summary.get("run_id", ""))
	var entry_feedback := _entry_feedback(mode, run_id)
	if not entry_feedback.is_empty():
		return _hidden(entry_feedback)
	var terminal_feedback := _terminal_feedback(summary)
	if not terminal_feedback.is_empty():
		return _hidden(terminal_feedback)
	var normalized := _normalize_failed_slots(summary.get("failed_slots", []))
	if not bool(normalized.get("ok", false)):
		return _hidden(String(normalized.get("feedback", "invalid_failed_slots")))
	var failures: Array = normalized["failures"]
	if failures.is_empty():
		return _hidden("no_execution_failure")
	var retry_slot_ids := PackedStringArray()
	for failure_value in failures:
		var failure: Dictionary = failure_value
		if _dialog_retry_allowed(failure):
			retry_slot_ids.append(String(failure["slot_id"]))
	var primary_code := _select_primary_code(failures, not retry_slot_ids.is_empty())
	var primary_action := (
		"retry_failed" if not retry_slot_ids.is_empty() else action_for_code(primary_code)
	)
	var model := {
		"affected_count": failures.size(),
		"codes": _unique_strings(failures, "code"),
		"primary_action_id": primary_action,
		"providers": _safe_providers(failures),
		"reason_code": primary_code,
		"request_ids": _safe_request_ids(failures),
		"retry_after_seconds": _retry_after_for_code(failures, primary_code),
		"retry_slot_ids": retry_slot_ids,
		"succeeded_count": maxi(0, int(summary.get("succeeded_count", 0))),
	}
	_presented_runs[run_id] = true
	return {"feedback": "dialog_ready", "model": model, "show": true}


func _entry_feedback(mode: String, run_id: String) -> String:
	if mode != "terminal" or run_id.is_empty():
		return "invalid_terminal_summary"
	if _presented_runs.has(run_id):
		return "already_presented"
	return ""


func _terminal_feedback(summary: Dictionary) -> String:
	if not bool(summary.get("settled", false)):
		return "requests_pending"
	if not _same_sequence(summary.get("terminal_steps", []), TERMINAL_STEPS):
		return "invalid_terminal_sequence"
	return ""


func render(model: Dictionary, locale: String) -> Dictionary:
	var catalog := Catalog.load_catalog(locale if locale in ["en", "zh_CN"] else "en")
	var code := String(model.get("reason_code", "provider_internal"))
	var text_keys := translation_keys_for_code(code)
	var succeeded_count := maxi(0, int(model.get("succeeded_count", 0)))
	var affected_count := maxi(0, int(model.get("affected_count", 0)))
	var reason := String(catalog.get(text_keys["reason"], text_keys["reason"]))
	var next_step := String(catalog.get(text_keys["next_step"], text_keys["next_step"]))
	if code == "rate_limited" and model.get("retry_after_seconds") != null:
		next_step = (
			String(catalog.get("GEN_ERROR_RATE_LIMITED_NEXT_WITH_SECONDS_FORMAT", ""))
			% _seconds_text(float(model["retry_after_seconds"]))
		)
	if succeeded_count > 0:
		reason = (
			String(catalog.get("GEN_ERROR_PARTIAL_REASON_FORMAT", ""))
			% [succeeded_count, affected_count]
		)
	var action_id := String(model.get("primary_action_id", "close"))
	var action_key := String(ACTION_KEYS.get(action_id, ACTION_KEYS["close"]))
	return {
		"title":
		String(
			catalog.get(
				"GEN_ERROR_TITLE_PARTIAL" if succeeded_count > 0 else "GEN_ERROR_TITLE_FAILED", ""
			)
		),
		"reason": reason,
		"affected_count": affected_count,
		"next_step": next_step,
		"primary_action":
		{
			"id": action_id,
			"label": String(catalog.get(action_key, action_key)),
			"requires_confirmation": action_id == "regenerate_confirm",
		},
		"close": String(catalog.get("GEN_ERROR_ACTION_CLOSE", "GEN_ERROR_ACTION_CLOSE")),
		"technical_details":
		{
			"codes": model.get("codes", PackedStringArray()),
			"providers": model.get("providers", PackedStringArray()),
			"request_ids": model.get("request_ids", PackedStringArray()),
		},
	}


static func action_for_code(code: String) -> String:
	return String(CODE_ACTIONS.get(code, "close"))


static func translation_keys_for_code(code: String) -> Dictionary:
	if not code in ERROR_CODES:
		return {}
	var prefix := "GEN_ERROR_%s" % code.to_upper()
	return {"reason": "%s_REASON" % prefix, "next_step": "%s_NEXT" % prefix}


func _normalize_failed_slots(value: Variant) -> Dictionary:
	if not (value is Array):
		return {"feedback": "invalid_failed_slots", "ok": false}
	var failures: Array = []
	var seen_slot_ids := {}
	for slot_value in value:
		if not (slot_value is Dictionary):
			return {"feedback": "invalid_failed_slot", "ok": false}
		var slot: Dictionary = slot_value
		var slot_id := String(slot.get("slot_id", ""))
		var error_value: Variant = slot.get("error")
		if (
			String(slot.get("status", "")) != "failed"
			or slot_id.is_empty()
			or seen_slot_ids.has(slot_id)
			or not (error_value is Dictionary)
		):
			return {"feedback": "invalid_failed_slot", "ok": false}
		var error: Dictionary = error_value
		if ContractV2.validate_pf_error(error) != null:
			return {"feedback": "invalid_error_shape", "ok": false}
		seen_slot_ids[slot_id] = true
		(
			failures
			. append(
				{
					"code": String(error["code"]),
					"provider_id": String(error["provider_id"]),
					"request_id": String(error["request_id"]),
					"retry_after_seconds": error.get("retry_after_seconds"),
					"retryable": bool(error["retryable"]),
					"slot_id": slot_id,
				}
			)
		)
	return {"failures": failures, "ok": true}


func _dialog_retry_allowed(failure: Dictionary) -> bool:
	return (
		bool(failure.get("retryable", false))
		and action_for_code(String(failure.get("code", ""))) == "retry_failed"
	)


func _retry_after_for_code(failures: Array, code: String) -> Variant:
	var result: Variant = null
	for failure_value in failures:
		var failure: Dictionary = failure_value
		if String(failure.get("code", "")) != code:
			continue
		var value: Variant = failure.get("retry_after_seconds")
		if value is float or value is int:
			result = maxf(float(result) if result != null else 0.0, float(value))
	return result


func _seconds_text(value: float) -> String:
	return (
		String.num_int64(roundi(value))
		if is_equal_approx(value, roundf(value))
		else String.num(value, 2)
	)


func _select_primary_code(failures: Array, has_retryable: bool) -> String:
	if has_retryable:
		for failure_value in failures:
			var failure: Dictionary = failure_value
			if bool(failure["retryable"]):
				return String(failure["code"])
	for code in NON_RETRYABLE_PRIORITY:
		for failure_value in failures:
			var failure: Dictionary = failure_value
			if String(failure["code"]) == code:
				return code
	return String(failures[0]["code"])


func _safe_providers(failures: Array) -> PackedStringArray:
	var providers := PackedStringArray()
	for failure_value in failures:
		var provider_id := String(failure_value["provider_id"])
		var provider_name := String(KNOWN_PROVIDER_NAMES.get(provider_id, ""))
		if not provider_name.is_empty() and not providers.has(provider_name):
			providers.append(provider_name)
	return providers


func _safe_request_ids(failures: Array) -> PackedStringArray:
	var request_ids := PackedStringArray()
	var regex := RegEx.new()
	regex.compile(SAFE_REQUEST_PATTERN)
	for failure_value in failures:
		var request_id := String(failure_value["request_id"])
		if regex.search(request_id) == null:
			continue
		var redacted := "…%s" % request_id.right(4)
		if not request_ids.has(redacted):
			request_ids.append(redacted)
	return request_ids


func _unique_strings(values: Array, field: String) -> PackedStringArray:
	var unique := PackedStringArray()
	for value in values:
		var item := String(value[field])
		if not unique.has(item):
			unique.append(item)
	return unique


func _same_sequence(left_value: Variant, right: Array) -> bool:
	if not (left_value is Array):
		return false
	var left: Array = left_value
	if left.size() != right.size():
		return false
	for index in range(right.size()):
		if left[index] != right[index]:
			return false
	return true


func _hidden(feedback: String) -> Dictionary:
	return {"feedback": feedback, "model": {}, "show": false}
