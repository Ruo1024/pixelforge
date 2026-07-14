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
	SettingsService.set_setting("provider_cost_%s" % TEST_MONTH, "fixture_provider", 0.0, false)
	_service.set_monthly_budget(0.0)


func after_each() -> void:
	_service.set_monthly_budget(0.0)


func test_mock_estimate_and_actual_month_ledger_are_exact() -> void:
	var provider: PFProvider = FakeProviderScript.new()
	var estimate := _service.estimate_with_provider(provider, {"batch": 4})
	assert_eq(estimate, 1.0)
	assert_true(_service.record_cost(FakeProviderScript.PROVIDER_ID, 1.0, TEST_MONTH))
	assert_eq(_service.get_month_total(TEST_MONTH), 1.0)
	assert_eq(_service.get_provider_total(FakeProviderScript.PROVIDER_ID, TEST_MONTH), 1.0)


func test_budget_requires_confirmation_only_for_known_overage() -> void:
	_service.set_monthly_budget(0.5)
	assert_false(_service.requires_confirmation(-1.0))
	assert_false(_service.requires_confirmation(0.5))
	assert_true(_service.requires_confirmation(0.51))
	_service.set_monthly_budget(0.0)
	assert_false(_service.requires_confirmation(100.0))


func test_negative_unknown_cost_is_never_recorded() -> void:
	assert_false(_service.record_cost("fixture_provider", -1.0, TEST_MONTH))
	assert_eq(_service.get_month_total(TEST_MONTH), 0.0)
