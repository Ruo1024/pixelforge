# gdlint: disable=max-file-lines
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
const GenerationCountPolicyScript := preload("res://services/generation_count_policy.gd")
const MockGenerationExecutorScript := preload("res://services/mock_generation_executor.gd")
const ProviderResultMapperScript := preload("res://services/provider_result_mapper.gd")
const ProviderRunProgressScript := preload("res://services/provider_run_progress.gd")
const OutputAutoPlacementScript := preload("res://services/output_auto_placement.gd")
const CardContractScript := preload("res://ui/canvas/canvas_card_contract.gd")
const MonotonicClockScript := preload("res://infra/monotonic_clock.gd")
const GenerationErrorDialogPresenterScript := preload(
	"res://ui/dialogs/generation_error_dialog_presenter.gd"
)
const IdUtil := preload("res://core/util/id_util.gd")

var _canvas: Control = null
var _status_label: Label = null
var _provider_settings_dialog: ConfirmationDialog = null
var _count_dialog: ConfirmationDialog = null
var _pending_runs := {}
var _pending_count_run := {}
var _run_scopes := {}
var _canceling_runs := {}
var _terminal_run_targets := {}
var _pending_regenerate := {}
var _coordinator: PFGenerationRunCoordinator
var _error_presenter: PFGenerationErrorDialogPresenter
var _regenerate_dialog: ConfirmationDialog


func setup(
	canvas: Control,
	status_label: Label,
	_retired_bottom_label: Label = null,
	provider_settings_dialog: ConfirmationDialog = null
) -> void:
	_canvas = canvas
	_status_label = status_label
	_provider_settings_dialog = provider_settings_dialog
	_coordinator = GenerationRunCoordinatorScript.new()
	var clock: RefCounted = MonotonicClockScript.new()
	_coordinator.configure_clock(clock)
	if _canvas.has_method("configure_run_edge_renderer"):
		_canvas.configure_run_edge_renderer(_coordinator, clock)
	_error_presenter = GenerationErrorDialogPresenterScript.new()
	_error_presenter.name = "GenerationErrorDialogPresenter"
	_error_presenter.action_requested.connect(_on_error_dialog_action)
	add_child(_error_presenter)
	_regenerate_dialog = ConfirmationDialog.new()
	_regenerate_dialog.name = "GenerationRegenerateConfirmDialog"
	_regenerate_dialog.confirmed.connect(_confirm_regenerate_from_error)
	_regenerate_dialog.canceled.connect(func() -> void: _pending_regenerate.clear())
	add_child(_regenerate_dialog)
	_count_dialog = ConfirmationDialog.new()
	_count_dialog.name = "GenerationCountConfirmDialog"
	_count_dialog.title = Strings.text("DIALOG_GENERATION_COUNT_TITLE")
	_count_dialog.confirmed.connect(_confirm_count_run)
	_count_dialog.canceled.connect(func() -> void: _pending_count_run.clear())
	add_child(_count_dialog)


func configure_session() -> void:
	if _provider_settings_dialog != null:
		_provider_settings_dialog.show_settings("openai_image")


func get_run_coordinator() -> PFGenerationRunCoordinator:
	return _coordinator


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


func retry_graph(graph: PFGraph, selected_node_id: String) -> void:
	var output_node_id := _retry_output_node_id(graph, selected_node_id)
	if output_node_id.is_empty():
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % "retry_source_unavailable"
		)
		return
	var params := graph.get_node_params(output_node_id)
	var failed_slots := []
	for slot_value in params.get("result_slots", []):
		var slot: Dictionary = slot_value
		if (
			String(slot.get("status", "")) != "failed"
			or not (slot.get("error") is Dictionary)
			or not bool(slot["error"].get("retryable", false))
		):
			continue
		var retry_slot: Dictionary = slot.duplicate(true)
		retry_slot["input_snapshot"] = (
			Dictionary(
				params.get("input_snapshots", {}).get(String(slot.get("input_snapshot_id", "")), {})
			)
			. duplicate(true)
		)
		failed_slots.append(retry_slot)
	if failed_slots.is_empty():
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % "retry_source_unavailable"
		)
		return
	var snapshot: Dictionary = failed_slots[0]["input_snapshot"]
	var provider_id := String(snapshot.get("provider_id", ""))
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(snapshot.get("model_id", ""))
	)
	var max_batch := maxi(1, int(descriptor.get("capabilities", {}).get("max_batch", 1)))
	var plan: Dictionary = _coordinator.prepare_retry_preflight(
		failed_slots, max_batch, "run_%s" % IdUtil.uuid_v4(), AssetLibrary
	)
	if not bool(plan.get("ok", false)):
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
			% String(plan.get("issue", {}).get("code", "retry_source_unavailable"))
		)
		return
	var run_states := _retry_run_states(graph, output_node_id, provider_id, plan)
	var preflight: Dictionary = plan.get("preflight", {})
	if String(preflight.get("decision", "blocked")) == "blocked":
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
			% String(preflight.get("reason_code", "invalid_request"))
		)
		return
	_submit_retry_runs(run_states)


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
		_status_label.text = Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % missing_target
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
		_status_label.text = Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % String(issue["code"])
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
			_status_label.text = Strings.text("STATUS_OPENAI_SESSION_REQUIRED")
			configure_session()
		else:
			_status_label.text = (
				Strings.text("STATUS_PROVIDER_CREDENTIALS_REQUIRED_FORMAT") % display_name
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
			_status_label.text = Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % validation_message
			return
	var preflight: Dictionary = _coordinator.preflight_plan(request_result, provider_id == "mock")
	if String(preflight.get("decision", "blocked")) == "blocked":
		var reason := String(preflight.get("reason_code", "invalid_request"))
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", reason)
		_refresh_output_card(target_state)
		_status_label.text = Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL") % reason
		return
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
					"provenance_inputs": request_result.get("provenance_inputs", {}),
					"planned_slots": planned_slots,
					"plan": request_result,
				}
			)
		)
	if bool(GenerationCountPolicyScript.validate(expected_count)["requires_confirmation"]):
		_pending_count_run = {"runs": run_states, "provider_id": provider_id}
		_count_dialog.dialog_text = (
			Strings.text("DIALOG_GENERATION_COUNT_CONFIRM_FORMAT") % expected_count
		)
		_status_label.text = _count_dialog.dialog_text
		_count_dialog.popup_centered()
		return
	_start_full_runs(run_states, provider_id)


func _start_full_runs(run_states: Array, provider_id: String) -> void:
	if run_states.is_empty():
		return
	var first: Dictionary = run_states[0]
	var scope_id := String(first.get("scope_id", ""))
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
	if provider_id == "mock":
		_submit_mock_runs(run_states)
	else:
		_submit_provider_runs(run_states)


func _submit_mock_runs(run_states: Array) -> void:
	var first: Dictionary = run_states[0]
	var graph: PFGraph = first["graph"]
	var output_node_id := String(first["batch_node_id"])
	var prepared: Dictionary = _prepare_pending_output(run_states)
	if not bool(prepared.get("ok", false)):
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
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
		_rollback_pending_output(run_states)
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
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
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
			% String(prepared.get("error", {}).get("code", "output_create_failed"))
		)
		return
	_dispatch_provider_runs(run_states)


func _submit_retry_runs(run_states: Array) -> void:
	var prepared := _prepare_retry_output(run_states)
	if not bool(prepared.get("ok", false)):
		_status_label.text = (
			Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL")
			% String(prepared.get("error", {}).get("code", "retry_source_unavailable"))
		)
		return
	_dispatch_provider_runs(run_states)


func _dispatch_provider_runs(run_states: Array) -> void:
	var submitted := 0
	for run_state in run_states:
		if not _submit_provider_run(run_state):
			if submitted == 0:
				_rollback_pending_output(run_states)
			return
		submitted += 1


func _prepare_retry_output(run_states: Array) -> Dictionary:
	if run_states.is_empty():
		return {"ok": false, "error": {"code": "empty_run"}}
	var first: Dictionary = run_states[0]
	var graph: PFGraph = first["graph"]
	var prepared: Dictionary = _coordinator.prepare_retry_run(
		graph, String(first["batch_node_id"]), first["plan"]
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	for run_state_value in run_states:
		var run_state: Dictionary = run_state_value
		run_state["rollback_token"] = prepared["rollback_token"]
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	return prepared


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
	var bounds := _canvas_item_bounds(graph, source_node_id)
	var output_size := Vector2(CardContractScript.default_size_for_type("batch"))
	var position: Vector2 = OutputAutoPlacementScript.find_position(
		bounds["source"], bounds["existing"], output_size
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	var card: Node = _canvas._add_graph_node_card(
		graph.id, output_node_id, position, IdUtil.uuid_v4(), false
	)
	if card == null:
		_coordinator.rollback_pending_run(graph, prepared["rollback_token"])
		ProjectService.set_graph_data(graph.id, graph.to_json(), true)
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


func _submit_provider_run(run_state: Dictionary) -> bool:
	var provider_id := String(run_state["provider_id"])
	var display_name := String(run_state["provider_name"])
	var request: Dictionary = run_state["request"]
	var task: Variant = ProviderService.generate(provider_id, request)
	if task == null or task is Dictionary:
		var unavailable := Strings.text("CONTENT_DETAIL_PROVIDER_UNAVAILABLE")
		_status_label.text = (
			Strings.text("STATUS_PROVIDER_GENERATE_FAILED_FORMAT") % [display_name, unavailable]
		)
		_set_graph_status(run_state, "CONTENT_STATUS_FAILED", unavailable)
		_refresh_output_card(run_state)
		return false
	var request_id := String(request["request_id"])
	_pending_runs[request_id] = run_state
	_set_graph_status(run_state, "CONTENT_STATUS_RUNNING", "")
	_refresh_output_card(run_state)
	task.progress.connect(_on_progress.bind(request_id))
	task.completed.connect(_on_finished.bind(request_id))
	task.failed.connect(_on_failed.bind(request_id))
	task.canceled.connect(_on_canceled)
	_status_label.text = Strings.text("STATUS_PROVIDER_GENERATE_QUEUED_FORMAT") % display_name
	return true


func _rollback_pending_output(run_states: Array) -> void:
	if run_states.is_empty():
		return
	var first: Dictionary = run_states[0]
	var graph: PFGraph = first.get("graph")
	var rollback_token: Dictionary = first.get("rollback_token", {})
	if graph == null or rollback_token.is_empty():
		return
	_coordinator.rollback_pending_run(graph, rollback_token)
	var card_id := String(first.get("batch_card_id", ""))
	if not bool(first.get("is_retry", false)) and not card_id.is_empty():
		_canvas._remove_item_direct(card_id)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)


func get_count_confirmation_dialog() -> ConfirmationDialog:
	return _count_dialog


func _confirm_count_run() -> void:
	if _pending_count_run.is_empty():
		return
	var pending := _pending_count_run
	_pending_count_run = {}
	_start_full_runs(pending.get("runs", []), String(pending.get("provider_id", "")))


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
		_status_label.text = Strings.text("STATUS_PROVIDER_GENERATE_QUEUED_FORMAT") % display_name
	else:
		var percent := roundi(float(ratio) * 100.0)
		_set_graph_status(
			state,
			"CONTENT_STATUS_RUNNING",
			Strings.text("CONTENT_DETAIL_PROGRESS_FORMAT") % [percent, message]
		)
		_status_label.text = (
			Strings.text("STATUS_PROVIDER_GENERATE_RUNNING_FORMAT")
			% [display_name, percent, message]
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
			Strings.text("STATUS_PROVIDER_GENERATE_FAILED_FORMAT")
			% [display_name, invalid_response]
		)
		return
	var materialized := _coordinator.apply_provider_mapping(
		graph, batch_node_id, request, mapped, AssetLibrary
	)
	if not bool(materialized.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_finish_scope_task(state, true)
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_refresh_output_card(state)
		_status_label.text = (
			Strings.text("STATUS_PROVIDER_GENERATE_FAILED_FORMAT")
			% [display_name, invalid_response]
		)
		return
	var asset_ids: Array = BatchNodeScript.get_visible_asset_ids(
		graph.get_node_params(batch_node_id)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
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
	if scope_done and int(scope_result.get("failed", 0)) > 0:
		_present_terminal_error(state, graph)
	if not batch_card_id.is_empty():
		_status_label.text = Strings.text("STATUS_GRAPH_RUN_DONE") % asset_ids.size()
		return
	var items := _add_canvas_items(graph, state["anchor"])
	if not items.is_empty():
		_focus_bounds(_bounds_for_items(items))
	_status_label.text = (
		Strings.text("STATUS_PROVIDER_GENERATE_DONE_FORMAT") % [display_name, asset_ids.size()]
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
		_present_terminal_error(state, graph)
	_status_label.text = (
		Strings.text("STATUS_PROVIDER_GENERATE_FAILED_FORMAT")
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
			Strings.text("STATUS_PROVIDER_GENERATE_CANCELED_FORMAT")
			% String(state.get("provider_name", "Provider"))
		)


func _on_cancel_resolved(result: Dictionary, _provider_id: String, request_id: String) -> void:
	if not _pending_runs.has(request_id):
		return
	var state: Dictionary = _pending_runs[request_id]
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
		_present_terminal_error(state, graph, "user_canceled")
		_status_label.text = (
			Strings.text("STATUS_PROVIDER_GENERATE_FAILED_FORMAT")
			% [
				String(state.get("provider_name", "Provider")),
				String(error.get("code", "cancel_failed"))
			]
		)


func _present_terminal_error(state: Dictionary, graph: PFGraph, mode: String = "terminal") -> void:
	if _error_presenter == null:
		return
	var output_node_id := String(state.get("batch_node_id", ""))
	if graph == null or graph.get_node(output_node_id) == null:
		return
	var params := graph.get_node_params(output_node_id)
	var run_id := String(state.get("run_id", params.get("source_run_id", "")))
	var failed_slots := []
	var succeeded_count := 0
	for slot_value in params.get("result_slots", []):
		var slot: Dictionary = slot_value
		if bool(slot.get("unexpected", false)):
			continue
		if String(slot.get("status", "")) == "succeeded":
			succeeded_count += 1
		elif (
			String(slot.get("run_id", "")) == run_id
			and String(slot.get("status", "")) == "failed"
			and slot.get("error") is Dictionary
		):
			failed_slots.append(slot.duplicate(true))
	if failed_slots.is_empty():
		return
	_terminal_run_targets[run_id] = {
		"graph_id": graph.id,
		"output_node_id": output_node_id,
		"source_node_id": String(params.get("source_node_id", "")),
		"provider_id": String(state.get("provider_id", "")),
	}
	(
		_error_presenter
		. present(
			{
				"mode": mode,
				"run_id": run_id,
				"settled": true,
				"succeeded_count": succeeded_count,
				"failed_slots": failed_slots,
				"cancel_failed": mode == "user_canceled",
				"terminal_steps":
				[
					"edge_stopped",
					"successes_saved",
					"failed_slots_updated",
					"safe_errors_recorded",
					"dialog_ready",
				],
			}
		)
	)


func _on_error_dialog_action(run_id: String, action_id: String, _context: Dictionary) -> void:
	var target: Dictionary = _terminal_run_targets.get(run_id, {})
	if target.is_empty():
		return
	match action_id:
		"retry_failed":
			var graph_data := ProjectService.get_graph_data(String(target["graph_id"]))
			if not graph_data.is_empty():
				retry_graph(GraphScript.from_json(graph_data), String(target["output_node_id"]))
		"open_provider_settings":
			if _provider_settings_dialog != null:
				_provider_settings_dialog.show_settings(String(target["provider_id"]))
		"regenerate_confirm":
			_pending_regenerate = target.duplicate(true)
			_regenerate_dialog.title = LocalizationService.text(
				"GEN_ERROR_ACTION_REGENERATE_CONFIRM"
			)
			_regenerate_dialog.dialog_text = LocalizationService.text(
				"GEN_ERROR_ACTION_REGENERATE_CONFIRM"
			)
			_regenerate_dialog.popup_centered()
		"edit_prompt", "return_generation_card":
			_canvas._refresh_graph_node_card(
				String(target["graph_id"]), String(target["source_node_id"])
			)
		_:
			return


func _confirm_regenerate_from_error() -> void:
	var target := _pending_regenerate
	_pending_regenerate = {}
	if target.is_empty():
		return
	var graph_data := ProjectService.get_graph_data(String(target["graph_id"]))
	if graph_data.is_empty():
		return
	run_graph(GraphScript.from_json(graph_data), "", "", String(target["source_node_id"]))


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
						"text": Strings.text("OPENAI_V1_FIXED_PROMPT"),
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
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 2,
				"seed": -1,
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


func _retry_output_node_id(graph: PFGraph, selected_node_id: String) -> String:
	var selected: PFNode = graph.get_node(selected_node_id)
	if selected != null and selected.get_type() == "batch":
		return selected_node_id
	for node_id_value in graph.nodes.keys():
		var node_id := String(node_id_value)
		var node: PFNode = graph.get_node(node_id)
		if node == null or node.get_type() != "batch":
			continue
		var params := graph.get_node_params(node_id)
		if (
			String(params.get("source_node_id", "")) == selected_node_id
			and String(params.get("role", "")) == "current"
		):
			return node_id
	return ""


func _retry_run_states(
	graph: PFGraph, output_node_id: String, provider_id: String, plan: Dictionary
) -> Array[Dictionary]:
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(plan["requests"][0].get("model_id", ""))
	)
	var display_name := String(descriptor.get("display_name", provider_id))
	var scope_id := IdUtil.uuid_v4()
	var card_id := _batch_card_id(graph.id, output_node_id)
	var result: Array[Dictionary] = []
	var progress_records := {}
	for request_value in plan.get("requests", []):
		var request: Dictionary = request_value
		var planned_slots := []
		for slot_value in plan.get("slots", []):
			if String(slot_value.get("request_id", "")) == String(request["request_id"]):
				planned_slots.append(Dictionary(slot_value).duplicate(true))
		(
			result
			. append(
				{
					"graph": graph,
					"request": request,
					"provider_id": provider_id,
					"provider_name": display_name,
					"anchor": _canvas.get_mouse_world_position(),
					"batch_node_id": output_node_id,
					"batch_card_id": card_id,
					"generate_node_id":
					String(graph.get_node_params(output_node_id).get("source_node_id", "")),
					"run_id": String(request["run_id"]),
					"scope_id": scope_id,
					"scope_expected_count": int(plan.get("total_slots", 0)),
					"planned_slots": planned_slots,
					"plan": plan,
					"is_retry": true,
				}
			)
		)
		progress_records[String(request["request_id"])] = {
			"state": "queued", "attempts": 0, "requested_count": int(request["batch"])
		}
	_run_scopes[scope_id] = {
		"pending": result.size(),
		"failed": 0,
		"failed_row_ids": [],
		"progress_records": progress_records,
		"previous_ratio": 0.0,
	}
	return result


func _batch_card_id(graph_id: String, output_node_id: String) -> String:
	for item_value in _canvas._items_by_id.values():
		var item: Node = item_value
		if (
			item != null
			and str(item.get("graph_id")) == graph_id
			and str(item.get("node_id")) == output_node_id
		):
			return str(item.get("item_id"))
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


func _add_canvas_items(graph: PFGraph, anchor: Vector2) -> Array:
	var items := []
	for node_id in ["objects", "prompt_preset", "generate"]:
		var node_item: Node = _canvas._add_graph_node_card(
			graph.id, node_id, anchor + _node_position(graph, node_id), "", false
		)
		if node_item != null:
			items.append(node_item)
	var batch_card: Node = _canvas._add_graph_node_card(
		graph.id, "batch_1", anchor + _node_position(graph, "batch_1"), "", false
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


func _canvas_item_bounds(graph: PFGraph, source_node_id: String) -> Dictionary:
	var existing := []
	var source := Rect2(
		_node_position(graph, source_node_id),
		Vector2(CardContractScript.default_size_for_type("ai_generate"))
	)
	for item_value in _canvas._items_by_id.values():
		var item: Node = item_value
		if item == null or not item.has_method("get_canvas_bounds"):
			continue
		var item_bounds: Rect2 = item.get_canvas_bounds()
		existing.append(item_bounds)
		if str(item.get("graph_id")) == graph.id and str(item.get("node_id")) == source_node_id:
			source = item_bounds
	return {"source": source, "existing": existing}


func _latest_graph_for_state(state: Dictionary) -> PFGraph:
	var original: PFGraph = state.get("graph")
	if original == null:
		return null
	var latest := ProjectService.get_graph_data(original.id)
	return GraphScript.from_json(latest) if not latest.is_empty() else original
