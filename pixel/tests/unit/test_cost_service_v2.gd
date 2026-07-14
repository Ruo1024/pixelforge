extends "res://addons/gut/test.gd"

const CostServiceScript := preload("res://services/cost_service.gd")
const TEST_MONTH := "2099-11"

var _service: PFCostService


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
	assert_null(_service.parse_usd_to_micro(0.1))
	assert_null(_service.parse_usd_to_micro("1e-1"))
	assert_true(_service.record_once("retrodiffusion:request:req-1", 300000, TEST_MONTH))
	assert_false(_service.record_once("retrodiffusion:request:req-1", 300000, TEST_MONTH))
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 300000)


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
	assert_eq(unknown["reason_code"], "unknown_estimate")
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 0)


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
