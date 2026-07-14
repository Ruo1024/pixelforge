class_name PFGenerationRunController
extends Node

## Provider dispatch and UI orchestration. Domain writes are delegated to the coordinator.

const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GenerationRunCoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const GraphGenerationPlanBuilderScript := preload("res://services/graph_generation_plan_builder.gd")
const MockGenerationExecutorScript := preload("res://services/mock_generation_executor.gd")
const ProviderResultMapperScript := preload("res://services/provider_result_mapper.gd")
const ProviderRunProgressScript := preload("res://services/provider_run_progress.gd")
const IdUtil := preload("res://core/util/id_util.gd")

var _canvas: Control = null
var _status_label: Label = null
var _cost_label: Label = null
var _provider_settings_dialog: ConfirmationDialog = null
var _budget_dialog: ConfirmationDialog = null
var _pending_runs := {}
var _pending_budget_run := {}
var _run_scopes := {}
var _canceling_runs := {}
var _coordinator: PFGenerationRunCoordinator


func setup(
	canvas: Control,
	status_label: Label,
	cost_label: Label = null,
	provider_settings_dialog: ConfirmationDialog = null
) -> void:
	_canvas = canvas
	_status_label = status_label
	_cost_label = cost_label
	_provider_settings_dialog = provider_settings_dialog
	_coordinator = GenerationRunCoordinatorScript.new()
	_budget_dialog = ConfirmationDialog.new()
	_budget_dialog.name = "ProviderBudgetDialog"
	_budget_dialog.title = Strings.DIALOG_PROVIDER_BUDGET_TITLE
	_budget_dialog.confirmed.connect(_confirm_budget_run)
	_budget_dialog.canceled.connect(func() -> void: _pending_budget_run.clear())
	add_child(_budget_dialog)
	CostService.cost_changed_v2.connect(
		func(_month: String, _total_micro_usd: int) -> void: _refresh_cost_label()
	)
	CostService.budget_changed_v2.connect(
		func(_limit_micro_usd: int) -> void: _refresh_cost_label()
	)
	_refresh_cost_label()


func configure_session() -> void:
	if _provider_settings_dialog != null:
		_provider_settings_dialog.show_settings("openai_image")


func generate_batch() -> void:
	_queue_graph(_make_graph(), "batch_1", "", "generate", "openai_image")


func run_graph(
	graph: PFGraph, batch_node_id: String, batch_card_id: String, generate_node_id: String = ""
) -> void:
	var target_generate_id := generate_node_id
	if target_generate_id.is_empty():
		target_generate_id = _generate_node_for_batch(graph, batch_node_id)
	_queue_graph(
		graph,
		batch_node_id,
		batch_card_id,
		target_generate_id,
		_provider_id_for_graph(graph, target_generate_id)
	)


func cancel_graph(graph_id: String, generate_node_id: String = "") -> bool:
	var canceled := false
	for request_id_value in _pending_runs.keys():
		var request_id := String(request_id_value)
		var state: Dictionary = _pending_runs[request_id]
		var graph: PFGraph = state.get("graph")
		if (
			graph != null
			and graph.id == graph_id
			and (
				generate_node_id.is_empty()
				or String(state.get("generate_node_id", "")) == generate_node_id
			)
		):
			var run_id := String(state.get("run_id", ""))
			if not _canceling_runs.has(run_id):
				_coordinator.begin_cancel_cutoff(run_id)
				_canceling_runs[run_id] = true
			var provider: PFProvider = ProviderService.get_provider(
				String(state.get("provider_id", ""))
			)
			state["cancel_pending"] = true
			_pending_runs[request_id] = state
			var cancel_task: Variant = provider.cancel(request_id) if provider != null else null
			if cancel_task != null:
				var on_resolved := _on_cancel_resolved.bind(
					String(state.get("provider_id", "")), request_id
				)
				var on_rejected := _on_cancel_rejected.bind(request_id)
				cancel_task.resolved.connect(on_resolved, CONNECT_ONE_SHOT)
				cancel_task.rejected.connect(on_rejected, CONNECT_ONE_SHOT)
				canceled = true
			else:
				state["cancel_pending"] = false
				_pending_runs[request_id] = state
	return canceled


# gdlint: disable=max-returns
func _queue_graph(
	graph: PFGraph,
	batch_node_id: String,
	batch_card_id: String,
	generate_node_id: String,
	provider_id: String
) -> void:
	if generate_node_id.is_empty() or graph.get_node(generate_node_id) == null:
		var missing_target := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % missing_target
		return
	var target_state := {
		"graph": graph,
		"generate_node_id": generate_node_id,
		"batch_node_id": batch_node_id,
	}
	var request_result := _requests_for_graph(graph, generate_node_id, provider_id)
	if not bool(request_result.get("ok", false)):
		var issue: Dictionary = request_result.get(
			"issue", {"code": "invalid_request", "field": "", "args": {}}
		)
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % String(issue["code"])
		return
	var descriptor: Dictionary = (
		_mock_descriptor()
		if provider_id == "mock"
		else ProviderService.get_model_descriptor(
			provider_id, String(request_result["requests"][0].get("model_id", ""))
		)
	)
	var display_name: String = String(descriptor.get("display_name", provider_id))
	if provider_id != "mock" and not ProviderService.get_selectable_provider_ids().has(provider_id):
		if provider_id == "openai_image":
			_status_label.text = Strings.STATUS_OPENAI_SESSION_REQUIRED
			configure_session()
		else:
			_status_label.text = (
				Strings.STATUS_PROVIDER_CREDENTIALS_REQUIRED_FORMAT % display_name
			)
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", _status_label.text)
		_refresh_output_card(target_state)
		return
	var requests: Array = request_result["requests"]
	for request in requests:
		if provider_id == "mock":
			continue
		var validation_message := _cloud_request_validation_message(
			provider_id, request, display_name
		)
		if not validation_message.is_empty():
			_set_graph_status(target_state, "CONTENT_STATUS_FAILED", validation_message)
			_refresh_output_card(target_state)
			_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % validation_message
			return
	var preflight: Dictionary = (
		{
			"decision": "allowed",
			"reason_code": "within_budget",
			"estimated_total_micro_usd": 0,
			"budget_micro_usd": CostService.get_monthly_budget_micro_usd(),
		}
		if provider_id == "mock"
		else CostService.preflight(requests)
	)
	if String(preflight.get("decision", "blocked")) == "blocked":
		var reason := String(preflight.get("reason_code", "invalid_estimate"))
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", reason)
		_refresh_output_card(target_state)
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % reason
		return
	var estimate_micro: Variant = preflight.get("estimated_total_micro_usd")
	var scope_id := IdUtil.uuid_v4()
	var output_node_id := (
		batch_node_id if not batch_node_id.is_empty() else "batch_%s" % IdUtil.uuid_v4().left(8)
	)
	var expected_count := int(request_result["result_count"])
	var run_states: Array[Dictionary] = []
	for request in requests:
		var run_id := String(request["run_id"])
		var planned_slots := []
		for slot_value in request_result.get("slots", []):
			if String(slot_value.get("request_id", "")) == String(request["request_id"]):
				planned_slots.append(Dictionary(slot_value).duplicate(true))
		(
			run_states
			. append(
				{
					"graph": graph,
					"request": request,
					"provider_id": provider_id,
					"provider_name": display_name,
					"anchor": _canvas.get_mouse_world_position(),
					"batch_node_id": output_node_id,
					"batch_card_id": batch_card_id,
					"generate_node_id": generate_node_id,
					"run_id": run_id,
					"scope_id": scope_id,
					"scope_expected_count": expected_count,
					"estimate_micro_usd": _estimate_micro_usd(provider_id, request),
					"provenance_inputs": request_result.get("provenance_inputs", {}),
					"planned_slots": planned_slots,
					"plan": request_result,
				}
			)
		)
	var progress_records := {}
	for run_state in run_states:
		var request: Dictionary = run_state["request"]
		progress_records[String(request["request_id"])] = {
			"state": "queued",
			"attempts": 0,
			"requested_count": int(request["batch"]),
		}
	_run_scopes[scope_id] = {
		"pending": run_states.size(),
		"failed": 0,
		"failed_row_ids": [],
		"progress_records": progress_records,
		"previous_ratio": 0.0,
	}
	_refresh_output_card(run_states[0])
	_refresh_cost_label(estimate_micro)
	if String(preflight["decision"]) == "needs_confirmation":
		_pending_budget_run = {"runs": run_states, "preflight": preflight.duplicate(true)}
		_budget_dialog.dialog_text = (
			Strings.STATUS_PROVIDER_BUDGET_CONFIRM_FORMAT
			% [
				_usd_display(int(estimate_micro)),
				_usd_display(int(preflight["budget_micro_usd"])),
			]
		)
		_status_label.text = _budget_dialog.dialog_text
		_set_graph_status(run_states[0], "CONTENT_STATUS_WAITING", _budget_dialog.dialog_text)
		_budget_dialog.popup_centered()
		return
	if provider_id == "mock":
		_submit_mock_runs(run_states)
		return
	_submit_provider_runs(run_states)


func _submit_mock_runs(run_states: Array) -> void:
	var first: Dictionary = run_states[0]
	var graph: PFGraph = first["graph"]
	var output_node_id := String(first["batch_node_id"])
	var prepared: Dictionary = _prepare_pending_output(run_states)
	if not bool(prepared.get("ok", false)):
		_status_label.text = (
			Strings.STATUS_GRAPH_RUN_FAILED_DETAIL
			% String(prepared.get("error", {}).get("code", "output_create_failed"))
		)
		return
	_set_graph_status(first, "CONTENT_STATUS_RUNNING", "")
	var executed: Dictionary = MockGenerationExecutorScript.execute_prepared(
		graph,
		String(first["generate_node_id"]),
		output_node_id,
		first["plan"],
		AssetLibrary,
		_coordinator
	)
	if not bool(executed.get("ok", false)):
		_status_label.text = (
			Strings.STATUS_GRAPH_RUN_FAILED_DETAIL
			% String(executed.get("error", {}).get("code", "mock_failed"))
		)
		return
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	_set_graph_status(
		first,
		"CONTENT_STATUS_COMPLETE",
		(
			Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT")
			% Array(executed.get("terminal_items", [])).size()
		)
	)
	_refresh_output_card(first)
	_status_label.text = (
		Strings.text("STATUS_GRAPH_RUN_DONE_FORMAT")
		% Array(executed.get("terminal_items", [])).size()
	)


func _submit_provider_runs(run_states: Array) -> void:
	var prepared := _prepare_pending_output(run_states)
	if not bool(prepared.get("ok", false)):
		_status_label.text = (
			Strings.STATUS_GRAPH_RUN_FAILED_DETAIL
			% String(prepared.get("error", {}).get("code", "output_create_failed"))
		)
		return
	for run_state in run_states:
		_submit_provider_run(run_state)


func _prepare_pending_output(run_states: Array) -> Dictionary:
	if run_states.is_empty():
		return {"ok": false, "error": {"code": "empty_run"}}
	var first: Dictionary = run_states[0]
	var graph: PFGraph = first.get("graph")
	var output_node_id := String(first.get("batch_node_id", ""))
	var source_node_id := String(first.get("generate_node_id", ""))
	var plan: Dictionary = first.get("plan", {})
	var prepared: Dictionary = _coordinator.prepare_full_run(
		graph, source_node_id, output_node_id, plan
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	var position := _node_position(graph, source_node_id) + Vector2(480, 0)
	var card: Node = _canvas._add_batch_card(
		[],
		position,
		Strings.text("BATCH_DEFAULT_LABEL"),
		IdUtil.uuid_v4(),
		false,
		graph.id,
		output_node_id
	)
	if card == null:
		_coordinator.rollback_pending_run(graph, prepared["rollback_token"])
		return {"ok": false, "error": {"code": "output_card_create_failed"}}
	for run_state_value in run_states:
		var run_state: Dictionary = run_state_value
		run_state["batch_card_id"] = String(card.item_id)
		run_state["rollback_token"] = prepared["rollback_token"]
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	return prepared


func _cloud_request_validation_message(
	provider_id: String, request: Dictionary, display_name: String
) -> String:
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(request.get("model_id", ""))
	)
	if (
		not _request_reference_images(request).is_empty()
		and not bool(descriptor.get("capabilities", {}).get("img2img", false))
	):
		return Strings.text("CONTENT_DETAIL_REFERENCE_UNSUPPORTED_FORMAT") % display_name
	var error: Variant = ProviderService.validate_generation_request(provider_id, request)
	return String(error.get("code", "")) if error is Dictionary else ""


func _submit_provider_run(run_state: Dictionary) -> void:
	var provider_id := String(run_state["provider_id"])
	var display_name := String(run_state["provider_name"])
	var request: Dictionary = run_state["request"]
	var task: Variant = ProviderService.generate(provider_id, request)
	if task == null or task is Dictionary:
		var unavailable := Strings.text("CONTENT_DETAIL_PROVIDER_UNAVAILABLE")
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, unavailable]
		)
		_set_graph_status(run_state, "CONTENT_STATUS_FAILED", unavailable)
		_refresh_output_card(run_state)
		return
	var request_id := String(request["request_id"])
	_pending_runs[request_id] = run_state
	var estimate_micro: Variant = run_state.get("estimate_micro_usd")
	var detail := (
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % _usd_display(int(estimate_micro))
		if estimate_micro is int
		else ""
	)
	_set_graph_status(run_state, "CONTENT_STATUS_RUNNING", detail)
	_refresh_output_card(run_state)
	task.progress.connect(_on_progress.bind(request_id))
	task.completed.connect(_on_finished.bind(request_id))
	task.failed.connect(_on_failed.bind(request_id))
	task.canceled.connect(_on_canceled)
	_status_label.text = Strings.STATUS_PROVIDER_GENERATE_QUEUED_FORMAT % display_name


func get_budget_dialog() -> ConfirmationDialog:
	return _budget_dialog


func _confirm_budget_run() -> void:
	if _pending_budget_run.is_empty():
		return
	var pending := _pending_budget_run
	_pending_budget_run = {}
	_submit_provider_runs(pending.get("runs", []))


func _on_progress(value: Dictionary, request_id: String) -> void:
	var state: Dictionary = _pending_runs.get(request_id, {})
	if state.is_empty() or bool(state.get("cancel_pending", false)):
		return
	var graph := _latest_graph_for_state(state)
	if graph == null:
		return
	state["graph"] = graph
	_pending_runs[request_id] = state
	var applied: Dictionary = _coordinator.apply_provider_progress(
		graph, String(state.get("batch_node_id", "")), request_id, value
	)
	if not bool(applied.get("ok", false)) or bool(applied.get("ignored", false)):
		return
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	var display_name := String(state.get("provider_name", "Provider"))
	var aggregate: Dictionary = _coordinator.run_progress(
		graph.get_node_params(String(state.get("batch_node_id", ""))),
		String(state.get("run_id", ""))
	)
	var ratio: Variant = aggregate.get("ratio")
	var message := String(value.get("phase", ""))
	if ratio == null:
		_set_graph_status(
			state, "CONTENT_STATUS_RUNNING", Strings.text("CONTENT_PLACEHOLDER_WAITING")
		)
		_status_label.text = Strings.STATUS_PROVIDER_GENERATE_QUEUED_FORMAT % display_name
	else:
		var percent := roundi(float(ratio) * 100.0)
		_set_graph_status(
			state,
			"CONTENT_STATUS_RUNNING",
			Strings.text("CONTENT_DETAIL_PROGRESS_FORMAT") % [percent, message]
		)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_RUNNING_FORMAT % [display_name, percent, message]
		)


func _on_finished(result: Variant, task_id: String) -> void:
	if not _pending_runs.has(task_id) or not (result is Dictionary):
		return
	var state: Dictionary = _pending_runs[task_id]
	if bool(state.get("cancel_pending", false)):
		return
	_pending_runs.erase(task_id)
	var original_graph: PFGraph = state["graph"]
	var latest_graph_data := ProjectService.get_graph_data(original_graph.id)
	var graph: PFGraph = (
		GraphScript.from_json(latest_graph_data)
		if not latest_graph_data.is_empty()
		else original_graph
	)
	state["graph"] = graph
	var request: Dictionary = state["request"]
	var provider_id := String(state["provider_id"])
	var display_name := String(state["provider_name"])
	var batch_node_id := String(state["batch_node_id"])
	var batch_card_id := String(state["batch_card_id"])
	var mapped: Dictionary = ProviderResultMapperScript.map_result(
		request, state.get("planned_slots", []), result
	)
	if not bool(mapped.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_finish_scope_task(state, true)
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_refresh_output_card(state)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, invalid_response]
		)
		return
	_record_billing_update(provider_id, String(request["request_id"]), result)
	var materialized := _coordinator.apply_provider_mapping(
		graph, batch_node_id, request, mapped, AssetLibrary
	)
	if not bool(materialized.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_finish_scope_task(state, true)
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_refresh_output_card(state)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, invalid_response]
		)
		return
	var asset_ids: Array = BatchNodeScript.get_visible_asset_ids(
		graph.get_node_params(batch_node_id)
	)
	var scope_result := _finish_scope_task(
		state,
		String(mapped.get("state", "failed")) != "succeeded",
		String(mapped.get("state", "failed")),
	)
	var scope_done := bool(scope_result.get("done", true))
	if scope_done:
		if int(scope_result.get("failed", 0)) > 0:
			state["failed_row_ids"] = scope_result.get("failed_row_ids", [])
			var partial_detail := (
				Strings.text("CONTENT_DETAIL_PARTIAL_FAILURE_FORMAT")
				% [asset_ids.size(), int(scope_result["failed"])]
			)
			_set_graph_status(state, "CONTENT_STATUS_FAILED", partial_detail)
			_refresh_output_card(state)
		else:
			_set_graph_status(
				state,
				"CONTENT_STATUS_COMPLETE",
				Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % asset_ids.size()
			)
			_refresh_output_card(state)
	else:
		_refresh_output_card(state)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if not batch_card_id.is_empty():
		_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, false)
		_status_label.text = Strings.STATUS_GRAPH_RUN_DONE % asset_ids.size()
		return
	var items := _add_canvas_items(graph, asset_ids, state["anchor"])
	if not items.is_empty():
		_focus_bounds(_bounds_for_items(items))
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_DONE_FORMAT % [display_name, asset_ids.size()]
	)


func _on_failed(error: Dictionary, task_id: String) -> void:
	var state: Dictionary = _pending_runs.get(task_id, {})
	if bool(state.get("cancel_pending", false)):
		return
	_pending_runs.erase(task_id)
	var message := String(error.get("code", "")).strip_edges()
	if state.is_empty():
		return
	var original_graph: PFGraph = state.get("graph")
	var latest_graph_data := ProjectService.get_graph_data(original_graph.id)
	var graph: PFGraph = (
		GraphScript.from_json(latest_graph_data)
		if not latest_graph_data.is_empty()
		else original_graph
	)
	state["graph"] = graph
	var request: Dictionary = state.get("request", {})
	var mapped: Dictionary = ProviderResultMapperScript.map_provider_failure(
		request, state.get("planned_slots", []), error
	)
	if bool(mapped.get("ok", false)):
		var materialized := _coordinator.apply_provider_mapping(
			graph, String(state.get("batch_node_id", "")), request, mapped, AssetLibrary
		)
		if bool(materialized.get("ok", false)):
			ProjectService.set_graph_data(graph.id, graph.to_json(), true)
		else:
			message = "invalid_provider_mapping"
	else:
		message = "ambiguous_result"
	if message.is_empty():
		message = Strings.text("CONTENT_DETAIL_UNKNOWN_ERROR")
	var scope_result := _finish_scope_task(state, true, "failed")
	if bool(scope_result.get("done", true)):
		_set_graph_status(state, "CONTENT_STATUS_FAILED", message)
		_refresh_output_card(state)
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT
		% [String(state.get("provider_name", "Provider")), message]
	)


func _on_canceled(task_id: String) -> void:
	var state: Dictionary = _pending_runs.get(task_id, {})
	if bool(state.get("cancel_pending", false)):
		state["generation_canceled"] = true
		_pending_runs[task_id] = state
		return
	_finalize_canceled(task_id)


func _finalize_canceled(task_id: String) -> void:
	var state: Dictionary = _pending_runs.get(task_id, {})
	_pending_runs.erase(task_id)
	var scope_result := _finish_scope_task(state, true, "canceled")
	if bool(scope_result.get("done", true)):
		_set_graph_status(state, "CONTENT_STATUS_CANCELED", Strings.text("CONTENT_DETAIL_CANCELED"))
		_refresh_output_card(state)
	if bool(scope_result.get("done", true)):
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_CANCELED_FORMAT
			% String(state.get("provider_name", "Provider"))
		)
	_refresh_cost_label()


func _on_cancel_resolved(result: Dictionary, provider_id: String, request_id: String) -> void:
	if not _pending_runs.has(request_id):
		return
	var state: Dictionary = _pending_runs[request_id]
	_record_billing_update(provider_id, request_id, result.get("billing_update"))
	var graph := _latest_graph_for_state(state)
	if graph == null:
		_finalize_canceled(request_id)
		return
	state["graph"] = graph
	_pending_runs[request_id] = state
	var applied: Dictionary = _coordinator.resolve_cancel(
		graph, String(state.get("batch_node_id", "")), request_id, result
	)
	if not bool(applied.get("ok", false)):
		return
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	_finalize_canceled(request_id)


func _on_cancel_rejected(error: Dictionary, request_id: String) -> void:
	if not _pending_runs.has(request_id):
		return
	var state: Dictionary = _pending_runs[request_id]
	var graph := _latest_graph_for_state(state)
	if graph == null:
		return
	state["graph"] = graph
	_pending_runs[request_id] = state
	var applied: Dictionary = _coordinator.reject_cancel(
		graph, String(state.get("batch_node_id", "")), request_id, error
	)
	if not bool(applied.get("ok", false)):
		return
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	_pending_runs.erase(request_id)
	var scope_result := _finish_scope_task(state, true, "failed")
	if bool(scope_result.get("done", true)):
		_set_graph_status(
			state, "CONTENT_STATUS_FAILED", String(error.get("code", "cancel_failed"))
		)
		_refresh_output_card(state)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT
			% [
				String(state.get("provider_name", "Provider")),
				String(error.get("code", "cancel_failed"))
			]
		)


func _record_billing_update(provider_id: String, request_id: String, value: Variant) -> void:
	if not (value is Dictionary):
		return
	var actual_micro: Variant = CostService.parse_usd_to_micro(value.get("actual_cost_usd"))
	if not (actual_micro is int):
		return
	var charge_id := String(value.get("charge_id", ""))
	var ledger_key := (
		"%s:charge:%s" % [provider_id, charge_id]
		if not charge_id.is_empty()
		else "%s:request:%s" % [provider_id, request_id]
	)
	CostService.record_once(ledger_key, int(actual_micro))


func _finish_scope_task(state: Dictionary, failed: bool, terminal_state: String = "") -> Dictionary:
	var scope_id := String(state.get("scope_id", ""))
	if scope_id.is_empty() or not _run_scopes.has(scope_id):
		return {"done": true}
	var scope: Dictionary = _run_scopes[scope_id]
	var records: Dictionary = scope.get("progress_records", {})
	var request_id := String(Dictionary(state.get("request", {})).get("request_id", ""))
	if records.has(request_id):
		var record: Dictionary = records[request_id]
		record["state"] = (
			terminal_state
			if not terminal_state.is_empty()
			else ("failed" if failed else "succeeded")
		)
		record.erase("progress")
		records[request_id] = record
		scope["progress_records"] = records
		var aggregate: Dictionary = ProviderRunProgressScript.aggregate(
			records.values(),
			int(state.get("scope_expected_count", 0)),
			float(scope["previous_ratio"])
		)
		if aggregate.get("ratio") != null:
			scope["previous_ratio"] = float(aggregate["ratio"])
		scope["aggregate_progress"] = aggregate
	scope["pending"] = maxi(0, int(scope.get("pending", 1)) - 1)
	if failed:
		scope["failed"] = int(scope.get("failed", 0)) + 1
		var row_id := String(Dictionary(state.get("request", {})).get("source_row_id", ""))
		if not row_id.is_empty() and not scope["failed_row_ids"].has(row_id):
			scope["failed_row_ids"].append(row_id)
	_run_scopes[scope_id] = scope
	var result := {
		"done": int(scope["pending"]) == 0,
		"failed": int(scope["failed"]),
		"failed_row_ids": Array(scope.get("failed_row_ids", [])).duplicate(),
	}
	if bool(result["done"]):
		_run_scopes.erase(scope_id)
	return result


func _set_graph_status(state: Dictionary, status_key: String, detail: String = "") -> void:
	var graph: PFGraph = state.get("graph")
	if graph != null:
		_canvas._set_graph_node_status(
			graph.id, String(state.get("generate_node_id", "")), status_key, detail
		)


func _refresh_output_card(state: Dictionary) -> void:
	var graph: PFGraph = state.get("graph")
	var batch_node_id := String(state.get("batch_node_id", ""))
	if graph == null or batch_node_id.is_empty():
		return
	_canvas._refresh_graph_batch_card(graph.id, batch_node_id)


func _refresh_cost_label(estimate_micro: Variant = null) -> void:
	if _cost_label == null:
		return
	var total := _usd_display(CostService.get_month_total_micro_usd())
	_cost_label.text = (
		Strings.text("COST_MONTH_ESTIMATE_FORMAT") % [total, _usd_display(int(estimate_micro))]
		if estimate_micro is int
		else Strings.text("COST_MONTH_FORMAT") % total
	)


func _estimate_micro_usd(provider_id: String, request: Dictionary) -> Variant:
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	if provider == null:
		return null
	return CostService.parse_usd_to_micro(provider.estimate_cost(request))


func _usd_display(micro_usd: int) -> float:
	return float(micro_usd) / 1000000.0


func _make_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_openai_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "OpenAI Generate Batch"
	(
		graph
		. add_node(
			ObjectListNodeScript.new(),
			"objects",
			{
				"rows":
				[
					{
						"id": "default",
						"text": Strings.OPENAI_V1_FIXED_PROMPT,
						"count": 2,
						"enabled": true,
					}
				]
			},
			Vector2(0, 0)
		)
	)
	graph.add_node(
		PromptPresetNodeScript.new(),
		"prompt_preset",
		{"preset": PromptPresetNodeScript.DEFAULT_PRESET.duplicate(true)},
		Vector2(0, 150)
	)
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"target_width": 32,
				"target_height": 32,
				"batch_size": 2,
				"seed": 1,
				"extra": {},
			},
			Vector2(280, 75)
		)
	)
	graph.add_edge("objects", "subjects", "generate", "subjects")
	graph.add_edge("prompt_preset", "prefix", "generate", "prefix")
	return graph


func _requests_for_graph(
	graph: PFGraph, generate_node_id: String, provider_id: String
) -> Dictionary:
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	if provider == null and provider_id != "mock":
		return {
			"ok": false,
			"issue": {"code": "invalid_provider_model", "field": "provider_id", "args": {}},
			"requests": [],
			"slots": [],
		}
	var descriptors: Array = (
		[_mock_descriptor()] if provider_id == "mock" else provider.get_model_descriptors()
	)
	return GraphGenerationPlanBuilderScript.build(
		graph, generate_node_id, provider_id, descriptors, AssetLibrary
	)


func _mock_descriptor() -> Dictionary:
	return GraphGenerationPlanBuilderScript.mock_descriptor()


func _provider_id_for_graph(graph: PFGraph, generate_node_id: String) -> String:
	var node: PFNode = graph.get_node(generate_node_id)
	if node == null:
		return ""
	if node.get_type() == "comfyui.run_workflow":
		return "comfyui"
	return String(graph.get_node_params(generate_node_id).get("provider_id", ""))


func _generate_node_for_batch(graph: PFGraph, batch_node_id: String) -> String:
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[0]) != batch_node_id:
			continue
		var source: PFNode = graph.get_node(String(from_data[0]))
		if source != null and source.get_type() in ["ai_generate", "comfyui.run_workflow"]:
			return String(from_data[0])
	return ""


func _direct_source_node_ids(graph: PFGraph, target_node_id: String) -> Array[String]:
	var result: Array[String] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		var source_id := String(from_data[0])
		if String(to_data[0]) == target_node_id and not result.has(source_id):
			result.append(source_id)
	return result


func _request_reference_images(request: Dictionary) -> Array:
	var value: Variant = request.get("ref_images", [])
	return value if value is Array else []


func _add_canvas_items(graph: PFGraph, asset_ids: Array, anchor: Vector2) -> Array:
	var items := []
	for node_id in ["objects", "prompt_preset", "generate"]:
		var node_item: Node = _canvas._add_graph_node_card(
			graph.id, node_id, anchor + _node_position(graph, node_id), "", false
		)
		if node_item != null:
			items.append(node_item)
	var batch_card: Node = _canvas._add_batch_card(
		asset_ids,
		anchor + _node_position(graph, "batch_1"),
		Strings.OPENAI_BATCH_LABEL,
		"",
		false,
		graph.id,
		"batch_1"
	)
	if batch_card != null:
		items.append(batch_card)
	return items


func _focus_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var target_zoom := minf(
		_canvas.size.x * 0.62 / bounds.size.x, _canvas.size.y * 0.62 / bounds.size.y
	)
	_canvas.set_camera_zoom(target_zoom, _canvas.size * 0.5)
	_canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)


func _bounds_for_items(items: Array) -> Rect2:
	var bounds: Rect2 = items[0].get_canvas_bounds()
	for index in range(1, items.size()):
		bounds = bounds.merge(items[index].get_canvas_bounds())
	return bounds


func _node_position(graph: PFGraph, node_id: String) -> Vector2:
	var node_data: Dictionary = graph.nodes.get(node_id, {})
	var raw_position: Variant = node_data.get("position", [0, 0])
	return Vector2(float(raw_position[0]), float(raw_position[1])).round()


func _latest_graph_for_state(state: Dictionary) -> PFGraph:
	var original: PFGraph = state.get("graph")
	if original == null:
		return null
	var latest := ProjectService.get_graph_data(original.id)
	return GraphScript.from_json(latest) if not latest.is_empty() else original
