extends "res://addons/gut/test.gd"

const BatchNode := preload("res://core/graph/nodes/batch_node.gd")
const Graph := preload("res://core/graph/pf_graph.gd")


func test_visible_projection_is_succeeded_not_detached_and_stable() -> void:
	var params := {
		"result_slots":
		[
			{"slot_id": "q", "status": "queued", "detached": false},
			{"slot_id": "a", "status": "succeeded", "asset_id": "asset-a", "detached": false},
			{"slot_id": "f", "status": "failed", "asset_id": "asset-f", "detached": false},
			{"slot_id": "b", "status": "succeeded", "asset_id": "asset-b", "detached": true},
			{
				"slot_id": "c",
				"status": "succeeded",
				"asset_id": "asset-c",
				"detached": false,
				"unexpected": true
			},
			{"slot_id": "x", "status": "canceled", "detached": false},
		]
	}
	assert_eq(BatchNode.get_visible_asset_ids(params), ["asset-a", "asset-c"])


func test_batch_params_have_no_asset_ids_compatibility_field() -> void:
	var node := BatchNode.new()
	var validated := (
		node
		. validate_params(
			{
				"label": "Output",
				"asset_ids": ["legacy"],
				"result_slots": [{"status": "succeeded", "asset_id": "current", "detached": false}],
			}
		)
	)
	assert_false(validated.has("asset_ids"))
	assert_eq(node.execute({}, validated, null)["assets"], ["current"])


func test_batch_without_input_outputs_visible_slots() -> void:
	var params := _standalone_params()
	assert_eq(BatchNode.new().execute({}, params, null), {"assets": ["asset-a"]})


func test_slot_snapshot_record_exact_shapes_fail_closed_at_graph_entry() -> void:
	assert_true(Graph.parse_v2(_graph(_standalone_params()))["ok"])

	var cases := []
	var invalid_status := _standalone_params()
	invalid_status["result_slots"][0]["status"] = "complete"
	cases.append(invalid_status)
	var unknown_slot_field := _standalone_params()
	unknown_slot_field["result_slots"][0]["order"] = 0
	cases.append(unknown_slot_field)
	var queued_with_asset := _standalone_params()
	queued_with_asset["result_slots"][0]["status"] = "queued"
	cases.append(queued_with_asset)
	var detached_queued := _standalone_params()
	detached_queued["result_slots"][0]["status"] = "queued"
	detached_queued["result_slots"][0].erase("asset_id")
	detached_queued["result_slots"][0]["detached"] = true
	cases.append(detached_queued)
	var failed_without_error := _standalone_params()
	failed_without_error["result_slots"][0]["status"] = "failed"
	failed_without_error["result_slots"][0].erase("asset_id")
	cases.append(failed_without_error)

	for params in cases:
		var parsed: Dictionary = Graph.parse_v2(_graph(params))
		assert_false(parsed.get("ok", true), "invalid Output domain must fail closed")
		assert_eq(parsed["error"]["code"], "invalid_output_domain")


func test_record_shape_cost_meta_and_cross_references_fail_closed() -> void:
	assert_true(Graph.parse_v2(_graph(_recorded_params())).get("ok", false))
	var cases := []
	var non_string_slot_id := _recorded_params()
	non_string_slot_id["request_records"][0]["slot_ids"] = [42]
	cases.append(non_string_slot_id)
	var duplicate_slot_id := _recorded_params()
	duplicate_slot_id["request_records"][0]["slot_ids"] = ["slot-1", "slot-1"]
	cases.append(duplicate_slot_id)
	var missing_slot_id := _recorded_params()
	missing_slot_id["request_records"][0]["slot_ids"] = ["missing"]
	cases.append(missing_slot_id)
	var count_mismatch := _recorded_params()
	count_mismatch["request_records"][0]["received_count"] = 0
	cases.append(count_mismatch)
	var bad_cost := _recorded_params()
	bad_cost["request_records"][0]["actual_cost_usd"] = "1.2"
	cases.append(bad_cost)
	var bad_meta := _recorded_params()
	bad_meta["request_records"][0]["provider_meta"] = {"raw_response": "forbidden"}
	cases.append(bad_meta)
	var bad_error := _recorded_params()
	bad_error["request_records"][0]["state"] = "failed"
	bad_error["request_records"][0]["error"] = {"code": "network"}
	cases.append(bad_error)
	for params in cases:
		var parsed := Graph.parse_v2(_graph(params))
		assert_false(parsed.get("ok", true), JSON.stringify(params))
		assert_eq(parsed["error"]["code"], "invalid_output_domain")


func _graph(params: Dictionary) -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Output contract",
		"nodes": [{"id": "output", "type": "batch", "params": params}],
		"edges": [],
	}


func _standalone_params() -> Dictionary:
	return {
		"label": "",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots":
		[
			{
				"slot_id": "11111111-1111-4111-8111-111111111111",
				"run_id": "",
				"request_id": "",
				"source_row_id": "",
				"source_asset_id": "",
				"input_snapshot_id": "",
				"planned_size": [32, 32],
				"status": "succeeded",
				"asset_id": "asset-a",
				"detached": false,
				"unexpected": false,
				"error": null,
			}
		],
	}


func _recorded_params() -> Dictionary:
	return {
		"label": "",
		"source_node_id": "generate",
		"source_run_id": "run-1",
		"role": "current",
		"input_snapshots":
		{
			"snapshot-1":
			{
				"kind": "generation",
				"graph_id": "graph-main",
				"source_node_id": "generate",
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"mode": "txt2img",
				"prompt": "tower",
				"source_row_id": "",
				"prompt_preset_id": "",
				"prompt_prefix": "",
				"reference_asset_ids": [],
				"reference_content_sha256s": [],
				"target_width": 32,
				"target_height": 32,
				"provider_output_size": [1024, 1024],
				"requested_seed": -1,
				"extra": {"quality": "low"},
			}
		},
		"request_records":
		[
			{
				"kind": "provider",
				"provider_id": "openai_image",
				"run_id": "run-1",
				"request_id": "request-1",
				"source_row_id": "",
				"slot_ids": ["slot-1"],
				"requested_count": 1,
				"received_count": 1,
				"attempts": 1,
				"state": "succeeded",
				"actual_cost_usd": "0.010000",
				"charge_id": "charge-1",
				"provider_meta": {"remote_task_id": "remote-1"},
				"remote_cancel_confirmed": null,
				"error": null,
			}
		],
		"result_slots":
		[
			{
				"slot_id": "slot-1",
				"run_id": "run-1",
				"request_id": "request-1",
				"source_row_id": "",
				"source_asset_id": "",
				"input_snapshot_id": "snapshot-1",
				"planned_size": [1024, 1024],
				"status": "succeeded",
				"asset_id": "asset-1",
				"detached": false,
				"unexpected": false,
				"error": null,
			}
		],
	}
