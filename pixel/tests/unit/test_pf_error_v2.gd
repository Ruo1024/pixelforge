extends "res://addons/gut/test.gd"

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const PlannerScript := preload("res://services/generation_request_planner.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const AdapterScript := preload("res://services/legacy_generation_v2_adapter.gd")


func test_exact_safe_shape_and_retry_policy() -> void:
	var forbidden_retry := _error("auth_failed", false)
	assert_null(ContractV2.validate_pf_error(forbidden_retry))
	forbidden_retry["retryable"] = true
	var retry_issue: Variant = ContractV2.validate_pf_error(forbidden_retry)
	assert_not_null(retry_issue)
	if retry_issue != null:
		assert_eq(retry_issue["code"], "invalid_error_field")
	for field in ["message", "detail", "raw_body"]:
		var unsafe := _error("provider_internal", false)
		unsafe[field] = "provider text"
		assert_eq(ContractV2.validate_pf_error(unsafe)["code"], "unknown_error_field")
	for code in [
		"rate_limited", "network", "malformed_response", "result_count_mismatch", "interrupted"
	]:
		assert_null(ContractV2.validate_pf_error(_error(code, true)), code)
	for code in [
		"auth_failed",
		"quota_exceeded",
		"invalid_request",
		"content_policy",
		"timeout",
		"ambiguous_result",
		"provider_internal",
		"cancel_failed",
		"cleanup_failed",
	]:
		assert_null(ContractV2.validate_pf_error(_error(code, false)), code)
	var range_error := _error("rate_limited", true)
	range_error["retry_after_seconds"] = 86400.0
	range_error["status_code"] = 429
	range_error["provider_code"] = "rate_limit-1"
	assert_null(ContractV2.validate_pf_error(range_error))
	for invalid_retry_after in [-1, 86401, INF, "30"]:
		var invalid := range_error.duplicate(true)
		invalid["retry_after_seconds"] = invalid_retry_after
		assert_not_null(ContractV2.validate_pf_error(invalid))
	for invalid_status in [99, 600, 429.0, "429"]:
		var invalid := range_error.duplicate(true)
		invalid["status_code"] = invalid_status
		assert_not_null(ContractV2.validate_pf_error(invalid))
	for invalid_provider_code in ["", "spaces forbidden", "x".repeat(65)]:
		var invalid := range_error.duplicate(true)
		invalid["provider_code"] = invalid_provider_code
		assert_not_null(ContractV2.validate_pf_error(invalid))


func test_all_stages_enforce_attempt_ranges() -> void:
	for stage in ContractV2.ERROR_STAGES:
		var error := _error("provider_internal", false)
		error["stage"] = stage
		error["attempts"] = 0 if stage == "queue" else 1
		assert_null(ContractV2.validate_pf_error(error), stage)
		error["attempts"] = 1 if stage == "queue" else 0
		assert_eq(ContractV2.validate_pf_error(error)["code"], "invalid_error_field")


func test_nonexecution_errors_have_no_attempts_or_message() -> void:
	var validation: Dictionary = PlannerScript.plan({}, [])["issue"]
	var load_error: Dictionary = GraphScript._load_error("invalid_graph_shape", "graph")
	var command_error: Dictionary = (
		AdapterScript
		. new()
		. materialize_provider_mapping("graph", "generate", {}, {}, {}, null)["error"]
	)
	var issues := [validation, load_error, command_error]
	for issue_value in issues:
		assert_true(issue_value is Dictionary)
		var issue: Dictionary = issue_value
		assert_true(issue.has("code"))
		assert_true(issue.has("args"))
		assert_false(issue.has("attempts"))
		assert_false(issue.has("message"))


func _error(code: String, retryable: bool) -> Dictionary:
	return {
		"code": code,
		"stage": "provider",
		"provider_id": "retrodiffusion",
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": "request-error",
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
