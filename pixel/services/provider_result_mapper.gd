class_name PFProviderResultMapper
extends RefCounted

## Converts one normalized Provider result into pure domain updates without writing product state.

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")


static func map_contract_failure(request: Dictionary, acceptance_proof: Dictionary) -> Dictionary:
	var proof_keys := ["billing_possible", "generation_started", "provider_accepted"]
	var exact_proof := acceptance_proof.size() == proof_keys.size()
	for key in proof_keys:
		exact_proof = exact_proof and acceptance_proof.has(key)
	var definitely_unaccepted := (
		exact_proof
		and acceptance_proof["provider_accepted"] is bool
		and acceptance_proof["generation_started"] is bool
		and acceptance_proof["billing_possible"] is bool
		and not bool(acceptance_proof["provider_accepted"])
		and not bool(acceptance_proof["generation_started"])
		and not bool(acceptance_proof["billing_possible"])
	)
	return _contract_failure(
		request, "malformed_response" if definitely_unaccepted else "ambiguous_result"
	)


static func map_provider_failure(
	request: Dictionary, planned_slots: Array, error: Dictionary
) -> Dictionary:
	if (
		ContractV2.validate_gen_request(request) != null
		or ContractV2.validate_pf_error(error) != null
		or planned_slots.size() != int(request.get("batch", 0))
		or String(error.get("provider_id", "")) != String(request.get("provider_id", ""))
		or String(error.get("request_id", "")) != String(request.get("request_id", ""))
		or int(error.get("expected_count", -1)) != int(request.get("batch", 0))
	):
		return _ambiguous(request)
	var slot_updates: Array[Dictionary] = []
	for value in planned_slots:
		if not (value is Dictionary):
			return _ambiguous(request)
		var planned: Dictionary = Dictionary(value).duplicate(true)
		if (
			String(planned.get("request_id", "")) != String(request["request_id"])
			or String(planned.get("slot_id", "")).is_empty()
			or not (planned.get("input_snapshot", {}) is Dictionary)
		):
			return _ambiguous(request)
		planned["status"] = "failed"
		planned["image"] = null
		planned["actual_seed"] = null
		planned["error"] = error.duplicate(true)
		slot_updates.append(planned)
	return {
		"ok": true,
		"error": null,
		"state": "failed",
		"slot_updates": slot_updates,
		"unexpected_slots": [],
		"diagnostics": [],
		"received_count": int(error.get("received_count", 0)),
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": {},
	}


static func map_result(request: Dictionary, planned_slots: Array, result: Dictionary) -> Dictionary:
	if ContractV2.validate_gen_request(request) != null:
		return _ambiguous(request)
	if String(result.get("request_id", "")) != String(request["request_id"]):
		return _ambiguous(request)
	var allowed_meta_keys := Array(request.get("provider_meta_keys", ["remote_task_id"]))
	if (
		ContractV2.validate_gen_result(
			result, Array(request["provider_output_size"]), allowed_meta_keys
		)
		!= null
	):
		return _ambiguous(request)
	var expected_count := int(request["batch"])
	if planned_slots.size() != expected_count:
		return _ambiguous(request)
	var received_count := 0
	for item_value in result["items"]:
		var item: Dictionary = item_value
		if item["image"] is Image:
			received_count += 1
	var slot_updates: Array[Dictionary] = []
	var unexpected_slots: Array[Dictionary] = []
	var diagnostics: Array[Dictionary] = []
	for index in range(expected_count):
		var planned: Dictionary = Dictionary(planned_slots[index]).duplicate(true)
		if index >= result["items"].size():
			planned["status"] = "failed"
			planned["image"] = null
			planned["actual_seed"] = null
			planned["error"] = _error("result_count_mismatch", request, received_count, true)
		elif result["items"][index]["image"] is Image:
			planned["status"] = "succeeded"
			planned["image"] = result["items"][index]["image"]
			planned["actual_seed"] = result["items"][index]["actual_seed"]
			planned["error"] = null
		else:
			planned["status"] = "failed"
			planned["image"] = null
			planned["actual_seed"] = null
			planned["error"] = Dictionary(result["items"][index]["error"]).duplicate(true)
		slot_updates.append(planned)
	for index in range(expected_count, result["items"].size()):
		var item: Dictionary = result["items"][index]
		if item["image"] is Image:
			var input_snapshot := _unexpected_snapshot(request, planned_slots, index)
			(
				unexpected_slots
				. append(
					{
						"slot_id": "%s-unexpected-%03d" % [String(request["run_id"]), index],
						"request_id": String(request["request_id"]),
						"source_row_id": String(input_snapshot["source_row_id"]),
						"unexpected": true,
						"source_index": index,
						"image": item["image"],
						"actual_seed": item["actual_seed"],
						"input_snapshot": input_snapshot,
					}
				)
			)
		else:
			(
				diagnostics
				. append(
					{
						"code": "unexpected_failed_item",
						"index": index,
						"request_id": String(request["request_id"]),
					}
				)
			)
	var succeeded_expected := 0
	for update in slot_updates:
		if String(update["status"]) == "succeeded":
			succeeded_expected += 1
	var state := "failed"
	if succeeded_expected == expected_count:
		state = "succeeded"
	elif succeeded_expected > 0:
		state = "partial"
	return {
		"ok": true,
		"error": null,
		"state": state,
		"slot_updates": slot_updates,
		"unexpected_slots": unexpected_slots,
		"diagnostics": diagnostics,
		"received_count": received_count,
		"actual_cost_usd": result["actual_cost_usd"],
		"charge_id": result["charge_id"],
		"provider_meta": Dictionary(result["provider_meta"]).duplicate(true),
	}


static func _unexpected_snapshot(
	request: Dictionary, planned_slots: Array, index: int
) -> Dictionary:
	var requested_seed := -1
	if int(request["seed"]) >= 0:
		requested_seed = int((int(request["seed"]) + index) % 2147483648)
	var snapshot: Dictionary = Dictionary(planned_slots[0]["input_snapshot"]).duplicate(true)
	snapshot["requested_seed"] = requested_seed
	return snapshot


static func _ambiguous(request: Dictionary) -> Dictionary:
	return _contract_failure(request, "ambiguous_result")


static func _contract_failure(request: Dictionary, code: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error(code, request, 0, code == "malformed_response"),
		"state": "failed",
		"slot_updates": [],
		"unexpected_slots": [],
		"diagnostics": [],
		"received_count": 0,
	}


static func _error(
	code: String, request: Dictionary, received_count: int, retryable: bool
) -> Dictionary:
	return {
		"code": code,
		"stage": "decode",
		"provider_id": String(request.get("provider_id", "")),
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": String(request.get("request_id", "result-mapper")),
		"attempts": 1,
		"expected_count": maxi(0, int(request.get("batch", 0))),
		"received_count": maxi(0, received_count),
	}
