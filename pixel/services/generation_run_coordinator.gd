# gdlint: disable=max-returns
class_name PFGenerationRunCoordinator
extends RefCounted

## Sole Beta 0.7 writer for run, request, slot and Output domain state.
## UI, Provider adapters and edge renderers consume typed events only.

signal run_event(event: Dictionary)

const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const ProviderRunProgressScript := preload("res://services/provider_run_progress.gd")
const MonotonicClockScript := preload("res://infra/monotonic_clock.gd")
const GenerationRetryPreflightScript := preload("res://services/generation_retry_preflight.gd")
const IdUtil := preload("res://core/util/id_util.gd")

const BUSY_SLOT_STATES := ["queued", "running"]
const TERMINAL_RECORD_STATES := ["succeeded", "partial", "failed", "canceled"]
const ACTIONS_ALLOWED_WHILE_BUSY := ["preview", "download"]
const TRANSITIONS := {
	"Ready": ["Queued", "Failed"],
	"Queued": ["Running", "Canceling", "Failed", "Canceled"],
	"Running": ["Canceling", "Complete", "Partial", "Failed", "Canceled"],
	"Canceling": ["Failed", "Canceled"],
	"Complete": [],
	"Partial": [],
	"Failed": [],
	"Canceled": [],
}

var _cancel_cutoffs_msec := {}
var _run_states := {}
var _run_started_msec := {}
var _request_progress := {}
var _previous_run_ratios := {}
var _clock: RefCounted = MonotonicClockScript.new()


func configure_clock(clock: RefCounted) -> void:
	_clock = clock


func preflight_plan(
	plan: Dictionary, offline: bool = false, cost_service: Variant = null, month_key: String = ""
) -> Dictionary:
	var requests: Array = plan.get("requests", [])
	if not bool(plan.get("ok", false)) or requests.is_empty():
		return {
			"decision": "blocked",
			"reason_code": "invalid_request",
			"estimated_total_micro_usd": null,
			"budget_micro_usd": null,
		}
	var ledger: Variant = cost_service if cost_service != null else CostService
	if offline:
		return {
			"decision": "allowed",
			"reason_code": "within_budget",
			"estimated_total_micro_usd": 0,
			"budget_micro_usd": ledger.get_monthly_budget_micro_usd(),
		}
	return ledger.preflight(requests, month_key)


func prepare_retry_preflight(
	slots: Array,
	max_batch: int,
	run_id: String,
	reference_source: Variant = null,
	cost_service: Variant = null,
	month_key: String = ""
) -> Dictionary:
	return GenerationRetryPreflightScript.prepare_failed_slots(
		slots, max_batch, run_id, reference_source, cost_service, month_key
	)


func prepare_full_run(
	graph: PFGraph, source_node_id: String, output_node_id: String, plan: Dictionary
) -> Dictionary:
	var issue := _validate_prepare(graph, source_node_id, output_node_id, plan, false)
	if not issue.is_empty():
		return issue
	var rollback_token := {"graph": graph.to_json()}
	var run_id := _plan_run_id(plan)
	for node_id_value in graph.nodes.keys():
		var node_id := String(node_id_value)
		var node: PFNode = graph.get_node(node_id)
		if node == null or node.get_type() != "batch":
			continue
		var params := graph.get_node_params(node_id)
		if (
			String(params.get("source_node_id", "")) == source_node_id
			and String(params.get("role", "")) == "current"
		):
			params["role"] = "history"
			graph.set_node_params(node_id, params)
			_remove_execution_edge(graph, source_node_id, node_id)
	var pending_params := _pending_params(source_node_id, plan)
	if not bool(BatchNodeScript.validate_v2_domain(pending_params).get("ok", false)):
		_restore_graph(graph, rollback_token["graph"])
		return _command_error("invalid_pending_output")
	if graph.add_node(BatchNodeScript.new(), output_node_id, pending_params).is_empty():
		_restore_graph(graph, rollback_token["graph"])
		return _command_error("output_create_failed")
	var edge_result := graph.add_edge(source_node_id, "assets", output_node_id, "in")
	if not bool(edge_result.get("ok", false)):
		_restore_graph(graph, rollback_token["graph"])
		return _command_error("output_edge_failed")
	_run_states[run_id] = "Queued"
	_run_started_msec[run_id] = _now_msec()
	_previous_run_ratios[run_id] = 0.0
	_emit_run_state(run_id, source_node_id, output_node_id, "Queued")
	return {
		"ok": true,
		"run_id": run_id,
		"output_node_id": output_node_id,
		"rollback_token": rollback_token,
	}


func prepare_cleanup_run(graph: PFGraph, source_node_id: String, output_node_id: String, plan: Dictionary) -> Dictionary:
	if graph == null or graph.get_node(source_node_id) == null or graph.get_node(source_node_id).get_type() != "pixel_cleanup" or graph.get_node(output_node_id) != null or String(plan.get("kind", "")) != "cleanup" or String(plan.get("run_id", "")).is_empty() or Array(plan.get("slots", [])).is_empty():
		return _command_error("invalid_cleanup_plan")
	var rollback_token := {"graph": graph.to_json()}
	for node_id_value in graph.nodes.keys():
		var node_id := String(node_id_value)
		var node: PFNode = graph.get_node(node_id)
		if node != null and node.get_type() == "batch":
			var old := graph.get_node_params(node_id)
			if String(old.get("source_node_id", "")) == source_node_id and String(old.get("role", "")) == "current":
				old["role"] = "history"
				graph.set_node_params(node_id, old)
				_remove_execution_edge(graph, source_node_id, node_id)
	var pending := _pending_params(source_node_id, plan)
	if not bool(BatchNodeScript.validate_v2_domain(pending).get("ok", false)) or graph.add_node(BatchNodeScript.new(), output_node_id, pending).is_empty() or not bool(graph.add_edge(source_node_id, "assets", output_node_id, "in").get("ok", false)):
		_restore_graph(graph, rollback_token["graph"])
		return _command_error("output_create_failed")
	var run_id := String(plan["run_id"])
	_run_states[run_id] = "Queued"
	_run_started_msec[run_id] = _now_msec()
	_emit_run_state(run_id, source_node_id, output_node_id, "Queued")
	return {"ok": true, "run_id": run_id, "output_node_id": output_node_id, "rollback_token": rollback_token}


func next_cleanup_operation(graph: PFGraph, output_node_id: String) -> Dictionary:
	var params := graph.get_node_params(output_node_id) if graph != null else {}
	for slot in params.get("result_slots", []):
		if String(slot.get("status", "")) == "running":
			return {}
	for slot in params.get("result_slots", []):
		if String(slot.get("status", "")) == "queued":
			var snapshot: Dictionary = params.get("input_snapshots", {}).get(String(slot.get("input_snapshot_id", "")), {})
			return {"request_id": String(slot.get("request_id", "")), "slot_id": String(slot.get("slot_id", "")), "source_asset_id": String(slot.get("source_asset_id", "")), "input_snapshot": snapshot.duplicate(true)}
	return {}


func mark_cleanup_running(graph: PFGraph, output_node_id: String, request_id: String) -> Dictionary:
	var params := graph.get_node_params(output_node_id)
	for record in params.get("request_records", []):
		if String(record.get("request_id", "")) == request_id and String(record.get("kind", "")) == "cleanup" and String(record.get("state", "")) == "queued":
			record["state"] = "running"
			record["attempts"] = int(record.get("attempts", 0)) + 1
			for slot in params["result_slots"]:
				if String(slot.get("request_id", "")) == request_id:
					slot["status"] = "running"
			graph.set_node_params(output_node_id, params)
			return {"ok": true}
	return _command_error("invalid_cleanup_operation")


func apply_cleanup_failure(graph: PFGraph, output_node_id: String, request_id: String, error: Dictionary) -> Dictionary:
	return _finish_cleanup_operation(graph, output_node_id, request_id, "failed", "", error)


func apply_cleanup_success(graph: PFGraph, output_node_id: String, request_id: String, image: Image, report: Dictionary, asset_library: Variant = null) -> Dictionary:
	if image == null or report.is_empty():
		return _command_error("invalid_cleanup_result")
	var params := graph.get_node_params(output_node_id)
	var slot := {}
	for value in params.get("result_slots", []):
		if String(value.get("request_id", "")) == request_id:
			slot = value
			break
	if slot.is_empty():
		return _command_error("invalid_cleanup_result")
	var snapshot: Dictionary = params.get("input_snapshots", {}).get(String(slot.get("input_snapshot_id", "")), {})
	var library: Variant = asset_library if asset_library != null else AssetLibrary
	var cleanup := {
		"source_asset": String(snapshot.get("source_asset_id", "")),
		"input_source_kind": String(snapshot.get("input_source_kind", "")),
		"input_source_node_id": String(snapshot.get("input_source_node_id", "")),
		"source_batch_node_id": String(snapshot.get("source_batch_node_id", "")),
		"source_slot_id": String(snapshot.get("source_slot_id", "")),
		"cleanup_node_id": String(snapshot.get("source_node_id", "")),
		"run_id": String(slot.get("run_id", "")),
		"request_id": request_id,
		"preset_id": String(snapshot.get("preset_id", "")),
		"effective_target_size": Array(snapshot.get("effective_target_size", [0, 0])).duplicate(),
		"settings": Dictionary(snapshot.get("settings", {})).duplicate(true),
		"palette_snapshot": snapshot.get("palette_snapshot"),
		"report": report.duplicate(true),
	}
	var asset_id: String = library.register_image(image, "Cleaned", {
		"origin": "cleaned", "tags": ["cleanup"],
		"palette_ref": cleanup["palette_snapshot"],
		"provenance": {
			"provider": null, "model": null, "prompt": "", "seed": null,
			"parent_asset": cleanup["source_asset"], "graph_id": snapshot.get("graph_id"),
			"created_at": IdUtil.utc_now_iso(), "cleanup": cleanup,
		},
	})
	if asset_id.is_empty():
		return _command_error("invalid_cleanup_result")
	return _finish_cleanup_operation(graph, output_node_id, request_id, "succeeded", asset_id, null)


func cancel_cleanup_remaining(graph: PFGraph, output_node_id: String, active_request_id: String) -> Dictionary:
	var params := graph.get_node_params(output_node_id)
	for slot in params.get("result_slots", []):
		if String(slot.get("status", "")) in ["queued", "running"]:
			slot["status"] = "canceled"
			slot["error"] = null
	for record in params.get("request_records", []):
		if String(record.get("state", "")) in ["queued", "running"]:
			record["state"] = "canceled"
			record["remote_cancel_confirmed"] = String(record.get("request_id", "")) == active_request_id
			record["error"] = null
	graph.set_node_params(output_node_id, params)
	return {"ok": true, "state": output_terminal_state(params, String(params.get("source_run_id", "")))}


func prepare_cleanup_retry(graph: PFGraph, output_node_id: String, run_id: String) -> Dictionary:
	var params := graph.get_node_params(output_node_id)
	var retried := 0
	for slot in params.get("result_slots", []):
		var error: Variant = slot.get("error")
		if String(slot.get("status", "")) != "failed" or not (error is Dictionary) or String(error.get("code", "")) != "interrupted":
			continue
		var request_id := IdUtil.uuid_v4()
		slot["run_id"] = run_id
		slot["request_id"] = request_id
		slot["status"] = "queued"
		slot["error"] = null
		params["request_records"].append({
			"kind": "cleanup", "provider_id": "", "run_id": run_id,
			"request_id": request_id, "source_row_id": "", "slot_ids": [String(slot["slot_id"])],
			"requested_count": 1, "received_count": 0, "attempts": 0, "state": "queued",
			"actual_cost_usd": null, "charge_id": "", "provider_meta": {},
			"remote_cancel_confirmed": null, "error": null,
		})
		retried += 1
	if retried == 0:
		return _command_error("retry_source_unavailable")
	params["source_run_id"] = run_id
	if not bool(BatchNodeScript.validate_v2_domain(params).get("ok", false)):
		return _command_error("invalid_cleanup_retry")
	graph.set_node_params(output_node_id, params)
	return {"ok": true, "run_id": run_id, "output_node_id": output_node_id}


func _finish_cleanup_operation(graph: PFGraph, output_node_id: String, request_id: String, status: String, asset_id: String, error: Variant) -> Dictionary:
	var params := graph.get_node_params(output_node_id)
	var found := false
	for slot in params.get("result_slots", []):
		if String(slot.get("request_id", "")) == request_id:
			slot["status"] = status
			slot["error"] = error
			slot.erase("asset_id")
			if status == "succeeded":
				slot["asset_id"] = asset_id
			found = true
	for record in params.get("request_records", []):
		if String(record.get("request_id", "")) == request_id:
			record["state"] = status
			record["received_count"] = 1 if status == "succeeded" else 0
			record["error"] = error
	if not found or not bool(BatchNodeScript.validate_v2_domain(params).get("ok", false)):
		return _command_error("invalid_cleanup_result")
	graph.set_node_params(output_node_id, params)
	return {"ok": true, "state": output_terminal_state(params, String(params.get("source_run_id", "")))}


func rollback_pending_run(graph: PFGraph, rollback_token: Dictionary) -> Dictionary:
	if graph == null or not (rollback_token.get("graph") is Dictionary):
		return _command_error("invalid_rollback_token")
	_restore_graph(graph, rollback_token["graph"])
	return {"ok": true}


func prepare_retry_run(graph: PFGraph, output_node_id: String, plan: Dictionary) -> Dictionary:
	var source_node_id := ""
	if graph != null:
		source_node_id = String(graph.get_node_params(output_node_id).get("source_node_id", ""))
	var issue := _validate_prepare(graph, source_node_id, output_node_id, plan, true)
	if not issue.is_empty():
		return issue
	var params := graph.get_node_params(output_node_id)
	if String(params.get("role", "")) not in ["current", "history"]:
		return _command_error("retry_source_unavailable")
	var rollback_token := {"graph": graph.to_json()}
	var run_id := _plan_run_id(plan)
	var request_by_slot := _request_ids_by_slot(plan)
	var target_ids := request_by_slot.keys()
	for slot_value in params.get("result_slots", []):
		var slot: Dictionary = slot_value
		var slot_id := String(slot.get("slot_id", ""))
		if not target_ids.has(slot_id):
			continue
		if String(slot.get("status", "")) != "failed":
			return _command_error("retry_slot_not_failed", {"slot_id": slot_id})
		slot["run_id"] = run_id
		slot["request_id"] = String(request_by_slot[slot_id])
		slot["status"] = "queued"
		slot["error"] = null
	params["source_run_id"] = run_id
	for record in _queued_records(plan):
		params["request_records"].append(record)
	if not bool(BatchNodeScript.validate_v2_domain(params).get("ok", false)):
		return _command_error("invalid_retry_output")
	graph.set_node_params(output_node_id, params)
	_run_states[run_id] = "Queued"
	_run_started_msec[run_id] = _now_msec()
	_previous_run_ratios[run_id] = 0.0
	_emit_run_state(run_id, source_node_id, output_node_id, "Queued")
	return {
		"ok": true,
		"run_id": run_id,
		"output_node_id": output_node_id,
		"rollback_token": rollback_token,
	}


func mark_submitting(graph: PFGraph, output_node_id: String, request_id: String) -> Dictionary:
	var params := graph.get_node_params(output_node_id) if graph != null else {}
	var matched := false
	var run_id := ""
	for record_value in params.get("request_records", []):
		var record: Dictionary = record_value
		if String(record.get("request_id", "")) != request_id:
			continue
		matched = true
		run_id = String(record.get("run_id", ""))
		if String(record.get("state", "")) == "queued":
			record["state"] = "running"
			record["attempts"] = 1
		for slot_value in params.get("result_slots", []):
			var slot: Dictionary = slot_value
			if String(slot.get("request_id", "")) == request_id and slot["status"] == "queued":
				slot["status"] = "running"
		break
	if not matched:
		return _command_error("request_not_found")
	graph.set_node_params(output_node_id, params)
	_run_states[run_id] = "Running"
	_emit_run_state(run_id, String(params.get("source_node_id", "")), output_node_id, "Running")
	return {"ok": true, "attempts": 1}


func apply_provider_progress(
	graph: PFGraph, output_node_id: String, request_id: String, progress: Dictionary
) -> Dictionary:
	if graph == null or graph.get_node(output_node_id) == null or request_id.is_empty():
		return _command_error("invalid_progress_target")
	var params := graph.get_node_params(output_node_id)
	var run_id := ""
	var matched := false
	for record_value in params.get("request_records", []):
		var record: Dictionary = record_value
		if String(record.get("request_id", "")) != request_id:
			continue
		matched = true
		run_id = String(record.get("run_id", ""))
		if not accepts_business_callback(run_id, _now_msec()):
			return {"ok": true, "ignored": true, "state": "Canceling"}
		var updated: Dictionary = ProviderRunProgressScript.apply_provider_progress(
			record, progress
		)
		if updated.has("progress_issue"):
			return _command_error(String(updated["progress_issue"].get("code", "invalid_progress")))
		_request_progress[_progress_key(run_id, request_id)] = Dictionary(updated["progress"])
		updated.erase("progress")
		record.merge(updated, true)
		if String(record.get("state", "")) == "running":
			for slot_value in params.get("result_slots", []):
				var slot: Dictionary = slot_value
				if (
					String(slot.get("request_id", "")) == request_id
					and String(slot.get("status", "")) == "queued"
				):
					slot["status"] = "running"
		break
	if not matched or not bool(BatchNodeScript.validate_v2_domain(params).get("ok", false)):
		return _command_error("invalid_progress_target")
	graph.set_node_params(output_node_id, params)
	_run_states[run_id] = "Running"
	_emit_run_state(run_id, String(params.get("source_node_id", "")), output_node_id, "Running")
	(
		run_event
		. emit(
			{
				"type": "run_progress",
				"run_id": run_id,
				"source_node_id": String(params.get("source_node_id", "")),
				"output_node_id": output_node_id,
				"progress": run_progress(params, run_id),
			}
		)
	)
	return {"ok": true, "state": "Running"}


func apply_provider_mapping(
	graph: PFGraph,
	output_node_id: String,
	request: Dictionary,
	mapped: Dictionary,
	asset_library: Node
) -> Dictionary:
	if (
		graph == null
		or graph.get_node(output_node_id) == null
		or not bool(mapped.get("ok", false))
		or asset_library == null
		or not asset_library.has_method("register_image")
	):
		return _command_error("invalid_provider_mapping")
	var params := graph.get_node_params(output_node_id)
	var request_id := String(request.get("request_id", ""))
	var run_id := String(request.get("run_id", ""))
	if request_id.is_empty() or run_id.is_empty():
		return _command_error("invalid_provider_mapping")
	if not accepts_business_callback(run_id, _now_msec()):
		return {
			"ok": true,
			"ignored": true,
			"state": "Canceling",
			"registered_asset_ids": [],
		}
	for record_value in params.get("request_records", []):
		if (
			String(record_value.get("request_id", "")) == request_id
			and String(record_value.get("state", "")) in TERMINAL_RECORD_STATES
		):
			return {
				"ok": true,
				"ignored": true,
				"state": String(_run_states.get(run_id, output_terminal_state(params, run_id))),
				"registered_asset_ids": [],
			}
	var registered := {}
	var updates := []
	for value in mapped.get("slot_updates", []):
		if not (value is Dictionary):
			return _command_error("invalid_provider_mapping")
		updates.append(Dictionary(value).duplicate(true))
	for value in mapped.get("unexpected_slots", []):
		if not (value is Dictionary):
			return _command_error("invalid_provider_mapping")
		var update := Dictionary(value).duplicate(true)
		update["status"] = "succeeded"
		update["error"] = null
		update["unexpected"] = true
		updates.append(update)
	for update_value in updates:
		var update: Dictionary = update_value
		if String(update.get("status", "")) != "succeeded":
			continue
		var image: Image = update.get("image") as Image
		var snapshot: Dictionary = update.get("input_snapshot", {})
		if image == null or snapshot.is_empty():
			return _command_error("invalid_provider_mapping")
		var asset_id: String = asset_library.register_image(
			image,
			"%s_%s" % [String(request.get("provider_id", "provider")), String(update["slot_id"])],
			_asset_meta(graph.id, params["source_node_id"], request, snapshot, update, image)
		)
		if asset_id.is_empty():
			return _command_error("asset_registration_failed")
		registered[String(update["slot_id"])] = asset_id
	var next_params: Dictionary = params.duplicate(true)
	var known_slots := {}
	for index in range(next_params["result_slots"].size()):
		known_slots[String(next_params["result_slots"][index]["slot_id"])] = index
	var record_slot_ids := []
	var summary_error: Variant = null
	for update_value in updates:
		var update: Dictionary = update_value
		var slot_id := String(update.get("slot_id", ""))
		var snapshot: Dictionary = Dictionary(update.get("input_snapshot", {})).duplicate(true)
		var slot: Dictionary
		if known_slots.has(slot_id):
			slot = next_params["result_slots"][int(known_slots[slot_id])]
		else:
			var snapshot_id := "%s:snapshot" % slot_id
			next_params["input_snapshots"][snapshot_id] = snapshot
			slot = _domain_slot(update, run_id, request_id, snapshot_id)
			known_slots[slot_id] = next_params["result_slots"].size()
			next_params["result_slots"].append(slot)
		slot["run_id"] = run_id
		slot["request_id"] = request_id
		slot["status"] = String(update.get("status", "failed"))
		slot["unexpected"] = bool(update.get("unexpected", slot.get("unexpected", false)))
		slot["error"] = update.get("error")
		slot.erase("asset_id")
		if slot["status"] == "succeeded":
			slot["asset_id"] = registered[slot_id]
			slot["error"] = null
		elif summary_error == null and slot["error"] is Dictionary:
			summary_error = Dictionary(slot["error"]).duplicate(true)
		record_slot_ids.append(slot_id)
	var record_found := false
	for record_value in next_params["request_records"]:
		var record: Dictionary = record_value
		if String(record.get("request_id", "")) != request_id:
			continue
		record_found = true
		for slot_id in record_slot_ids:
			if not record["slot_ids"].has(slot_id):
				record["slot_ids"].append(slot_id)
		record["received_count"] = int(mapped.get("received_count", 0))
		record["attempts"] = maxi(1, int(record.get("attempts", 0)))
		record["state"] = String(mapped.get("state", "failed"))
		record["actual_cost_usd"] = mapped.get("actual_cost_usd")
		record["charge_id"] = String(mapped.get("charge_id", ""))
		record["provider_meta"] = Dictionary(mapped.get("provider_meta", {})).duplicate(true)
		record["error"] = (
			summary_error if String(record["state"]) in ["partial", "failed"] else null
		)
		break
	if (
		not record_found
		or not bool(BatchNodeScript.validate_v2_domain(next_params).get("ok", false))
	):
		return _command_error("invalid_provider_mapping")
	graph.set_node_params(output_node_id, next_params)
	var terminal := output_terminal_state(next_params, run_id)
	_run_states[run_id] = terminal
	_emit_run_state(run_id, String(next_params["source_node_id"]), output_node_id, terminal)
	return {"ok": true, "state": terminal, "registered_asset_ids": registered.values()}


func run_progress(params: Dictionary, run_id: String) -> Dictionary:
	var total := 0
	var records := []
	var phase := "submitting"
	var phase_rank := {"submitting": 0, "provider_processing": 1, "downloading": 2, "decoding": 3}
	var best_rank := -1
	for record_value in params.get("request_records", []):
		var record: Dictionary = record_value
		if String(record.get("run_id", "")) != run_id:
			continue
		total += int(record.get("requested_count", 0))
		var aggregate_record: Dictionary = record.duplicate(true)
		var progress: Variant = _request_progress.get(
			_progress_key(run_id, String(record.get("request_id", ""))), null
		)
		if progress is Dictionary:
			aggregate_record["progress"] = Dictionary(progress).duplicate(true)
			var record_phase := String(progress.get("phase", "submitting"))
			var rank := int(phase_rank.get(record_phase, -1))
			if rank > best_rank and String(record.get("state", "")) not in TERMINAL_RECORD_STATES:
				best_rank = rank
				phase = record_phase
		records.append(aggregate_record)
	var aggregate: Dictionary = ProviderRunProgressScript.aggregate(
		records, total, float(_previous_run_ratios.get(run_id, 0.0))
	)
	if aggregate.get("ratio") != null:
		_previous_run_ratios[run_id] = float(aggregate["ratio"])
	return {
		"phase": phase,
		"determinate": bool(aggregate["determinate"]),
		"ratio": aggregate["ratio"],
		"completed_items": int(aggregate["completed_items"]),
		"total_items": int(aggregate["total_items"]),
		"elapsed_ms": maxi(0, _now_msec() - int(_run_started_msec.get(run_id, _now_msec()))),
	}


func output_terminal_state(params: Dictionary, run_id: String) -> String:
	var latest_records := []
	for value in params.get("request_records", []):
		if value is Dictionary and String(value.get("run_id", "")) == run_id:
			latest_records.append(value)
	for record_value in latest_records:
		var record: Dictionary = record_value
		if (
			String(record.get("state", "")) == "failed"
			and record.get("error") is Dictionary
			and String(record["error"].get("code", "")) == "cancel_failed"
		):
			return "Failed"
	for record_value in latest_records:
		if String(record_value.get("state", "")) == "canceled":
			return "Canceled"
	var succeeded := 0
	var failed := 0
	var canceled := 0
	var queued := 0
	var running := 0
	for value in params.get("result_slots", []):
		if not (value is Dictionary) or bool(value.get("unexpected", false)):
			continue
		match String(value.get("status", "")):
			"succeeded":
				succeeded += 1
			"failed":
				failed += 1
			"canceled":
				canceled += 1
			"queued":
				queued += 1
			"running":
				running += 1
	if running > 0:
		return "Running"
	if queued > 0:
		return "Queued"
	if succeeded > 0 and failed + canceled == 0:
		return "Complete"
	if succeeded > 0 and failed + canceled > 0:
		return "Partial"
	if failed > 0:
		return "Failed"
	if canceled > 0:
		return "Canceled"
	return "Ready"


func is_action_allowed(params: Dictionary, action: String) -> bool:
	for slot_value in params.get("result_slots", []):
		if String(slot_value.get("status", "")) in BUSY_SLOT_STATES:
			return action in ACTIONS_ALLOWED_WHILE_BUSY
	return true


func can_transition(from_state: String, to_state: String) -> bool:
	return TRANSITIONS.has(from_state) and Array(TRANSITIONS[from_state]).has(to_state)


func begin_cancel_cutoff(run_id: String, cutoff_msec: int = -1) -> void:
	_cancel_cutoffs_msec[run_id] = _now_msec() if cutoff_msec < 0 else cutoff_msec
	_run_states[run_id] = "Canceling"
	run_event.emit({"type": "run_state", "run_id": run_id, "state": "Canceling"})


func accepts_business_callback(run_id: String, occurred_msec: int) -> bool:
	return not _cancel_cutoffs_msec.has(run_id) or occurred_msec < int(_cancel_cutoffs_msec[run_id])


func resolve_cancel(
	graph: PFGraph, output_node_id: String, request_id: String, result: Dictionary
) -> Dictionary:
	if (
		graph == null
		or graph.get_node(output_node_id) == null
		or String(result.get("request_id", "")) != request_id
		or ProviderContractV2.validate_cancel_result(result) != null
	):
		return _command_error("invalid_cancel_result")
	var params := graph.get_node_params(output_node_id)
	var record := _find_record(params, request_id)
	if record.is_empty():
		return _command_error("request_not_found")
	if String(record.get("state", "")) in TERMINAL_RECORD_STATES:
		return {
			"ok": true,
			"ignored": true,
			"state": _cancel_terminal_state(params, String(record["run_id"]))
		}
	for slot_value in params.get("result_slots", []):
		var slot: Dictionary = slot_value
		if (
			String(slot.get("request_id", "")) == request_id
			and String(slot.get("status", "")) in BUSY_SLOT_STATES
		):
			slot["status"] = "canceled"
			slot["error"] = null
	record["state"] = "canceled"
	record["remote_cancel_confirmed"] = bool(result["remote_cancel_confirmed"])
	record["error"] = null
	var billing: Variant = result.get("billing_update")
	if billing is Dictionary:
		record["actual_cost_usd"] = billing["actual_cost_usd"]
		record["charge_id"] = String(billing["charge_id"])
		record["provider_meta"] = Dictionary(billing["provider_meta"]).duplicate(true)
	return _finish_cancel_update(graph, output_node_id, params, String(record["run_id"]))


func reject_cancel(
	graph: PFGraph, output_node_id: String, request_id: String, error: Dictionary
) -> Dictionary:
	if (
		graph == null
		or graph.get_node(output_node_id) == null
		or String(error.get("code", "")) != "cancel_failed"
		or String(error.get("request_id", "")) != request_id
		or ProviderContractV2.validate_pf_error(error) != null
	):
		return _command_error("invalid_cancel_error")
	var params := graph.get_node_params(output_node_id)
	var record := _find_record(params, request_id)
	if record.is_empty():
		return _command_error("request_not_found")
	if String(record.get("state", "")) in TERMINAL_RECORD_STATES:
		return {
			"ok": true,
			"ignored": true,
			"state": _cancel_terminal_state(params, String(record["run_id"]))
		}
	for slot_value in params.get("result_slots", []):
		var slot: Dictionary = slot_value
		if (
			String(slot.get("request_id", "")) == request_id
			and String(slot.get("status", "")) in BUSY_SLOT_STATES
		):
			slot["status"] = "failed"
			slot["error"] = error.duplicate(true)
	record["state"] = "failed"
	record["remote_cancel_confirmed"] = null
	record["error"] = error.duplicate(true)
	return _finish_cancel_update(graph, output_node_id, params, String(record["run_id"]))


func _find_record(params: Dictionary, request_id: String) -> Dictionary:
	for record_value in params.get("request_records", []):
		if record_value is Dictionary and String(record_value.get("request_id", "")) == request_id:
			return record_value
	return {}


func _finish_cancel_update(
	graph: PFGraph, output_node_id: String, params: Dictionary, run_id: String
) -> Dictionary:
	if not bool(BatchNodeScript.validate_v2_domain(params).get("ok", false)):
		return _command_error("invalid_cancel_domain")
	graph.set_node_params(output_node_id, params)
	var state := _cancel_terminal_state(params, run_id)
	_run_states[run_id] = state
	_emit_run_state(run_id, String(params.get("source_node_id", "")), output_node_id, state)
	return {"ok": true, "state": state}


func _cancel_terminal_state(params: Dictionary, run_id: String) -> String:
	for record_value in params.get("request_records", []):
		if (
			String(record_value.get("run_id", "")) == run_id
			and String(record_value.get("state", "")) in ["queued", "running"]
		):
			return "Canceling"
	return output_terminal_state(params, run_id)


func _progress_key(run_id: String, request_id: String) -> String:
	return "%s\n%s" % [run_id, request_id]


func recover_interrupted(graph: PFGraph) -> Dictionary:
	if graph == null:
		return _command_error("missing_graph")
	var outputs := {}
	for node_id_value in graph.nodes.keys():
		var node_id := String(node_id_value)
		var node: PFNode = graph.get_node(node_id)
		if node == null or node.get_type() != "batch":
			continue
		var params := graph.get_node_params(node_id)
		var changed := false
		var records_by_id := {}
		for record_value in params.get("request_records", []):
			var record: Dictionary = record_value
			records_by_id[String(record.get("request_id", ""))] = record
		for slot_value in params.get("result_slots", []):
			var slot: Dictionary = slot_value
			if String(slot.get("status", "")) not in BUSY_SLOT_STATES:
				continue
			var record: Dictionary = records_by_id.get(String(slot.get("request_id", "")), {})
			var attempts := int(record.get("attempts", 0))
			var stage := (
				"queue"
				if attempts == 0
				else (
					"cleanup" if String(record.get("kind", "provider")) == "cleanup" else "provider"
				)
			)
			slot["status"] = "failed"
			slot["error"] = _pf_error(
				"interrupted",
				stage,
				String(record.get("provider_id", "")),
				String(record.get("request_id", "")),
				attempts,
				int(record.get("requested_count", 0)),
				0,
				true
			)
			changed = true
		for record_value in params.get("request_records", []):
			var record: Dictionary = record_value
			if String(record.get("state", "")) not in ["queued", "running"]:
				continue
			_rederive_record(record, params["result_slots"])
			changed = true
		if not changed:
			continue
		graph.set_node_params(node_id, params)
		var state := output_terminal_state(params, String(params.get("source_run_id", "")))
		outputs[node_id] = {"state": state}
		_emit_run_state(
			String(params.get("source_run_id", "")),
			String(params.get("source_node_id", "")),
			node_id,
			"idle"
		)
	return {
		"ok": true,
		"outputs": outputs,
		"dialog_count": 0,
		"network_count": 0,
		"worker_count": 0,
		"undo_count": 0,
	}


func _validate_prepare(
	graph: PFGraph, source_node_id: String, output_node_id: String, plan: Dictionary, is_retry: bool
) -> Dictionary:
	if graph == null or graph.get_node(source_node_id) == null:
		return _command_error("missing_generation_source")
	if output_node_id.is_empty():
		return _command_error("invalid_output_id")
	if (
		(not is_retry and graph.get_node(output_node_id) != null)
		or (is_retry and graph.get_node(output_node_id) == null)
	):
		return _command_error("invalid_output_target")
	if not bool(plan.get("ok", false)) or plan.get("requests", []).is_empty():
		return _command_error("invalid_generation_plan")
	var run_id := _plan_run_id(plan)
	if run_id.is_empty():
		return _command_error("invalid_generation_plan")
	for request_value in plan.get("requests", []):
		if not (request_value is Dictionary):
			return _command_error("invalid_generation_plan")
		var request: Dictionary = request_value
		if String(request.get("run_id", "")) != run_id:
			return _command_error("mixed_run_plan")
	return {}


func _pending_params(source_node_id: String, plan: Dictionary) -> Dictionary:
	var snapshots := {}
	var slots := []
	var run_id := _plan_run_id(plan)
	for value in plan.get("slots", []):
		var planned: Dictionary = value
		var snapshot_id := "%s:snapshot" % String(planned.get("slot_id", ""))
		var snapshot: Dictionary = Dictionary(planned.get("input_snapshot", {})).duplicate(true)
		snapshots[snapshot_id] = snapshot
		slots.append(_domain_slot(planned, run_id, String(planned["request_id"]), snapshot_id))
	return {
		"label": "",
		"source_node_id": source_node_id,
		"source_run_id": run_id,
		"role": "current",
		"input_snapshots": snapshots,
		"request_records": _queued_records(plan),
		"result_slots": slots,
	}


func _queued_records(plan: Dictionary) -> Array:
	var result := []
	if String(plan.get("kind", "provider")) == "cleanup":
		for slot_value in plan.get("slots", []):
			var slot: Dictionary = slot_value
			result.append({
				"kind": "cleanup", "provider_id": "", "run_id": String(plan.get("run_id", "")),
				"request_id": String(slot.get("request_id", "")), "source_row_id": "",
				"slot_ids": [String(slot.get("slot_id", ""))], "requested_count": 1,
				"received_count": 0, "attempts": 0, "state": "queued",
				"actual_cost_usd": null, "charge_id": "", "provider_meta": {},
				"remote_cancel_confirmed": null, "error": null,
			})
		return result
	for request_value in plan.get("requests", []):
		var request: Dictionary = request_value
		var slot_ids := []
		for slot_value in plan.get("slots", []):
			if String(slot_value.get("request_id", "")) == String(request["request_id"]):
				slot_ids.append(String(slot_value["slot_id"]))
		(
			result
			. append(
				{
					"kind": String(plan.get("kind", "provider")),
					"provider_id": String(request.get("provider_id", "")),
					"run_id": String(request["run_id"]),
					"request_id": String(request["request_id"]),
					"source_row_id": _source_row_for_request(plan, String(request["request_id"])),
					"slot_ids": slot_ids,
					"requested_count": int(request.get("batch", 1)),
					"received_count": 0,
					"attempts": 0,
					"state": "queued",
					"actual_cost_usd": null,
					"charge_id": "",
					"provider_meta": {},
					"remote_cancel_confirmed": null,
					"error": null,
				}
			)
		)
	return result


func _domain_slot(
	planned: Dictionary, run_id: String, request_id: String, snapshot_id: String
) -> Dictionary:
	var snapshot: Dictionary = planned.get("input_snapshot", {})
	return {
		"slot_id": String(planned.get("slot_id", "")),
		"run_id": run_id,
		"request_id": request_id,
		"source_row_id": String(planned.get("source_row_id", "")),
		"source_asset_id": String(planned.get("source_asset_id", "")),
		"input_snapshot_id": snapshot_id,
		"planned_size": Array(planned.get("planned_size", snapshot.get("provider_output_size", []))).duplicate(),
		"status": String(planned.get("status", "queued")),
		"detached": bool(planned.get("detached", false)),
		"unexpected": bool(planned.get("unexpected", false)),
		"error": planned.get("error"),
	}


func _request_ids_by_slot(plan: Dictionary) -> Dictionary:
	var result := {}
	for value in plan.get("slots", []):
		if value is Dictionary:
			result[String(value.get("slot_id", ""))] = String(value.get("request_id", ""))
	return result


func _source_row_for_request(plan: Dictionary, request_id: String) -> String:
	for value in plan.get("slots", []):
		if value is Dictionary and String(value.get("request_id", "")) == request_id:
			return String(value.get("source_row_id", ""))
	return ""


func _plan_run_id(plan: Dictionary) -> String:
	var requests: Array = plan.get("requests", [])
	return String(requests[0].get("run_id", "")) if not requests.is_empty() else String(plan.get("run_id", ""))


func _remove_execution_edge(graph: PFGraph, source_node_id: String, output_node_id: String) -> void:
	var kept: Array[Dictionary] = []
	for edge in graph.edges:
		if (
			String(edge.get("from", ["", ""])[0]) == source_node_id
			and String(edge.get("to", ["", ""])[0]) == output_node_id
			and String(edge.get("to", ["", ""])[1]) == "in"
		):
			continue
		kept.append(Dictionary(edge).duplicate(true))
	graph.edges = kept


func _restore_graph(graph: PFGraph, data: Dictionary) -> void:
	var restored: PFGraph = GraphScript.from_json(data)
	graph.graph_version = restored.graph_version
	graph.id = restored.id
	graph.name = restored.name
	graph.nodes = restored.nodes
	graph.edges = restored.edges
	graph._node_order = restored._node_order
	graph._raw_graph_fields = restored._raw_graph_fields


func _rederive_record(record: Dictionary, slots: Array) -> void:
	var expected_ids: Array = Array(record.get("slot_ids", [])).slice(
		0, int(record.get("requested_count", 0))
	)
	var referenced := []
	var received := 0
	for slot_value in slots:
		var slot: Dictionary = slot_value
		if not Array(record.get("slot_ids", [])).has(String(slot.get("slot_id", ""))):
			continue
		if String(slot.get("status", "")) == "succeeded":
			received += 1
		if expected_ids.has(String(slot.get("slot_id", ""))):
			referenced.append(slot)
	record["received_count"] = received
	var first_error: Variant = null
	var succeeded := 0
	var failed := 0
	var canceled := 0
	for slot_value in referenced:
		var slot: Dictionary = slot_value
		match String(slot.get("status", "")):
			"succeeded":
				succeeded += 1
			"failed":
				failed += 1
				if first_error == null and slot.get("error") is Dictionary:
					first_error = Dictionary(slot["error"]).duplicate(true)
			"canceled":
				canceled += 1
	if canceled > 0:
		record["state"] = "canceled"
		record["error"] = null
		if record.get("remote_cancel_confirmed") == null:
			record["remote_cancel_confirmed"] = false
	elif succeeded == referenced.size() and succeeded > 0:
		record["state"] = "succeeded"
		record["error"] = null
	elif succeeded > 0 and failed > 0:
		record["state"] = "partial"
		record["error"] = first_error
	else:
		record["state"] = "failed"
		record["error"] = first_error


func _asset_meta(
	graph_id: String,
	source_node_id: String,
	request: Dictionary,
	snapshot: Dictionary,
	update: Dictionary,
	image: Image
) -> Dictionary:
	return {
		"origin": "generated",
		"tags": [String(request.get("provider_id", "")), "graph"],
		"provenance":
		{
			"graph_id": graph_id,
			"generation_snapshot":
			{
				"provider_id": snapshot.get("provider_id"),
				"model_id": snapshot.get("model_id"),
				"mode": snapshot.get("mode"),
				"target_width": snapshot.get("target_width"),
				"target_height": snapshot.get("target_height"),
				"provider_output_size": snapshot.get("provider_output_size"),
				"actual_width": image.get_width(),
				"actual_height": image.get_height(),
				"requested_seed": snapshot.get("requested_seed", -1),
				"actual_seed": update.get("actual_seed"),
				"run_id": request.get("run_id"),
				"request_id": request.get("request_id"),
				"source_node_id": source_node_id,
				"source_row_id": snapshot.get("source_row_id", ""),
				"prompt_preset_id": snapshot.get("prompt_preset_id", ""),
				"prompt_prefix": snapshot.get("prompt_prefix", ""),
				"prompt": snapshot.get("prompt", ""),
				"reference_asset_ids": snapshot.get("reference_asset_ids", []),
				"reference_content_sha256s": snapshot.get("reference_content_sha256s", []),
				"extra": snapshot.get("extra", {}),
			},
		},
	}


func _pf_error(
	code: String,
	stage: String,
	provider_id: String,
	request_id: String,
	attempts: int,
	expected_count: int,
	received_count: int,
	retryable: bool
) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": provider_id,
		"retryable": retryable,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": attempts,
		"expected_count": expected_count,
		"received_count": received_count,
	}


func _emit_run_state(
	run_id: String, source_node_id: String, output_node_id: String, state: String
) -> void:
	(
		run_event
		. emit(
			{
				"type": "edge_state",
				"run_id": run_id,
				"source_node_id": source_node_id,
				"output_node_id": output_node_id,
				"state": state,
			}
		)
	)


func _now_msec() -> int:
	if _clock != null and _clock.has_method("now_msec"):
		return int(_clock.call("now_msec"))
	return 0


func _command_error(code: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": {"code": code, "args": args.duplicate(true)}}
