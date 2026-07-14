extends "res://addons/gut/test.gd"

const COORDINATOR_PATH := "res://services/generation_run_coordinator.gd"
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func test_all_stale_slots_and_records_converge() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _stale_graph()
	var observed: Dictionary = {"http": 0, "worker": 0, "dialog": 0, "undo": 0, "edge": []}
	coordinator.run_event.connect(
		func(event: Dictionary) -> void:
			if String(event.get("type", "")) == "edge_state":
				observed["edge"].append(event.get("state"))
	)
	var recovered: Dictionary = coordinator.recover_interrupted(graph)
	assert_true(recovered.get("ok", false))
	var params: Dictionary = graph.get_node_params("output")
	assert_eq(
		params["result_slots"].map(func(slot: Dictionary) -> String: return slot["status"]),
		["failed", "failed", "succeeded"]
	)
	for index in [0, 1]:
		assert_eq(params["result_slots"][index]["error"]["code"], "interrupted")
		assert_eq(params["result_slots"][index]["error"]["stage"], "recovery")
	assert_eq(params["request_records"][0]["state"], "failed")
	assert_eq(params["request_records"][1]["state"], "failed")
	assert_eq(params["request_records"][2]["state"], "succeeded")
	assert_eq(observed, {"http": 0, "worker": 0, "dialog": 0, "undo": 0, "edge": ["idle"]})


func test_recovery_rederives_cancel_priority_without_popup() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _stale_graph()
	var params: Dictionary = graph.get_node_params("output")
	params["request_records"][1]["state"] = "failed"
	params["request_records"][1]["error"] = _error("cancel_failed", "request-running", "cancel")
	graph.set_node_params("output", params)
	var recovered: Dictionary = coordinator.recover_interrupted(graph)
	assert_true(recovered.get("ok", false))
	assert_eq(recovered["outputs"]["output"]["state"], "Failed")
	assert_eq(recovered["dialog_count"], 0)
	assert_eq(recovered["network_count"], 0)
	assert_eq(recovered["worker_count"], 0)
	assert_eq(recovered["undo_count"], 0)


func _coordinator() -> Variant:
	assert_true(ResourceLoader.exists(COORDINATOR_PATH), "B7-4 coordinator must exist")
	if not ResourceLoader.exists(COORDINATOR_PATH):
		return null
	return load(COORDINATOR_PATH).new()


func _stale_graph() -> PFGraph:
	var graph: PFGraph = GraphScript.new()
	graph.id = "graph-recovery"
	graph.add_node(GenerateNodeScript.new(), "generate", {})
	var snapshots: Dictionary = {}
	var slots: Array = []
	var records: Array = []
	for index in range(3):
		var request_id: String = "request-%d" % index
		var slot_id: String = "slot-%d" % index
		var snapshot_id: String = "snapshot-%d" % index
		snapshots[snapshot_id] = _snapshot()
		var state: String = ["queued", "running", "succeeded"][index]
		var slot: Dictionary = {
			"slot_id": slot_id,
			"run_id": "run-stale",
			"request_id": request_id,
			"source_row_id": "",
			"source_asset_id": "",
			"input_snapshot_id": snapshot_id,
			"planned_size": [2, 2],
			"status": state,
			"detached": false,
			"unexpected": false,
			"error": null,
		}
		if state == "succeeded":
			slot["asset_id"] = "asset-existing"
		slots.append(slot)
		(
			records
			. append(
				{
					"kind": "provider",
					"provider_id": "openai_image",
					"run_id": "run-stale",
					"request_id": request_id,
					"source_row_id": "",
					"slot_ids": [slot_id],
					"requested_count": 1,
					"received_count": 1 if state == "succeeded" else 0,
					"attempts": 0 if state == "queued" else 1,
					"state": state,
					"actual_cost_usd": null,
					"charge_id": "",
					"provider_meta": {},
					"remote_cancel_confirmed": null,
					"error": null,
				}
			)
		)
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			"output",
			{
				"label": "",
				"source_node_id": "generate",
				"source_run_id": "run-stale",
				"role": "current",
				"input_snapshots": snapshots,
				"request_records": records,
				"result_slots": slots,
			}
		)
	)
	graph.add_edge("generate", "assets", "output", "in")
	return graph


func _snapshot() -> Dictionary:
	return {
		"kind": "generation",
		"graph_id": "graph-recovery",
		"source_node_id": "generate",
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"mode": "txt2img",
		"prompt": "safe prompt",
		"source_row_id": "",
		"prompt_preset_id": "",
		"prompt_prefix": "",
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"target_width": 2,
		"target_height": 2,
		"provider_output_size": [2, 2],
		"requested_seed": -1,
		"extra": {"quality": "low"},
	}


func _error(code: String, request_id: String, stage: String) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": "openai_image",
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
