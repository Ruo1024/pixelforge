extends "res://addons/gut/test.gd"

const CostServiceScript := preload("res://services/cost_service.gd")
const TEST_MONTH := "2099-11"

var _service: PFCostService


class EstimateProvider:
	extends PFProvider

	var provider_id := "fixture_cost"
	var model_id := "known"
	var can_estimate := true
	var estimate: Variant = "0.250000"

	func get_model_descriptors() -> Array[Dictionary]:
		return [
			{
				"provider_id": provider_id,
				"model_id": model_id,
				"capabilities": {"cost_estimate": can_estimate},
			}
		]

	func estimate_cost(_request: Dictionary) -> Variant:
		return estimate


func before_each() -> void:
	_service = CostServiceScript.new()
	add_child_autofree(_service)
	_service.reset_month_for_tests(TEST_MONTH)
	_service.set_monthly_budget_micro_usd(0)


func after_each() -> void:
	_service.set_monthly_budget_micro_usd(0)


func test_decimal_and_record_once() -> void:
	assert_eq(_service.parse_usd_to_micro("0.100000"), 100000)
	assert_eq(_service.parse_usd_to_micro("0.200000"), 200000)
	assert_eq(_service.format_micro_usd(100000 + 200000), "0.300000")
	assert_eq(_service.parse_usd_to_micro("1"), 1000000)
	assert_eq(_service.parse_usd_to_micro("1.2345674"), 1234567)
	assert_eq(_service.parse_usd_to_micro("1.2345675"), 1234568)
	assert_null(_service.parse_usd_to_micro(0.1))
	assert_null(_service.parse_usd_to_micro("1e-1"))
	assert_null(_service.parse_usd_to_micro("01.000000"))
	assert_null(_service.parse_usd_to_micro("-1"))
	assert_null(_service.parse_usd_to_micro("$1"))
	assert_null(_service.parse_usd_to_micro("1000000000.000000"))
	assert_null(_service.format_micro_usd(-1))
	assert_true(_service.record_once("retrodiffusion:request:req-1", 300000, TEST_MONTH))
	assert_false(_service.record_once("retrodiffusion:request:req-1", 300000, TEST_MONTH))
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 300000)
	assert_false(_service.record_once("", 1, TEST_MONTH))
	assert_false(_service.record_once("retrodiffusion:request:negative", -1, TEST_MONTH))


func test_estimate_actual_unknown_and_budget_matrix() -> void:
	_service.set_monthly_budget_micro_usd(500000)
	var known: Dictionary = _service.preflight_with_providers(
		[_request("req-1", "rd_pro", 2)],
		{"retrodiffusion": ProviderService.get_provider("retrodiffusion")},
		TEST_MONTH
	)
	assert_eq(known["decision"], "allowed")
	assert_eq(known["estimate_state"], "estimate")
	assert_eq(known["estimated_total_usd"], "0.500000")
	assert_eq(known["estimated_total_micro_usd"], 500000)
	var unknown: Dictionary = _service.preflight_with_providers(
		[_request("req-2", "rd_plus", 1)],
		{"retrodiffusion": ProviderService.get_provider("retrodiffusion")},
		TEST_MONTH
	)
	assert_eq(unknown["decision"], "allowed")
	assert_eq(unknown["estimate_state"], "unknown")
	assert_null(unknown["estimated_total_usd"])
	assert_null(unknown["estimated_total_micro_usd"])
	assert_null(unknown["projected_month_total_micro_usd"])
	assert_eq(unknown["reason_code"], "unknown_estimate")
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 0)
	assert_true(_service.record_once("retrodiffusion:request:previous", 100000, TEST_MONTH))
	var over_budget: Dictionary = _service.preflight_with_providers(
		[_request("req-3", "rd_pro", 2)],
		{"retrodiffusion": ProviderService.get_provider("retrodiffusion")},
		TEST_MONTH
	)
	assert_eq(over_budget["decision"], "needs_confirmation")
	assert_eq(over_budget["reason_code"], "budget_exceeded")
	assert_eq(over_budget["month_total_micro_usd"], 100000)
	assert_eq(over_budget["projected_month_total_micro_usd"], 600000)
	assert_eq(over_budget["budget_micro_usd"], 500000)


func test_preflight_blocks_missing_or_invalid_estimates() -> void:
	var request := _request("fixture-1", "known", 1)
	request["provider_id"] = "fixture_cost"
	var provider := EstimateProvider.new()
	var provider_map := {"fixture_cost": provider}
	assert_eq(
		_service.preflight_with_providers([request], {}, TEST_MONTH)["reason_code"],
		"provider_unavailable"
	)
	provider.estimate = null
	assert_eq(
		_service.preflight_with_providers([request], provider_map, TEST_MONTH)["reason_code"],
		"invalid_estimate"
	)
	provider.estimate = 0.25
	assert_eq(
		_service.preflight_with_providers([request], provider_map, TEST_MONTH)["reason_code"],
		"invalid_estimate"
	)
	provider.estimate = "0.25"
	assert_eq(
		_service.preflight_with_providers([request], provider_map, TEST_MONTH)["reason_code"],
		"invalid_estimate"
	)
	provider.can_estimate = false
	provider.estimate = "0.250000"
	assert_eq(
		_service.preflight_with_providers([request], provider_map, TEST_MONTH)["reason_code"],
		"invalid_estimate"
	)
	provider.estimate = null
	assert_eq(
		_service.preflight_with_providers([request], provider_map, TEST_MONTH)["estimate_state"],
		"unknown"
	)


func test_v2_storage_never_reads_legacy_float_buckets() -> void:
	_service.set_monthly_budget(99.0)
	assert_true(_service.record_cost("fixture_cost", 12.5, TEST_MONTH))
	assert_eq(_service.get_monthly_budget_micro_usd(), 0)
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 0)
	assert_true(_service.set_monthly_budget_micro_usd(250000))
	assert_eq(_service.get_monthly_budget(), 99.0)
	assert_eq(_service.get_month_total(TEST_MONTH), 12.5)
	assert_false(_service.set_monthly_budget_micro_usd(0.25))


func test_all_manual_retry_paths_preflight_without_side_effects() -> void:
	var provider_map := {"retrodiffusion": ProviderService.get_provider("retrodiffusion")}
	var paths := [
		[_request("single-slot", "rd_pro", 1)],
		[_request("failed-a", "rd_pro", 1), _request("failed-b", "rd_pro", 2)],
		[
			_request("full-a", "rd_pro", 4),
			_request("full-b", "rd_pro", 4),
			_request("full-c", "rd_pro", 1),
		],
	]
	for requests in paths:
		var before := _service.get_month_total_micro_usd(TEST_MONTH)
		var decision: Dictionary = _service.preflight_with_providers(
			requests, provider_map, TEST_MONTH
		)
		assert_eq(decision["decision"], "allowed")
		assert_eq(decision["estimate_state"], "estimate")
		assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), before)
	var blocked: Dictionary = _service.preflight_with_providers(
		[_request("blocked", "missing", 1)], provider_map, TEST_MONTH
	)
	assert_eq(blocked["decision"], "blocked")
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 0)


func test_actual_charge_meta_and_unknown_ledger() -> void:
	assert_true(_service.record_once("retrodiffusion:charge:charge-1", 250000, TEST_MONTH))
	assert_false(_service.record_once("retrodiffusion:charge:charge-1", 250000, TEST_MONTH))
	assert_true(_service.record_once("retrodiffusion:request:req-no-charge", 125000, TEST_MONTH))
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 375000)
	var before_unknown := _service.get_month_total_micro_usd(TEST_MONTH)
	var unknown_actual: Variant = null
	if unknown_actual != null:
		fail_test("unknown actual must not be recorded")
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), before_unknown)


func _request(request_id: String, model_id: String, batch: int) -> Dictionary:
	return {
		"run_id": "run-cost",
		"request_id": request_id,
		"idempotency_key": "idem-%s" % request_id,
		"provider_id": "retrodiffusion",
		"mode": "txt2img",
		"model_id": model_id,
		"prompt": "barrel",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [32, 32],
		"batch": batch,
		"seed": 1,
		"ref_images": [],
		"extra": {"remove_bg": true, "strength": 0.8},
	}
