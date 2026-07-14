class_name PFProviderResultMapper
extends RefCounted

## Converts one normalized Provider result into pure domain updates without writing product state.

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")


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
			(
				unexpected_slots
				. append(
					{
						"unexpected": true,
						"source_index": index,
						"image": item["image"],
						"actual_seed": item["actual_seed"],
						"input_snapshot": _unexpected_snapshot(request, index),
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


static func _unexpected_snapshot(request: Dictionary, index: int) -> Dictionary:
	var requested_seed := -1
	if int(request["seed"]) >= 0:
		requested_seed = int((int(request["seed"]) + index) % 2147483648)
	return {
		"provider_id": String(request["provider_id"]),
		"model_id": String(request["model_id"]),
		"mode": String(request["mode"]),
		"prompt": String(request["prompt"]),
		"target_width": int(request["target_width"]),
		"target_height": int(request["target_height"]),
		"provider_output_size": Array(request["provider_output_size"]).duplicate(),
		"requested_seed": requested_seed,
		"extra": Dictionary(request["extra"]).duplicate(true),
	}


static func _ambiguous(request: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"error": _error("ambiguous_result", request, 0, false),
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
