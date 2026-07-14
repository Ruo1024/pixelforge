class_name PFCostService
extends Node

## Provider spend ledger and preflight budget policy.
## v2 amounts are persisted and calculated only as integer micro-USD.

signal cost_changed_v2(month_key: String, total_micro_usd: int)
signal budget_changed_v2(limit_micro_usd: int)

const UsdDecimalScript := preload("res://core/provider/pf_usd_decimal.gd")
const BUDGET_SECTION_V2 := "provider_budget_v2"
const LEDGER_SECTION_PREFIX_V2 := "provider_cost_v2_"
const MONTHLY_MICRO_USD_KEY := "monthly_micro_usd"
const TOTAL_MICRO_USD_KEY := "total_micro_usd"
const MICRO_USD_PER_USD := 1000000
const MAX_CANONICAL_MICRO_USD := 999999999999999
const MAX_INT64 := 9223372036854775807
const DECIMAL_PATTERN := "^(0|[1-9][0-9]{0,8})(?:[.]([0-9]+))?$"
const CANONICAL_USD_PATTERN := "^(0|[1-9][0-9]{0,8})[.][0-9]{6}$"


func get_month_key(unix_time: int = -1) -> String:
	var timestamp := int(Time.get_unix_time_from_system()) if unix_time < 0 else unix_time
	var parts := Time.get_datetime_dict_from_unix_time(timestamp)
	return "%04d-%02d" % [int(parts["year"]), int(parts["month"])]


func parse_usd_to_micro(value: Variant) -> Variant:
	return UsdDecimalScript.parse_to_micro(value)


func format_micro_usd(micro_usd: int) -> Variant:
	return UsdDecimalScript.format_micro(micro_usd)


func set_monthly_budget_micro_usd(limit: Variant) -> bool:
	if not (limit is int) or int(limit) < 0 or int(limit) > MAX_CANONICAL_MICRO_USD:
		return false
	SettingsService.set_setting(BUDGET_SECTION_V2, MONTHLY_MICRO_USD_KEY, int(limit))
	budget_changed_v2.emit(int(limit))
	return true


func get_monthly_budget_micro_usd() -> int:
	var stored: Variant = SettingsService.get_setting(BUDGET_SECTION_V2, MONTHLY_MICRO_USD_KEY, 0)
	return int(stored) if stored is int and int(stored) >= 0 else 0


func get_month_total_micro_usd(month_key: String = "") -> int:
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	var stored: Variant = SettingsService.get_setting(
		_ledger_section_v2(bucket), TOTAL_MICRO_USD_KEY, 0
	)
	return int(stored) if stored is int and int(stored) >= 0 else 0


func record_once(key: String, micro_usd: int, month_key: String = "") -> bool:
	if key.strip_edges().is_empty() or micro_usd < 0 or micro_usd > MAX_CANONICAL_MICRO_USD:
		return false
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	var section := _ledger_section_v2(bucket)
	var entry_key := "entry_%s" % key.sha256_text()
	if SettingsService._config.has_section_key(section, entry_key):
		return false
	var total_value: Variant = SettingsService.get_setting(section, TOTAL_MICRO_USD_KEY, 0)
	if not (total_value is int) or int(total_value) < 0:
		return false
	var total := int(total_value)
	if total > MAX_INT64 - micro_usd:
		return false
	var updated_total := total + micro_usd
	# Dedupe entries also store integers, so every v2 ledger value remains int64-only.
	SettingsService.set_setting(section, entry_key, micro_usd, false)
	SettingsService.set_setting(section, TOTAL_MICRO_USD_KEY, updated_total)
	cost_changed_v2.emit(bucket, updated_total)
	return true


func preflight(requests: Array, month_key: String = "") -> Dictionary:
	var providers := {}
	for request_value in requests:
		if not (request_value is Dictionary):
			continue
		var provider_id := String(request_value.get("provider_id", ""))
		if not providers.has(provider_id):
			providers[provider_id] = ProviderService.get_provider(provider_id)
	return preflight_with_providers(requests, providers, month_key)


# gdlint: disable=max-returns
func preflight_with_providers(
	requests: Array, providers: Dictionary, month_key: String = ""
) -> Dictionary:
	var bucket := month_key if not month_key.is_empty() else get_month_key()
	var month_total := get_month_total_micro_usd(bucket)
	var budget := get_monthly_budget_micro_usd()
	var seen_request_ids := {}
	var estimated_total := 0
	var has_unknown := false
	for request_value in requests:
		if not (request_value is Dictionary):
			return _blocked_preflight(month_total, budget, "provider_unavailable")
		var request: Dictionary = request_value
		var provider_id := String(request.get("provider_id", "")).strip_edges()
		var request_id := String(request.get("request_id", "")).strip_edges()
		var model_id := String(request.get("model_id", "")).strip_edges()
		if (
			provider_id.is_empty()
			or request_id.is_empty()
			or model_id.is_empty()
			or seen_request_ids.has(request_id)
		):
			return _blocked_preflight(month_total, budget, "provider_unavailable")
		seen_request_ids[request_id] = true
		var provider: Variant = providers.get(provider_id)
		if (
			provider == null
			or not provider.has_method("get_model_descriptors")
			or not provider.has_method("estimate_cost")
		):
			return _blocked_preflight(month_total, budget, "provider_unavailable")
		var descriptor := _find_model_descriptor(
			provider.get_model_descriptors(), provider_id, model_id
		)
		if descriptor.is_empty():
			return _blocked_preflight(month_total, budget, "provider_unavailable")
		var capabilities: Variant = descriptor.get("capabilities")
		if not (capabilities is Dictionary) or not capabilities.get("cost_estimate") is bool:
			return _blocked_preflight(month_total, budget, "provider_unavailable")
		var estimate: Variant = provider.estimate_cost(request)
		if not bool(capabilities["cost_estimate"]):
			if estimate != null:
				return _blocked_preflight(month_total, budget, "invalid_estimate")
			has_unknown = true
			continue
		if not _is_canonical_usd(estimate):
			return _blocked_preflight(month_total, budget, "invalid_estimate")
		var estimate_micro: Variant = parse_usd_to_micro(estimate)
		if estimate_micro == null:
			return _blocked_preflight(month_total, budget, "invalid_estimate")
		if estimated_total > MAX_INT64 - int(estimate_micro):
			return _blocked_preflight(month_total, budget, "amount_overflow")
		estimated_total += int(estimate_micro)
		if estimated_total > MAX_CANONICAL_MICRO_USD:
			return _blocked_preflight(month_total, budget, "amount_overflow")
	if has_unknown:
		return {
			"decision": "allowed",
			"estimate_state": "unknown",
			"estimated_total_usd": null,
			"estimated_total_micro_usd": null,
			"month_total_micro_usd": month_total,
			"projected_month_total_micro_usd": null,
			"budget_micro_usd": budget,
			"reason_code": "unknown_estimate",
		}
	if month_total > MAX_INT64 - estimated_total:
		return _blocked_preflight(month_total, budget, "amount_overflow")
	var projected := month_total + estimated_total
	var over_budget := budget > 0 and projected > budget
	return {
		"decision": "needs_confirmation" if over_budget else "allowed",
		"estimate_state": "estimate",
		"estimated_total_usd": format_micro_usd(estimated_total),
		"estimated_total_micro_usd": estimated_total,
		"month_total_micro_usd": month_total,
		"projected_month_total_micro_usd": projected,
		"budget_micro_usd": budget,
		"reason_code": "budget_exceeded" if over_budget else "within_budget",
	}


func reset_month_for_tests(month_key: String) -> void:
	# Tests need to clear persisted dedupe entries as well as totals between runs.
	if SettingsService._config.has_section(_ledger_section_v2(month_key)):
		SettingsService._config.erase_section(_ledger_section_v2(month_key))
	SettingsService.set_setting(_ledger_section_v2(month_key), TOTAL_MICRO_USD_KEY, 0, false)


func _blocked_preflight(month_total: int, budget: int, reason_code: String) -> Dictionary:
	return {
		"decision": "blocked",
		"estimate_state": "unknown",
		"estimated_total_usd": null,
		"estimated_total_micro_usd": null,
		"month_total_micro_usd": month_total,
		"projected_month_total_micro_usd": null,
		"budget_micro_usd": budget,
		"reason_code": reason_code,
	}


func _find_model_descriptor(
	descriptors: Variant, provider_id: String, model_id: String
) -> Dictionary:
	if not (descriptors is Array):
		return {}
	for descriptor_value in descriptors:
		if (
			descriptor_value is Dictionary
			and descriptor_value.get("provider_id") == provider_id
			and descriptor_value.get("model_id") == model_id
		):
			return descriptor_value
	return {}


func _is_canonical_usd(value: Variant) -> bool:
	if not (value is String):
		return false
	return RegEx.create_from_string(CANONICAL_USD_PATTERN).search(String(value)) != null


func _ledger_section_v2(month_key: String) -> String:
	return "%s%s" % [LEDGER_SECTION_PREFIX_V2, month_key]
