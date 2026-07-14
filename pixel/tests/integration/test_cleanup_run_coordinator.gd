extends "res://addons/gut/test.gd"

const COORDINATOR_PATH := "res://services/generation_run_coordinator.gd"
const GraphScript := preload("res://core/graph/pf_graph.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func before_each() -> void:
	AssetLibrary.clear()


func test_every_click_new_output_and_single_failure_continues() -> void:
	var coordinator: Variant = load(COORDINATOR_PATH).new()
	var graph := _graph()
	assert_true(coordinator.prepare_cleanup_run(graph, "cleanup", "output-1", _plan("run-1"))["ok"])
	assert_eq(coordinator.next_cleanup_operation(graph, "output-1")["source_asset_id"], "source-a")
	assert_true(coordinator.mark_cleanup_running(graph, "output-1", "request-a")["ok"])
	assert_true(coordinator.apply_cleanup_failure(graph, "output-1", "request-a", _error("request-a"))["ok"])
	assert_eq(coordinator.next_cleanup_operation(graph, "output-1")["source_asset_id"], "source-b")
	assert_true(coordinator.mark_cleanup_running(graph, "output-1", "request-b")["ok"])
	assert_true(coordinator.apply_cleanup_success(graph, "output-1", "request-b", "clean-b", _report())["ok"])
	assert_eq(coordinator.output_terminal_state(graph.get_node_params("output-1"), "run-1"), "Partial")
	assert_true(coordinator.prepare_cleanup_run(graph, "cleanup", "output-2", _plan("run-2"))["ok"])
	assert_eq(graph.get_node_params("output-1")["role"], "history")
	assert_eq(graph.get_node_params("output-2")["role"], "current")
	assert_eq(graph.get_node_params("output-1")["result_slots"][1]["asset_id"], "clean-b")


func test_cancel_keeps_success_and_cancels_remaining() -> void:
	var coordinator: Variant = load(COORDINATOR_PATH).new()
	var graph := _graph()
	assert_true(coordinator.prepare_cleanup_run(graph, "cleanup", "output", _plan("run-cancel"))["ok"])
	assert_true(coordinator.mark_cleanup_running(graph, "output", "request-a")["ok"])
	assert_true(coordinator.apply_cleanup_success(graph, "output", "request-a", "clean-a", _report())["ok"])
	assert_true(coordinator.mark_cleanup_running(graph, "output", "request-b")["ok"])
	var canceled: Dictionary = coordinator.cancel_cleanup_remaining(graph, "output", "request-b")
	assert_true(canceled.get("ok", false))
	var slots: Array = graph.get_node_params("output")["result_slots"]
	assert_eq([slots[0]["status"], slots[1]["status"]], ["succeeded", "canceled"])
	assert_eq(slots[0]["asset_id"], "clean-a")
	assert_true(coordinator.next_cleanup_operation(graph, "output").is_empty())


func test_retry_interrupted_same_output_original_snapshots_only() -> void:
	var coordinator: Variant = load(COORDINATOR_PATH).new()
	var graph := _graph()
	assert_true(coordinator.prepare_cleanup_run(graph, "cleanup", "output", _plan("run-old"))["ok"])
	assert_true(coordinator.mark_cleanup_running(graph, "output", "request-a")["ok"])
	assert_true(coordinator.apply_cleanup_success(graph, "output", "request-a", "clean-a", _report())["ok"])
	assert_true(coordinator.mark_cleanup_running(graph, "output", "request-b")["ok"])
	assert_true(coordinator.recover_interrupted(graph)["ok"])
	var before: Dictionary = graph.get_node_params("output")
	var old_records: Array = before["request_records"].duplicate(true)
	var original_snapshot: Dictionary = before["input_snapshots"][before["result_slots"][1]["input_snapshot_id"]]
	var retry: Dictionary = coordinator.prepare_cleanup_retry(graph, "output", "run-retry")
	assert_true(retry.get("ok", false))
	assert_eq(retry["output_node_id"], "output")
	var after: Dictionary = graph.get_node_params("output")
	assert_eq(after["result_slots"][0]["asset_id"], "clean-a")
	assert_eq(after["result_slots"][0]["status"], "succeeded")
	assert_eq(after["input_snapshots"][after["result_slots"][1]["input_snapshot_id"]], original_snapshot)
	assert_ne(after["result_slots"][1]["request_id"], "request-b")
	assert_eq(after["request_records"].size(), old_records.size() + 1)
	assert_eq(after["request_records"][1], old_records[1])


func test_success_registers_cleaned_asset_with_frozen_provenance_before_slot_write() -> void:
	var coordinator: Variant = load(COORDINATOR_PATH).new()
	var graph := _graph()
	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	source.fill(Color.RED)
	var source_id := AssetLibrary.register_image(source, "source", {"id": "source-a"})
	assert_eq(source_id, "source-a")
	assert_true(coordinator.prepare_cleanup_run(graph, "cleanup", "output", _plan("run-provenance"))["ok"])
	assert_true(coordinator.mark_cleanup_running(graph, "output", "request-a")["ok"])
	var cleaned := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	cleaned.fill(Color.BLUE)
	var result: Dictionary = coordinator.apply_cleanup_success(
		graph, "output", "request-a", cleaned, _report(), AssetLibrary
	)
	assert_true(result.get("ok", false))
	var slot: Dictionary = graph.get_node_params("output")["result_slots"][0]
	assert_true(AssetLibrary.has_asset(String(slot["asset_id"])))
	var meta: Dictionary = AssetLibrary.get_asset_meta(String(slot["asset_id"]))
	assert_eq(meta["origin"], "cleaned")
	assert_eq(meta["provenance"]["parent_asset"], "source-a")
	assert_eq(meta["provenance"]["cleanup"]["source_asset"], "source-a")
	assert_eq(meta["provenance"]["cleanup"]["run_id"], "run-provenance")
	assert_eq(meta["provenance"]["cleanup"]["request_id"], "request-a")
	assert_eq(meta["provenance"]["cleanup"]["report"], _report())


func _graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.add_node(CleanupNodeScript.new(), "cleanup", {})
	return graph


func _plan(run_id: String) -> Dictionary:
	var settings: Dictionary = CleanupNodeScript.DEFAULT_SETTINGS.duplicate(true)
	var slots := []
	for index in range(2):
		var suffix := "a" if index == 0 else "b"
		var snapshot := {
			"kind": "cleanup", "graph_id": "graph", "source_node_id": "cleanup",
			"input_source_node_id": "source", "input_source_kind": "reference_set",
			"source_asset_id": "source-%s" % suffix, "source_batch_node_id": "", "source_slot_id": "",
			"preset_id": "cleanup-16bit-db32", "settings": settings.duplicate(true),
			"palette_snapshot": null, "effective_target_size": [0, 0],
		}
		slots.append({
			"slot_id": "slot-%s" % suffix, "request_id": "request-%s" % suffix,
			"source_asset_id": "source-%s" % suffix, "source_row_id": "",
			"planned_size": [8, 8], "input_snapshot": snapshot,
		})
	return {"ok": true, "kind": "cleanup", "run_id": run_id, "slots": slots}


func _error(request_id: String) -> Dictionary:
	return {"code": "cleanup_failed", "stage": "cleanup", "provider_id": "", "request_id": request_id, "attempts": 1, "expected_count": 1, "received_count": 0, "retryable": false, "retry_after_seconds": null, "status_code": null}


func _report() -> Dictionary:
	return {"input_size": [8, 8], "output_size": [8, 8], "effective_target_size": [0, 0], "detected_grid": {"cell_size": [1, 1], "offset": [0, 0]}, "steps": {"detect_grid": true, "resample": true, "quantize": true}, "input_color_count": 2, "output_color_count": 2, "elapsed_ms": 1}
