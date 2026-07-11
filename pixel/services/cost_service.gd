class_name PFCostService
extends Node

## Provider spend ledger and preflight budget policy, persisted by provider/month buckets.

signal cost_changed(month_key: String, total: float)
signal budget_changed(limit: float)

const UNKNOWN_COST := -1.0
const BUDGET_SECTION := "provider_budget"
const LEDGER_SECTION_PREFIX := "provider_cost_"


func get_month_key(unix_time: int = -1) -> String:
	var timestamp := int(Time.get_unix_time_from_system()) if unix_time < 0 else unix_time
	var parts := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d" % [int(parts["year"]), int(parts["month"])]


func record_cost(provider_id: String, cost: float, month_key: String = "") -> bool:
	if provider_id.is_empty() or cost < 0.0:
		return false
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	var section := _ledger_section(bucket)
	var provider_total := float(SettingsService.get_setting(section, provider_id, 0.0)) + cost
	var month_total := float(SettingsService.get_setting(section, "total", 0.0)) + cost
	SettingsService.set_setting(section, provider_id, provider_total, false)
	SettingsService.set_setting(section, "total", month_total)
	cost_changed.emit(bucket, month_total)
	return true


func get_month_total(month_key: String = "") -> float:
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	return float(SettingsService.get_setting(_ledger_section(bucket), "total", 0.0))


func get_provider_total(provider_id: String, month_key: String = "") -> float:
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	return float(SettingsService.get_setting(_ledger_section(bucket), provider_id, 0.0))


func set_monthly_budget(limit: float) -> void:
	var normalized := maxf(0.0, limit)
	SettingsService.set_setting(BUDGET_SECTION, "monthly_usd", normalized)
	budget_changed.emit(normalized)


func get_monthly_budget() -> float:
	return maxf(0.0, float(SettingsService.get_setting(BUDGET_SECTION, "monthly_usd", 0.0)))


func estimate_request(provider_id: String, request: Dictionary) -> float:
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	return estimate_with_provider(provider, request)


func estimate_with_provider(provider: PFProvider, request: Dictionary) -> float:
	if provider == null:
		return UNKNOWN_COST
	return float(provider.estimate_cost(request))


func requires_confirmation(estimate: float) -> bool:
	var limit := get_monthly_budget()
	return limit > 0.0 and estimate >= 0.0 and get_month_total() + estimate > limit


func format_month_total() -> String:
	return "This month: $%.2f" % get_month_total()


func reset_month_for_tests(month_key: String) -> void:
	SettingsService.set_setting(_ledger_section(month_key), "total", 0.0, false)


func _ledger_section(month_key: String) -> String:
	return "%s%s" % [LEDGER_SECTION_PREFIX, month_key]
