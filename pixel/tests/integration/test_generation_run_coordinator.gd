extends "res://addons/gut/test.gd"

const COORDINATOR_PATH := "res://services/generation_run_coordinator.gd"
const LEGACY_ADAPTER_PATH := "res://services/legacy_generation_v2_adapter.gd"
const LEGACY_CONTROLLER_PATH := "res://ui/shell/openai_generation_controller.gd"
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


class RecordingAssetLibrary:
	extends Node

	var graph: PFGraph
	var output_node_id := ""
	var observed_statuses := []
	var registered := []

	func register_image(image: Image, name: String, metadata: Dictionary = {}) -> String:
		var statuses := []
		for slot in graph.get_node_params(output_node_id).get("result_slots", []):
			statuses.append(String(slot.get("status", "")))
		observed_statuses.append(statuses)
		registered.append({"image": image, "name": name, "metadata": metadata.duplicate(true)})
		return "asset-%d" % registered.size()


func test_legacy_adapter_and_old_entries_are_absent() -> void:
	assert_false(FileAccess.file_exists(LEGACY_ADAPTER_PATH))
	assert_false(FileAccess.file_exists(LEGACY_CONTROLLER_PATH))
	var runner_source: String = FileAccess.get_file_as_string("res://services/graph_mock_runner.gd")
	assert_false(runner_source.contains("LegacyAdapterScript"))
	assert_false(runner_source.contains("materialize_provider_mapping"))
	var shell_source: String = FileAccess.get_file_as_string("res://ui/shell/m2_1_ui_controller.gd")
	assert_false(shell_source.contains("OpenAIGenerationControllerScript"))


func test_is_only_run_slot_output_writer() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var forbidden: Dictionary = {
		"res://ui/shell/m2_1_ui_controller.gd": ["_set_batch_run_state"],
		"res://services/graph_mock_runner.gd": ["set_node_params", "register_image"],
		"res://ui/canvas/canvas_graph_edge_renderer.gd": ["set_node_params", "result_slots"],
	}
	for path in forbidden:
		var source: String = FileAccess.get_file_as_string(path)
		for symbol in forbidden[path]:
			assert_false(source.contains(symbol), "%s must not own %s" % [path, symbol])
	assert_true(coordinator.has_method("prepare_full_run"))


func test_atomic_pending_output_creation_and_queue_rollback() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _graph_with_current_output()
	var old_json: Dictionary = graph.to_json()
	var prepared: Dictionary = coordinator.prepare_full_run(
		graph, "generate", "output-new", _plan("run-new", 2)
	)
	assert_true(prepared.get("ok", false))
	assert_not_null(graph.get_node("output-new"))
	var pending: Dictionary = graph.get_node_params("output-new")
	assert_eq(pending["role"], "current")
	assert_eq(pending["source_run_id"], "run-new")
	assert_eq(_slot_statuses(pending), ["queued", "queued"])
	assert_true(_has_edge(graph, "generate", "output-new"))
	assert_eq(graph.get_node_params("output-old")["role"], "history")
	assert_false(_has_edge(graph, "generate", "output-old"))

	var rolled_back: Dictionary = coordinator.rollback_pending_run(
		graph, prepared["rollback_token"]
	)
	assert_true(rolled_back.get("ok", false))
	assert_eq(graph.to_json(), old_json)


func test_full_run_preserves_history_output_and_downstream_edges() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _graph_with_current_output(true)
	var old_params: Dictionary = graph.get_node_params("output-old")
	assert_true(
		coordinator.prepare_full_run(graph, "generate", "output-new", _plan("run-2", 1))["ok"]
	)
	assert_eq(graph.get_node_params("output-old")["role"], "history")
	assert_eq(graph.get_node_params("output-old")["label"], old_params["label"])
	assert_true(_has_edge(graph, "output-old", "consumer"))
	assert_true(_has_edge(graph, "generate", "output-new"))


func test_retry_reuses_slots_and_latest_run_scope() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _graph_with_retryable_output()
	var before: Dictionary = graph.get_node_params("output-old")
	var retry: Dictionary = coordinator.prepare_retry_run(
		graph, "output-old", _retry_plan("run-retry", before)
	)
	assert_true(retry.get("ok", false))
	assert_eq(retry["output_node_id"], "output-old")
	var after: Dictionary = graph.get_node_params("output-old")
	assert_eq(after["source_run_id"], "run-retry")
	assert_eq(after["result_slots"].size(), before["result_slots"].size())
	assert_eq(after["result_slots"][0], before["result_slots"][0])
	assert_eq(after["result_slots"][1]["status"], "queued")
	assert_eq(after["result_slots"][1]["run_id"], "run-retry")
	assert_ne(after["result_slots"][1]["request_id"], before["result_slots"][1]["request_id"])
	assert_true(after["result_slots"][0]["detached"])
	assert_eq(coordinator.run_progress(after, "run-retry")["total_items"], 1)


func test_retry_run_terminal_priority_and_busy_domain_gate() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var params: Dictionary = _retryable_params()
	assert_eq(coordinator.output_terminal_state(params, "run-old"), "Partial")
	params["result_slots"][1]["status"] = "running"
	params["result_slots"][1]["error"] = null
	params["request_records"][1]["state"] = "running"
	params["request_records"][1]["error"] = null
	for forbidden in ["copy", "delete", "detach", "edit", "undo"]:
		assert_false(coordinator.is_action_allowed(params, forbidden))
	for allowed in ["preview", "download"]:
		assert_true(coordinator.is_action_allowed(params, allowed))
	params["result_slots"][1]["status"] = "canceled"
	params["result_slots"][1]["error"] = null
	params["request_records"][1]["state"] = "canceled"
	params["request_records"][1]["remote_cancel_confirmed"] = false
	assert_eq(coordinator.output_terminal_state(params, "run-old"), "Canceled")
	params["request_records"][1]["state"] = "failed"
	params["request_records"][1]["remote_cancel_confirmed"] = null
	params["request_records"][1]["error"] = _error("cancel_failed", false, "request-failed")
	assert_eq(coordinator.output_terminal_state(params, "run-old"), "Failed")


func test_registers_asset_before_slot_output() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	var graph: PFGraph = _graph_with_current_output()
	assert_true(
		coordinator.prepare_full_run(graph, "generate", "output-new", _plan("run-map", 1))["ok"]
	)
	var library: RecordingAssetLibrary = RecordingAssetLibrary.new()
	library.graph = graph
	library.output_node_id = "output-new"
	add_child_autofree(library)
	var request: Dictionary = _plan("run-map", 1)["requests"][0]
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var mapped: Dictionary = {
		"ok": true,
		"state": "succeeded",
		"received_count": 1,
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": {},
		"slot_updates":
		[
			_plan("run-map", 1)["slots"][0].merged(
				{"status": "succeeded", "image": image, "actual_seed": null, "error": null}, true
			)
		],
		"unexpected_slots": [],
		"diagnostics": [],
	}
	var applied: Dictionary = coordinator.apply_provider_mapping(
		graph, "output-new", request, mapped, library
	)
	assert_true(applied.get("ok", false))
	assert_eq(library.observed_statuses, [["queued"]])
	assert_eq(graph.get_node_params("output-new")["result_slots"][0]["status"], "succeeded")


func test_generation_state_transition_matrix_and_cancel_cutoff() -> void:
	var coordinator: Variant = _coordinator()
	if coordinator == null:
		return
	assert_true(coordinator.can_transition("Ready", "Queued"))
	assert_true(coordinator.can_transition("Queued", "Running"))
	assert_true(coordinator.can_transition("Running", "Canceling"))
	for terminal in ["Complete", "Partial", "Failed", "Canceled"]:
		assert_true(coordinator.can_transition("Running", terminal))
	assert_false(coordinator.can_transition("Ready", "Running"))
	assert_false(coordinator.can_transition("Complete", "Running"))
	coordinator.begin_cancel_cutoff("run-cutoff", 100)
	assert_true(coordinator.accepts_business_callback("run-cutoff", 99))
	assert_false(coordinator.accepts_business_callback("run-cutoff", 100))
	assert_false(coordinator.accepts_business_callback("run-cutoff", 101))


func _coordinator() -> Variant:
	assert_true(ResourceLoader.exists(COORDINATOR_PATH), "B7-4 coordinator must exist")
	if not ResourceLoader.exists(COORDINATOR_PATH):
		return null
	return load(COORDINATOR_PATH).new()


func _graph_with_current_output(with_consumer: bool = false) -> PFGraph:
	var graph: PFGraph = GraphScript.new()
	graph.id = "graph-b7-4"
	graph.add_node(GenerateNodeScript.new(), "generate", {})
	graph.add_node(BatchNodeScript.new(), "output-old", _empty_output("run-old", "Old Output"))
	assert_true(graph.add_edge("generate", "assets", "output-old", "in")["ok"])
	if with_consumer:
		graph.add_node(BatchNodeScript.new(), "consumer", _standalone_output())
		assert_true(graph.add_edge("output-old", "assets", "consumer", "in")["ok"])
	return graph


func _graph_with_retryable_output() -> PFGraph:
	var graph: PFGraph = _graph_with_current_output()
	graph.set_node_params("output-old", _retryable_params())
	return graph


func _empty_output(run_id: String, label: String = "") -> Dictionary:
	return {
		"label": label,
		"source_node_id": "generate",
		"source_run_id": run_id,
		"role": "current",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}


func _standalone_output() -> Dictionary:
	return {
		"label": "Consumer",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}


func _plan(run_id: String, count: int) -> Dictionary:
	var request_id: String = "%s-request-000" % run_id
	var request: Dictionary = {
		"run_id": run_id,
		"request_id": request_id,
		"idempotency_key": "%s:%s" % [run_id, request_id],
		"provider_id": "openai_image",
		"mode": "txt2img",
		"model_id": "gpt-image-2",
		"prompt": "safe prompt",
		"target_width": 2,
		"target_height": 2,
		"provider_output_size": [2, 2],
		"batch": count,
		"seed": -1,
		"ref_images": [],
		"extra": {"quality": "low"},
	}
	var slots: Array = []
	for index in range(count):
		(
			slots
			. append(
				{
					"slot_id": "%s-slot-%03d" % [run_id, index],
					"request_id": request_id,
					"source_row_id": "",
					"input_snapshot": _snapshot(run_id),
				}
			)
		)
	return {"ok": true, "requests": [request], "slots": slots, "total_slots": count}


func _retry_plan(run_id: String, params: Dictionary) -> Dictionary:
	var request_id: String = "%s-retry-request-000" % run_id
	var request: Dictionary = _plan(run_id, 1)["requests"][0]
	request["request_id"] = request_id
	request["idempotency_key"] = "%s:%s" % [run_id, request_id]
	var failed: Dictionary = params["result_slots"][1].duplicate(true)
	failed["request_id"] = request_id
	failed["input_snapshot"] = params["input_snapshots"][failed["input_snapshot_id"]].duplicate(
		true
	)
	return {"ok": true, "requests": [request], "slots": [failed], "total_slots": 1}


func _retryable_params() -> Dictionary:
	var success_snapshot: Dictionary = _snapshot("run-old")
	var failed_snapshot: Dictionary = _snapshot("run-old")
	var success: Dictionary = {
		"slot_id": "slot-success",
		"run_id": "run-old",
		"request_id": "request-success",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "snapshot-success",
		"planned_size": [2, 2],
		"status": "succeeded",
		"asset_id": "asset-success",
		"detached": true,
		"unexpected": false,
		"error": null,
	}
	var failure: Dictionary = {
		"slot_id": "slot-failed",
		"run_id": "run-old",
		"request_id": "request-failed",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "snapshot-failed",
		"planned_size": [2, 2],
		"status": "failed",
		"detached": false,
		"unexpected": false,
		"error": _error("network", true, "request-failed"),
	}
	return {
		"label": "",
		"source_node_id": "generate",
		"source_run_id": "run-old",
		"role": "current",
		"input_snapshots":
		{
			"snapshot-success": success_snapshot,
			"snapshot-failed": failed_snapshot,
		},
		"request_records":
		[
			_record("run-old", "request-success", ["slot-success"], "succeeded", null, 1),
			_record(
				"run-old",
				"request-failed",
				["slot-failed"],
				"failed",
				_error("network", true, "request-failed"),
				0
			),
		],
		"result_slots": [success, failure],
	}


func _record(
	run_id: String,
	request_id: String,
	slot_ids: Array,
	state: String,
	error: Variant,
	received_count: int
) -> Dictionary:
	return {
		"kind": "provider",
		"provider_id": "openai_image",
		"run_id": run_id,
		"request_id": request_id,
		"source_row_id": "",
		"slot_ids": slot_ids,
		"requested_count": slot_ids.size(),
		"received_count": received_count,
		"attempts": 1,
		"state": state,
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": {},
		"remote_cancel_confirmed": null,
		"error": error,
	}


func _snapshot(_run_id: String) -> Dictionary:
	return {
		"kind": "generation",
		"graph_id": "graph-b7-4",
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


func _error(code: String, retryable: bool, request_id: String) -> Dictionary:
	return {
		"code": code,
		"stage": "provider",
		"provider_id": "openai_image",
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}


func _slot_statuses(params: Dictionary) -> Array:
	return params["result_slots"].map(func(slot: Dictionary) -> String: return slot["status"])


func _has_edge(graph: PFGraph, from_id: String, to_id: String) -> bool:
	for edge in graph.edges:
		if String(edge["from"][0]) == from_id and String(edge["to"][0]) == to_id:
			return true
	return false
