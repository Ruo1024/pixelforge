class_name PFGenerationRetryPreflight
extends RefCounted

## Pure B7-3 boundary: plan retry/full requests before submission.

const PlannerScript := preload("res://services/generation_request_planner.gd")


static func prepare_failed_slots(
	slots: Array, max_batch: int, run_id: String, reference_source: Variant = null
) -> Dictionary:
	var planned := PlannerScript.plan_retry_slots(slots, max_batch, run_id, reference_source)
	return _with_preflight("failed_slots", planned)


static func prepare_full(input: Dictionary, descriptors: Array) -> Dictionary:
	var planned := PlannerScript.plan(input, descriptors)
	return _with_preflight("full_regeneration", planned)


static func authorize(prepared: Dictionary, _confirmed: bool = false) -> Dictionary:
	if not bool(prepared.get("ok", false)):
		return _denied(prepared.get("issue"))
	var preflight: Dictionary = prepared.get("preflight", {})
	var decision := String(preflight.get("decision", "blocked"))
	if decision == "blocked":
		return _denied(
			{
				"code": String(preflight.get("reason_code", "provider_unavailable")),
				"field": "request",
				"args": {},
			}
		)
	return {
		"ok": true,
		"issue": null,
		"requests": Array(prepared.get("requests", [])).duplicate(true),
		"slots": Array(prepared.get("slots", [])).duplicate(true),
	}


static func _with_preflight(kind: String, planned: Dictionary) -> Dictionary:
	if not bool(planned.get("ok", false)):
		return {
			"ok": false,
			"kind": kind,
			"issue": planned.get("issue"),
			"requests": [],
			"slots": [],
			"preflight": null,
		}
	var requests: Array = planned.get("requests", [])
	return {
		"ok": true,
		"kind": kind,
		"issue": null,
		"requests": requests.duplicate(true),
		"slots": Array(planned.get("slots", [])).duplicate(true),
		"preflight": {"decision": "allowed", "reason_code": "validated"},
	}


static func _denied(issue: Variant) -> Dictionary:
	return {"ok": false, "issue": issue, "requests": [], "slots": []}
