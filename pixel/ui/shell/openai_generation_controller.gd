class_name PFOpenAIGenerationController
extends Node

## 云端 Provider 异步生成闭环；配置统一进入 ProviderSettingsDialog。

const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const GenerationRequestPlannerScript := preload("res://services/generation_request_planner.gd")
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
				cancel_task.resolved.connect(on_resolved, CONNECT_ONE_SHOT)
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
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(request_result["requests"][0].get("model_id", ""))
	)
	var display_name: String = String(descriptor.get("display_name", provider_id))
	if not ProviderService.get_selectable_provider_ids().has(provider_id):
		if provider_id == "openai_image":
			_status_label.text = Strings.STATUS_OPENAI_SESSION_REQUIRED
			configure_session()
		else:
			_status_label.text = (
				Strings.STATUS_PROVIDER_CREDENTIALS_REQUIRED_FORMAT % display_name
			)
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", _status_label.text)
		_set_batch_run_state(target_state, "failed", _status_label.text)
		return
	var requests: Array = request_result["requests"]
	for request in requests:
		var validation_message := _cloud_request_validation_message(
			provider_id, request, display_name
		)
		if not validation_message.is_empty():
			_set_graph_status(target_state, "CONTENT_STATUS_FAILED", validation_message)
			_set_batch_run_state(target_state, "failed", validation_message)
			_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % validation_message
			return
	var preflight: Dictionary = CostService.preflight(requests)
	if String(preflight.get("decision", "blocked")) == "blocked":
		var reason := String(preflight.get("reason_code", "invalid_estimate"))
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", reason)
		_set_batch_run_state(target_state, "failed", reason)
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % reason
		return
	var estimate_micro: Variant = preflight.get("estimated_total_micro_usd")
	var scope_id := IdUtil.uuid_v4()
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
					"batch_node_id": batch_node_id,
					"batch_card_id": batch_card_id,
					"generate_node_id": generate_node_id,
					"run_id": run_id,
					"scope_id": scope_id,
					"scope_expected_count": expected_count,
					"estimate_micro_usd": _estimate_micro_usd(provider_id, request),
					"provenance_inputs": request_result.get("provenance_inputs", {}),
					"planned_slots": planned_slots,
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
	_set_batch_run_state(run_states[0], "waiting", "")
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
	_submit_provider_runs(run_states)


func _submit_provider_runs(run_states: Array) -> void:
	for run_state in run_states:
		_submit_provider_run(run_state)


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
		_set_batch_run_state(run_state, "failed", unavailable)
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
	_set_batch_run_state(run_state, "running", detail)
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
	var display_name := String(state.get("provider_name", "Provider"))
	var ratio: Variant = _apply_scope_progress(state, request_id, value).get("ratio")
	var percent := roundi(float(ratio) * 100.0) if ratio != null else 0
	var message := String(value.get("phase", ""))
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
		_set_batch_run_state(state, "failed", invalid_response)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, invalid_response]
		)
		return
	_record_billing_update(provider_id, String(request["request_id"]), result)
	var runner := GraphRunnerScript.new()
	var materialized := runner.materialize_provider_mapping(
		graph, batch_node_id, request, mapped, AssetLibrary
	)
	if not bool(materialized.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_finish_scope_task(state, true)
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_set_batch_run_state(state, "failed", invalid_response)
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
			_set_batch_run_state(state, "failed", partial_detail)
		else:
			_set_graph_status(
				state,
				"CONTENT_STATUS_COMPLETE",
				Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % asset_ids.size()
			)
			_set_batch_run_state(state, "complete", "", asset_ids.size())
	else:
		_set_batch_run_state(state, "running", "")
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
		var runner := GraphRunnerScript.new()
		var materialized := runner.materialize_provider_mapping(
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
		_set_batch_run_state(state, "failed", message)
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
		_set_batch_run_state(state, "canceled", Strings.text("CONTENT_DETAIL_CANCELED"))
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_CANCELED_FORMAT
		% String(state.get("provider_name", "Provider"))
	)
	_refresh_cost_label()


func _on_cancel_resolved(result: Dictionary, provider_id: String, request_id: String) -> void:
	_record_billing_update(provider_id, request_id, result.get("billing_update"))
	if _pending_runs.has(request_id):
		_finalize_canceled(request_id)


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


func _apply_scope_progress(state: Dictionary, request_id: String, value: Dictionary) -> Dictionary:
	var scope_id := String(state.get("scope_id", ""))
	if scope_id.is_empty() or not _run_scopes.has(scope_id):
		return value
	var scope: Dictionary = _run_scopes[scope_id]
	var records: Dictionary = scope.get("progress_records", {})
	if not records.has(request_id):
		return value
	records[request_id] = ProviderRunProgressScript.apply_provider_progress(
		records[request_id], value
	)
	scope["progress_records"] = records
	var aggregate: Dictionary = ProviderRunProgressScript.aggregate(
		records.values(), int(state.get("scope_expected_count", 0)), float(scope["previous_ratio"])
	)
	if aggregate.get("ratio") != null:
		scope["previous_ratio"] = float(aggregate["ratio"])
	scope["aggregate_progress"] = aggregate
	_run_scopes[scope_id] = scope
	return aggregate


func _set_graph_status(state: Dictionary, status_key: String, detail: String = "") -> void:
	var graph: PFGraph = state.get("graph")
	if graph != null:
		_canvas._set_graph_node_status(
			graph.id, String(state.get("generate_node_id", "")), status_key, detail
		)


func _set_batch_run_state(
	state: Dictionary, _status: String, _detail: String, _completed_count: int = -1
) -> void:
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
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": Strings.OPENAI_BATCH_LABEL}, Vector2(560, 29)
	)
	graph.add_edge("objects", "subjects", "generate", "subjects")
	graph.add_edge("prompt_preset", "prefix", "generate", "prefix")
	graph.add_edge("generate", "assets", "batch_1", "in")
	return graph


func _request_for_graph(
	graph: PFGraph, generate_node_id: String, provider_id: String
) -> Dictionary:
	var generate_params := graph.get_node_params(generate_node_id)
	var model_id := String(generate_params.get("model_id", "")).strip_edges()
	var input := {
		"run_id": IdUtil.uuid_v4(),
		"provider_id": provider_id,
		"model_id": model_id,
		"graph_id": graph.id,
		"source_node_id": generate_node_id,
		"prompt": "",
		"prefix": "",
		"prompt_preset_id": "",
		"rows": [],
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
		"target_width": int(generate_params.get("target_width", 32)),
		"target_height": int(generate_params.get("target_height", 32)),
		"batch_size": int(generate_params.get("batch_size", 1)),
		"seed": int(generate_params.get("seed", -1)),
		"extra": Dictionary(generate_params.get("extra", {})).duplicate(true),
	}
	for node_id in _direct_source_node_ids(graph, generate_node_id):
		var node: PFNode = graph.get_node(node_id)
		if node == null:
			continue
		var params := graph.get_node_params(node_id)
		match node.get_type():
			"object_list":
				input["rows"] = Array(params.get("rows", [])).duplicate(true)
			"text_prompt":
				input["prompt"] = String(params.get("text", input["prompt"]))
			"prompt_preset":
				var preset: Dictionary = params.get("preset", {})
				input["prefix"] = String(preset.get("prefix", ""))
				input["prompt_preset_id"] = String(preset.get("id", ""))
	_add_reference_inputs(input, graph, generate_node_id)
	return input


func _requests_for_graph(
	graph: PFGraph, generate_node_id: String, provider_id: String
) -> Dictionary:
	var base := _request_for_graph(graph, generate_node_id, provider_id)
	if base.has("__issue"):
		return {"ok": false, "issue": base["__issue"], "requests": [], "slots": []}
	var provenance_inputs := {
		"source_node_id": String(base.get("source_node_id", "")),
		"prompt_preset_id": String(base.get("prompt_preset_id", "")),
		"prompt_prefix": String(base.get("prefix", "")),
		"reference_asset_ids": Array(base.get("reference_asset_ids", [])).duplicate(),
		"reference_content_sha256s": Array(base.get("reference_content_sha256s", [])).duplicate(),
	}
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	if provider == null:
		return {
			"ok": false,
			"issue": {"code": "invalid_provider_model", "field": "provider_id", "args": {}},
			"requests": [],
			"slots": [],
		}
	var planned: Dictionary = GenerationRequestPlannerScript.plan(
		base, provider.get_model_descriptors()
	)
	if not bool(planned.get("ok", false)):
		return {
			"ok": false,
			"issue": Dictionary(planned.get("issue", {})).duplicate(true),
			"requests": [],
			"slots": [],
		}
	planned["result_count"] = int(planned["total_slots"])
	planned["provenance_inputs"] = provenance_inputs
	return planned


func _add_reference_inputs(request: Dictionary, graph: PFGraph, generate_node_id: String) -> void:
	var asset_ids: Array[String] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[0]) != generate_node_id or String(to_data[1]) != "references":
			continue
		var source: PFNode = graph.get_node(String(from_data[0]))
		if source == null:
			continue
		var params := graph.get_node_params(String(from_data[0]))
		if source.get_type() == "image_input":
			asset_ids.append(String(params.get("asset_id", "")))
		elif source.get_type() == "reference_set":
			for raw_id in params.get("asset_ids", []):
				asset_ids.append(String(raw_id))
	if asset_ids.is_empty():
		return
	var resolved: Dictionary = GenerationRequestPlannerScript.resolve_reference_assets(
		asset_ids, AssetLibrary
	)
	if not bool(resolved.get("ok", false)):
		request["__issue"] = Dictionary(resolved.get("issue", {})).duplicate(true)
		return
	request["reference_asset_ids"] = resolved["reference_asset_ids"]
	request["reference_content_sha256s"] = resolved["reference_content_sha256s"]
	request["ref_images"] = resolved["ref_images"]


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
