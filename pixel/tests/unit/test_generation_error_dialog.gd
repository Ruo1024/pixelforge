extends "res://addons/gut/test.gd"

const POLICY_PATH := "res://services/generation_error_dialog_policy.gd"
const Catalog := preload("res://infra/localization_catalog.gd")
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const TERMINAL_STEPS := [
	"edge_stopped",
	"successes_saved",
	"failed_slots_updated",
	"safe_errors_recorded",
	"dialog_ready",
]


func test_at_most_one_per_run() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var summary := _terminal_summary([_slot("slot-1", _error("provider_internal", false))])
	assert_true(bool(policy.evaluate(summary)["show"]))
	assert_false(bool(policy.evaluate(summary)["show"]))
	assert_true(bool(policy.evaluate(_terminal_summary([_slot("slot-2", _error("network", true))], "run-2"))["show"]))


func test_no_dialog_preflight_retrying_cancel_or_recovery() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var cases := [
		{"mode": "preflight_validation", "run_id": "preflight"},
		{"mode": "retry_in_progress", "run_id": "retrying"},
		{"mode": "user_canceled", "run_id": "canceled", "cancel_failed": false},
		{
			"mode": "startup_recovery",
			"run_id": "recovered",
			"failed_slots": [_slot("slot-r", _error("interrupted", true))],
		},
	]
	for summary in cases:
		var decision: Dictionary = policy.evaluate(summary)
		assert_false(bool(decision["show"]), String(summary["mode"]))
		assert_ne(String(decision["feedback"]), "")


func test_update_order_before_dialog() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var invalid := _terminal_summary([_slot("slot-1", _error("timeout", false))])
	invalid["terminal_steps"] = TERMINAL_STEPS.duplicate()
	invalid["terminal_steps"].swap(0, 1)
	var rejected: Dictionary = policy.evaluate(invalid)
	assert_false(bool(rejected["show"]))
	assert_eq(rejected["feedback"], "invalid_terminal_sequence")
	var accepted: Dictionary = policy.evaluate(
		_terminal_summary([_slot("slot-2", _error("timeout", false))], "ordered-run")
	)
	assert_true(bool(accepted["show"]))


func test_partial_summary_and_retryable_rules() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var pending := _terminal_summary(
		[
			_slot("slot-retry", _error("network", true)),
			_slot("slot-fixed", _error("content_policy", false)),
		],
		"partial-pending"
	)
	pending["succeeded_count"] = 6
	pending["settled"] = false
	assert_false(bool(policy.evaluate(pending)["show"]))
	pending["run_id"] = "partial-settled"
	pending["settled"] = true
	var decision: Dictionary = policy.evaluate(pending)
	assert_true(bool(decision["show"]))
	assert_eq(decision["model"]["succeeded_count"], 6)
	assert_eq(decision["model"]["affected_count"], 2)
	assert_eq(decision["model"]["retry_slot_ids"], PackedStringArray(["slot-retry"]))
	assert_eq(decision["model"]["primary_action_id"], "retry_failed")


func test_error_action_matrix_and_priority() -> void:
	var policy_script: Variant = _load_policy()
	if policy_script == null:
		return
	var exact_actions := {
		"auth_failed": "open_provider_settings",
		"rate_limited": "retry_failed",
		"quota_exceeded": "open_provider_settings",
		"invalid_request": "return_generation_card",
		"network": "retry_failed",
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
	for code in exact_actions:
		assert_eq(policy_script.action_for_code(code), exact_actions[code], code)
	var policy: Variant = policy_script.new()
	var errors := [
		_slot("internal", _error("provider_internal", false)),
		_slot("invalid", _error("invalid_request", false)),
		_slot("policy", _error("content_policy", false)),
		_slot("auth", _error("auth_failed", false)),
	]
	assert_eq(
		policy.evaluate(_terminal_summary(errors, "priority"))["model"]["primary_action_id"],
		"open_provider_settings"
	)


func test_every_pferror_code_has_static_en_zh() -> void:
	var policy_script: Variant = _load_policy()
	if policy_script == null:
		return
	var english := Catalog.load_catalog("en")
	var chinese := Catalog.load_catalog("zh_CN")
	assert_eq(policy_script.ERROR_CODES, ContractV2.ERROR_CODES)
	for code in ContractV2.ERROR_CODES:
		var keys: Dictionary = policy_script.translation_keys_for_code(code)
		assert_eq(keys.keys().size(), 2, code)
		for key in keys.values():
			assert_true(english.has(key), "%s missing en %s" % [code, key])
			assert_true(chinese.has(key), "%s missing zh_CN %s" % [code, key])
			assert_ne(english.get(key, ""), "", code)
			assert_ne(chinese.get(key, ""), "", code)


func test_exact_content_and_technical_allowlist() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var decision: Dictionary = policy.evaluate(
		_terminal_summary([_slot("slot-1", _error("provider_internal", false))], "content")
	)
	var rendered: Dictionary = policy.render(decision["model"], "en")
	var keys := rendered.keys()
	keys.sort()
	assert_eq(
		keys,
		[
			"affected_count",
			"close",
			"next_step",
			"primary_action",
			"reason",
			"technical_details",
			"title",
		]
	)
	var detail_keys: Array = rendered["technical_details"].keys()
	detail_keys.sort()
	assert_eq(detail_keys, ["codes", "providers", "request_ids"])


func test_dialog_never_contains_sensitive_payload() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var sentinel := "PF_SECRET_SENTINEL_DO_NOT_LEAK"
	var unsafe_error := _error("provider_internal", false)
	unsafe_error["request_id"] = "request-safe-12345678"
	var summary := _terminal_summary([_slot("slot-1", unsafe_error)], "safe-surface")
	summary["prompt"] = "draw %s" % sentinel
	summary["headers"] = {"Authorization": sentinel}
	summary["raw_body"] = "raw %s" % sentinel
	summary["provider_names"] = {"retrodiffusion": "RetroDiffusion %s" % sentinel}
	summary["image"] = sentinel.to_utf8_buffer()
	var decision: Dictionary = policy.evaluate(summary)
	assert_true(bool(decision["show"]))
	var serialized := JSON.stringify(decision)
	assert_false(serialized.contains(sentinel))
	assert_false(serialized.contains("Authorization"))
	assert_false(serialized.contains("draw "))
	assert_false(serialized.contains("raw "))
	assert_false(serialized.contains("request-safe-12345678"))
	assert_true(serialized.contains("…5678"))


func test_runtime_en_zh_en_rerenders_same_safe_model() -> void:
	var policy: Variant = _new_policy()
	if policy == null:
		return
	var decision: Dictionary = policy.evaluate(
		_terminal_summary([_slot("slot-1", _error("auth_failed", false))], "locale")
	)
	var english_first: Dictionary = policy.render(decision["model"], "en")
	var chinese: Dictionary = policy.render(decision["model"], "zh_CN")
	var english_second: Dictionary = policy.render(decision["model"], "en")
	assert_eq(english_first, english_second)
	assert_ne(english_first["title"], chinese["title"])
	assert_ne(english_first["reason"], chinese["reason"])
	assert_eq(english_first["technical_details"], chinese["technical_details"])


func _new_policy() -> Variant:
	var policy_script: Variant = _load_policy()
	return policy_script.new() if policy_script != null else null


func _load_policy() -> Variant:
	assert_true(FileAccess.file_exists(POLICY_PATH), "B7-4 error dialog policy is missing")
	if not FileAccess.file_exists(POLICY_PATH):
		return null
	return load(POLICY_PATH)


func _terminal_summary(
	failed_slots: Array, run_id: String = "run-1", mode: String = "terminal"
) -> Dictionary:
	return {
		"mode": mode,
		"run_id": run_id,
		"settled": true,
		"succeeded_count": 0,
		"failed_slots": failed_slots,
		"terminal_steps": TERMINAL_STEPS.duplicate(),
		"provider_names": {"retrodiffusion": "RetroDiffusion"},
	}


func _slot(slot_id: String, error: Dictionary) -> Dictionary:
	return {"slot_id": slot_id, "status": "failed", "error": error}


func _error(code: String, retryable: bool) -> Dictionary:
	return {
		"code": code,
		"stage": "provider",
		"provider_id": "retrodiffusion",
		"retryable": retryable,
		"retry_after_seconds": 30.0 if code == "rate_limited" else null,
		"status_code": null,
		"request_id": "request-12345678",
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
