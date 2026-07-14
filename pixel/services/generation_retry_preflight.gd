class_name PFGenerationRetryPreflight
extends RefCounted

## Pure B7-3 boundary: plan retry/full requests and budget-check them before submission.

const PlannerScript := preload("res://services/generation_request_planner.gd")


static func prepare_failed_slots(
	slots: Array,
	max_batch: int,
	run_id: String,
	reference_source: Variant = null,
	cost_service: Variant = null,
	month_key: String = ""
) -> Dictionary:
	var planned := PlannerScript.plan_retry_slots(slots, max_batch, run_id, reference_source)
	return _with_preflight("failed_slots", planned, cost_service, month_key)


static func prepare_full(
	input: Dictionary, descriptors: Array, cost_service: Variant = null, month_key: String = ""
) -> Dictionary:
	var planned := PlannerScript.plan(input, descriptors)
	return _with_preflight("full_regeneration", planned, cost_service, month_key)


static func authorize(prepared: Dictionary, confirmed: bool = false) -> Dictionary:
	if not bool(prepared.get("ok", false)):
		return _denied(prepared.get("issue"))
	var preflight: Dictionary = prepared.get("preflight", {})
	var decision := String(preflight.get("decision", "blocked"))
	if decision == "blocked":
		return _denied(
			{
				"code": String(preflight.get("reason_code", "provider_unavailable")),
				"field": "budget",
				"args": {},
			}
		)
	if decision == "needs_confirmation" and not confirmed:
		return _denied({"code": "budget_confirmation_canceled", "field": "budget", "args": {}})
	return {
		"ok": true,
		"issue": null,
		"requests": Array(prepared.get("requests", [])).duplicate(true),
		"slots": Array(prepared.get("slots", [])).duplicate(true),
	}


static func _with_preflight(
	kind: String, planned: Dictionary, cost_service: Variant, month_key: String
) -> Dictionary:
	if not bool(planned.get("ok", false)):
		return {
			"ok": false,
			"kind": kind,
			"issue": planned.get("issue"),
			"requests": [],
			"slots": [],
			"preflight": null,
		}
	var ledger: Variant = cost_service if cost_service != null else CostService
	var requests: Array = planned.get("requests", [])
	return {
		"ok": true,
		"kind": kind,
		"issue": null,
		"requests": requests.duplicate(true),
		"slots": Array(planned.get("slots", [])).duplicate(true),
		"preflight": ledger.preflight(requests, month_key),
	}


static func _denied(issue: Variant) -> Dictionary:
	return {"ok": false, "issue": issue, "requests": [], "slots": []}
