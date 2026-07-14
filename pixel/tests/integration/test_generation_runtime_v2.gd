extends "res://addons/gut/test.gd"

const CoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const Scanner := preload("res://tests/helpers/credential_sentinel_scanner.gd")


class FakeClock:
	extends RefCounted

	var value := 0

	func now_msec() -> int:
		return value


class RecordingAssetLibrary:
	extends Node

	var registered := 0

	func register_image(_image: Image, _name: String, _metadata: Dictionary = {}) -> String:
		registered += 1
		return "asset-%d" % registered


func before_each() -> void:
	ProjectService.new_project("B7-4 runtime")


func test_run_progress_uses_fixed_slots_phase_priority_and_fake_elapsed() -> void:
	var clock := FakeClock.new()
	clock.value = 100
	var coordinator := CoordinatorScript.new()
	coordinator.configure_clock(clock)
	assert_true(coordinator.has_method("apply_provider_progress"))
	if not coordinator.has_method("apply_provider_progress"):
		return
	var graph := _graph()
	var plan := _plan("run-progress", ["request-a", "request-b"])
	assert_true(coordinator.prepare_full_run(graph, "generate", "output", plan)["ok"])
	assert_true(
		(
			coordinator
			. apply_provider_progress(
				graph,
				"output",
				"request-a",
				{
					"phase": "submitting",
					"determinate": false,
					"ratio": null,
					"completed_items": 0,
					"total_items": 1,
				}
			)["ok"]
		)
	)
	clock.value = 1300
	assert_true(
		(
			coordinator
			. apply_provider_progress(
				graph,
				"output",
				"request-a",
				{
					"phase": "provider_processing",
					"determinate": false,
					"ratio": null,
					"completed_items": 0,
					"total_items": 1,
				}
			)["ok"]
		)
	)
	var progress: Dictionary = coordinator.run_progress(
		graph.get_node_params("output"), "run-progress"
	)
	assert_eq(
		progress,
		{
			"phase": "provider_processing",
			"determinate": false,
			"ratio": null,
			"completed_items": 0,
			"total_items": 2,
			"elapsed_ms": 1200,
		}
	)


func test_multi_cancel_terminalizes_domain_and_ignores_late_business_callback() -> void:
	var clock := FakeClock.new()
	clock.value = 10
	var coordinator := CoordinatorScript.new()
	coordinator.configure_clock(clock)
	assert_true(coordinator.has_method("resolve_cancel"))
	assert_true(coordinator.has_method("reject_cancel"))
	if not coordinator.has_method("resolve_cancel") or not coordinator.has_method("reject_cancel"):
		return
	var graph := _graph()
	var plan := _plan("run-cancel", ["request-a", "request-b"])
	assert_true(coordinator.prepare_full_run(graph, "generate", "output", plan)["ok"])
	assert_true(coordinator.mark_submitting(graph, "output", "request-a")["ok"])
	assert_true(coordinator.mark_submitting(graph, "output", "request-b")["ok"])
	coordinator.begin_cancel_cutoff("run-cancel", 10)
	var first: Dictionary = (
		coordinator
		. resolve_cancel(
			graph,
			"output",
			"request-a",
			{
				"request_id": "request-a",
				"local_stopped": true,
				"remote_cancel_confirmed": false,
				"billing_update": null,
			}
		)
	)
	assert_true(first["ok"])
	assert_eq(first["state"], "Canceling")
	var error := _error("cancel_failed", "request-b", false, "cancel")
	var second: Dictionary = coordinator.reject_cancel(graph, "output", "request-b", error)
	assert_true(second["ok"])
	assert_eq(second["state"], "Failed")
	var params: Dictionary = graph.get_node_params("output")
	assert_eq(
		params["result_slots"].map(func(slot: Dictionary) -> String: return slot["status"]),
		["canceled", "failed"]
	)
	assert_eq(
		params["request_records"].map(func(record: Dictionary) -> String: return record["state"]),
		["canceled", "failed"]
	)
	clock.value = 11
	var library := RecordingAssetLibrary.new()
	add_child_autofree(library)
	var late: Dictionary = coordinator.apply_provider_mapping(
		graph, "output", plan["requests"][1], _success_mapping(plan["slots"][1]), library
	)
	assert_true(late["ok"])
	assert_true(late["ignored"])
	assert_eq(library.registered, 0)


func test_project_runtime_recovery_finishes_before_ui_observation() -> void:
	var graph := _graph()
	var coordinator := CoordinatorScript.new()
	var plan := _plan("run-stale", ["request-stale"])
	assert_true(coordinator.prepare_full_run(graph, "generate", "output", plan)["ok"])
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	assert_true(ProjectService.has_method("recover_interrupted_runs_before_ui"))
	if not ProjectService.has_method("recover_interrupted_runs_before_ui"):
		return
	var recovered: Dictionary = ProjectService.recover_interrupted_runs_before_ui()
	assert_true(recovered["ok"])
	assert_eq(recovered["recovered_outputs"], 1)
	var loaded := GraphScript.from_json(ProjectService.get_graph_data(graph.id))
	var params: Dictionary = loaded.get_node_params("output")
	assert_eq(params["result_slots"][0]["status"], "failed")
	assert_eq(params["result_slots"][0]["error"]["code"], "interrupted")
	assert_eq(params["request_records"][0]["state"], "failed")
	var source := FileAccess.get_file_as_string("res://services/project_service.gd")
	var open_start := source.find("func _open_project")
	assert_lt(
		source.find("recover_interrupted_runs_before_ui(false)", open_start),
		source.find("project_loaded.emit(current_project)", open_start),
	)


func test_coordinator_events_and_errors_never_expose_credential_sentinel() -> void:
	var coordinator := CoordinatorScript.new()
	var events := []
	coordinator.run_event.connect(func(event: Dictionary) -> void: events.append(event))
	var plan := _plan("run-safe", ["request-safe"])
	plan["transport_secret"] = Scanner.VALUE
	assert_true(coordinator.prepare_full_run(_graph(), "generate", "output", plan)["ok"])
	assert_false(Scanner.contains(events, Scanner.VALUE))


func test_generation_controller_routes_progress_and_both_cancel_outcomes_through_coordinator() -> void:
	var source := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	var coordinator_source := FileAccess.get_file_as_string(
		"res://services/generation_run_coordinator.gd"
	)
	assert_true(source.contains("_coordinator.apply_provider_progress("))
	assert_true(source.contains("_coordinator.begin_cancel_cutoff("))
	assert_true(source.contains("cancel_task.rejected.connect("))
	assert_true(source.contains("_coordinator.resolve_cancel("))
	assert_true(source.contains("_coordinator.reject_cancel("))
	assert_true(source.contains("_coordinator.preflight_plan("))
	assert_false(source.contains("CostService.preflight("))
	assert_true(coordinator_source.contains("func preflight_plan("))
	assert_false(source.contains("ProviderRunProgressScript.apply_provider_progress("))


func test_submit_failure_uses_atomic_pending_output_rollback_path() -> void:
	var source := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	assert_true(source.contains("func _rollback_pending_output("))
	assert_true(source.contains("_coordinator.rollback_pending_run("))
	assert_true(source.contains("_canvas._remove_item_direct("))


func test_manual_retry_routes_original_failed_slots_to_retry_run_without_full_output_creation() -> void:
	var controller := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	var shell := FileAccess.get_file_as_string("res://ui/shell/m2_1_ui_controller.gd")
	assert_true(controller.contains("func retry_graph("))
	assert_true(controller.contains("_coordinator.prepare_retry_preflight("))
	assert_true(controller.contains("_coordinator.prepare_retry_run("))
	assert_true(controller.contains("input_snapshots"))
	assert_true(shell.contains("_generation_flow.retry_graph("))
	assert_true(shell.contains('"retry", "retry_failed"'))


func _graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph-runtime"
	graph.add_node(GenerateNodeScript.new(), "generate", {})
	return graph


func _plan(run_id: String, request_ids: Array) -> Dictionary:
	var requests := []
	var slots := []
	for index in range(request_ids.size()):
		var request_id := String(request_ids[index])
		(
			requests
			. append(
				{
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
					"batch": 1,
					"seed": -1,
					"ref_images": [],
					"extra": {"quality": "low"},
				}
			)
		)
		(
			slots
			. append(
				{
					"slot_id": "slot-%d" % index,
					"request_id": request_id,
					"source_row_id": "",
					"input_snapshot": _snapshot(),
				}
			)
		)
	return {"ok": true, "requests": requests, "slots": slots, "total_slots": slots.size()}


func _snapshot() -> Dictionary:
	return {
		"kind": "generation",
		"graph_id": "graph-runtime",
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


func _success_mapping(slot: Dictionary) -> Dictionary:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	return {
		"ok": true,
		"state": "succeeded",
		"received_count": 1,
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": {},
		"slot_updates":
		[
			slot.merged(
				{"status": "succeeded", "image": image, "actual_seed": null, "error": null}, true
			)
		],
		"unexpected_slots": [],
		"diagnostics": [],
	}


func _error(code: String, request_id: String, retryable: bool, stage: String) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": "openai_image",
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
