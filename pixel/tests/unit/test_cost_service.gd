extends "res://addons/gut/test.gd"

const CostServiceScript := preload("res://services/cost_service.gd")
const FakeProviderScript := preload("res://tests/fixtures/providers/fake_provider.gd")

const TEST_MONTH := "2099-12"

var _service: PFCostService


func before_each() -> void:
	_service = CostServiceScript.new()
	add_child_autofree(_service)
	_service.reset_month_for_tests(TEST_MONTH)
	_service.reset_month_for_tests(_service.get_month_key())
	_service.set_monthly_budget_micro_usd(0)


func after_each() -> void:
	_service.set_monthly_budget_micro_usd(0)


func test_mock_estimate_and_actual_month_ledger_are_exact() -> void:
	var provider: PFProvider = FakeProviderScript.new()
	var preflight: Dictionary = _service.preflight_with_providers(
		[_request("estimate", 4)], {FakeProviderScript.PROVIDER_ID: provider}, TEST_MONTH
	)
	assert_eq(preflight["estimated_total_micro_usd"], 1000000)
	assert_eq(preflight["estimated_total_usd"], "1.000000")
	assert_true(_service.record_once("fixture_provider:request:estimate", 1000000, TEST_MONTH))
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 1000000)


func test_budget_requires_confirmation_only_for_known_overage() -> void:
	var provider: PFProvider = FakeProviderScript.new()
	var provider_map := {FakeProviderScript.PROVIDER_ID: provider}
	_service.set_monthly_budget_micro_usd(500000)
	assert_eq(
		(
			_service
			. preflight_with_providers([_request("equal", 2)], provider_map, TEST_MONTH)["decision"]
		),
		"allowed"
	)
	assert_eq(
		(
			_service
			. preflight_with_providers([_request("over", 3)], provider_map, TEST_MONTH)["decision"]
		),
		"needs_confirmation"
	)
	_service.set_monthly_budget_micro_usd(0)
	assert_eq(
		(
			_service
			. preflight_with_providers([_request("unlimited", 4)], provider_map, TEST_MONTH)["decision"]
		),
		"allowed"
	)


func test_negative_unknown_cost_is_never_recorded() -> void:
	assert_false(_service.record_once("fixture_provider:request:negative", -1, TEST_MONTH))
	assert_eq(_service.get_month_total_micro_usd(TEST_MONTH), 0)


func _request(request_id: String, batch: int) -> Dictionary:
	return {
		"request_id": request_id,
		"provider_id": FakeProviderScript.PROVIDER_ID,
		"model_id": FakeProviderScript.MODEL_ID,
		"batch": batch,
	}
