extends "res://addons/gut/test.gd"

const MAPPER_PATH := "res://services/provider_result_mapper.gd"
const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const RetroProviderScript := preload(
	"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd"
)


func test_expected_unexpected_and_missing_slot_mapping() -> void:
	var mapper: Script = load(MAPPER_PATH)
	assert_not_null(mapper)
	if mapper == null:
		return
	var request := _request(2)
	var slots := [_slot("slot-0", 0), _slot("slot-1", 1)]
	var one_image := _result([_success(0)])
	var short: Dictionary = mapper.map_result(request, slots, one_image)
	assert_true(short["ok"])
	assert_eq(short["received_count"], 1)
	assert_eq(short["slot_updates"][0]["status"], "succeeded")
	assert_eq(short["slot_updates"][1]["status"], "failed")
	assert_eq(short["slot_updates"][1]["error"]["code"], "result_count_mismatch")
	assert_eq(short["state"], "partial")

	var extra: Dictionary = (
		mapper
		. map_result(
			_request(1),
			[_slot("slot-0", 0)],
			_result([_success(0), _success(1), _failed(2)]),
		)
	)
	assert_true(extra["ok"])
	assert_eq(extra["received_count"], 2)
	assert_eq(extra["slot_updates"].size(), 1)
	assert_eq(extra["unexpected_slots"].size(), 1)
	assert_true(extra["unexpected_slots"][0]["unexpected"])
	assert_eq(
		extra["unexpected_slots"][0]["input_snapshot"].keys().size(),
		slots[0]["input_snapshot"].keys().size(),
	)
	assert_eq(extra["unexpected_slots"][0]["input_snapshot"]["graph_id"], "graph-result")
	assert_eq(extra["unexpected_slots"][0]["input_snapshot"]["reference_asset_ids"], ["asset-a"])
	assert_eq(extra["diagnostics"].size(), 1)

	var empty: Dictionary = mapper.map_result(_request(2), slots, _result([]))
	assert_true(empty["ok"])
	assert_eq(empty["state"], "failed")
	assert_eq(empty["received_count"], 0)
	assert_eq(
		empty["slot_updates"].map(func(slot: Dictionary) -> String: return slot["error"]["code"]),
		["result_count_mismatch", "result_count_mismatch"],
	)


func test_discontinuous_index_is_ambiguous_and_never_retryable() -> void:
	var mapper: Script = load(MAPPER_PATH)
	assert_not_null(mapper)
	if mapper == null:
		return
	var malformed := _result([_success(0), _success(1)])
	malformed["items"][1]["index"] = 2
	var mapped: Dictionary = mapper.map_result(
		_request(2), [_slot("slot-0", 0), _slot("slot-1", 1)], malformed
	)
	assert_false(mapped["ok"])
	assert_eq(mapped["error"]["code"], "ambiguous_result")
	assert_false(mapped["error"]["retryable"])
	assert_eq(mapped["slot_updates"], [])


func test_ambiguous_vs_retryable_malformed_requires_machine_proof() -> void:
	var mapper: Script = load(MAPPER_PATH)
	assert_not_null(mapper)
	if mapper == null:
		return
	var accepted: Dictionary = mapper.map_contract_failure(
		_request(1),
		{"provider_accepted": true, "generation_started": null, "billing_possible": true}
	)
	assert_eq(accepted["error"]["code"], "ambiguous_result")
	assert_false(accepted["error"]["retryable"])
	var unaccepted: Dictionary = mapper.map_contract_failure(
		_request(1),
		{"provider_accepted": false, "generation_started": false, "billing_possible": false}
	)
	assert_eq(unaccepted["error"]["code"], "malformed_response")
	assert_true(unaccepted["error"]["retryable"])
	for guessed in [
		{},
		{"provider_accepted": false, "generation_started": false},
		{"provider_accepted": false, "generation_started": false, "billing_possible": null},
		{
			"provider_accepted": false,
			"generation_started": false,
			"billing_possible": false,
			"message": "not billed"
		},
	]:
		var safe: Dictionary = mapper.map_contract_failure(_request(1), guessed)
		assert_eq(safe["error"]["code"], "ambiguous_result")
		assert_false(safe["error"]["retryable"])


func test_generation_transport_only_retries_when_local_dispatch_is_proven_absent() -> void:
	var cases := [
		{"provider": OpenAIProviderScript.new(), "request": _openai_request()},
		{"provider": RetroProviderScript.new(), "request": _request(1)},
	]
	for item in cases:
		var provider: PFProvider = item["provider"]
		var request: Dictionary = item["request"]
		var local_failure: Dictionary = provider.map_error(
			HTTPRequest.RESULT_CANT_CONNECT,
			0,
			{"attempts": 1, "request_dispatched": false},
			request
		)
		assert_eq(local_failure["code"], "network")
		assert_true(local_failure["retryable"])
		var uncertain: Dictionary = provider.map_error(
			HTTPRequest.RESULT_CANT_CONNECT, 0, {"attempts": 1, "request_dispatched": true}, request
		)
		assert_eq(uncertain["code"], "ambiguous_result")
		assert_false(uncertain["retryable"])
		var server_error: Dictionary = provider.map_error(
			HTTPRequest.RESULT_SUCCESS, 503, {"attempts": 1, "request_dispatched": true}, request
		)
		assert_eq(server_error["code"], "ambiguous_result")
		assert_false(server_error["retryable"])


func _request(batch: int) -> Dictionary:
	return {
		"run_id": "run-result",
		"request_id": "request-result",
		"idempotency_key": "idem-result",
		"provider_id": "retrodiffusion",
		"mode": "txt2img",
		"model_id": "rd_pro",
		"prompt": "barrel",
		"target_width": 2,
		"target_height": 2,
		"provider_output_size": [2, 2],
		"batch": batch,
		"seed": 1,
		"ref_images": [],
		"extra": {"remove_bg": true, "strength": 0.8},
	}


func _openai_request() -> Dictionary:
	var request := _request(1)
	request["provider_id"] = "openai_image"
	request["model_id"] = "gpt-image-2"
	request["provider_output_size"] = [1024, 1024]
	request["seed"] = -1
	request["extra"] = {"quality": "low"}
	return request


func _slot(slot_id: String, index: int) -> Dictionary:
	return {
		"slot_id": slot_id,
		"request_id": "request-result",
		"source_row_id": "row-a",
		"logical_index": index,
		"input_snapshot":
		{
			"kind": "generation",
			"graph_id": "graph-result",
			"source_node_id": "generate",
			"provider_id": "retrodiffusion",
			"model_id": "rd_pro",
			"mode": "txt2img",
			"prompt": "barrel",
			"source_row_id": "row-a",
			"prompt_preset_id": "preset-a",
			"prompt_prefix": "pixel art",
			"reference_asset_ids": ["asset-a"],
			"reference_content_sha256s": ["a".repeat(64)],
			"target_width": 2,
			"target_height": 2,
			"provider_output_size": [2, 2],
			"requested_seed": 1 + index,
			"extra": {"remove_bg": true, "strength": 0.8},
		},
	}


func _result(items: Array) -> Dictionary:
	return {
		"request_id": "request-result",
		"items": items,
		"actual_cost_usd": "0.250000",
		"charge_id": "charge-1",
		"provider_meta": {"remote_task_id": "remote-1"},
	}


func _success(index: int) -> Dictionary:
	return {
		"index": index,
		"image": Image.create(2, 2, false, Image.FORMAT_RGBA8),
		"actual_seed": 10 + index,
		"error": null,
	}


func _failed(index: int) -> Dictionary:
	return {
		"index": index,
		"image": null,
		"actual_seed": null,
		"error": _error("ambiguous_result", false, index + 1),
	}


func _error(code: String, retryable: bool, received: int) -> Dictionary:
	return {
		"code": code,
		"stage": "decode",
		"provider_id": "retrodiffusion",
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": "request-result",
		"attempts": 1,
		"expected_count": 1,
		"received_count": received,
	}
