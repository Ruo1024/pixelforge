class_name PFOpenAIGenerationController
extends Node

## 云端 Provider 异步生成闭环；配置统一进入 ProviderSettingsDialog。

const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")

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
	CostService.cost_changed.connect(
		func(_month: String, _total: float) -> void: _refresh_cost_label()
	)
	CostService.budget_changed.connect(func(_limit: float) -> void: _refresh_cost_label())
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
	for task_id in _pending_runs.keys():
		var state: Dictionary = _pending_runs[task_id]
		var graph: PFGraph = state.get("graph")
		if (
			graph != null
			and graph.id == graph_id
			and (
				generate_node_id.is_empty()
				or String(state.get("generate_node_id", "")) == generate_node_id
			)
		):
			TaskQueue.cancel(String(task_id))
			canceled = true
	return canceled


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
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	if provider == null:
		var unavailable := Strings.text("CONTENT_DETAIL_PROVIDER_UNAVAILABLE")
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", unavailable)
		_set_batch_run_state(target_state, "failed", unavailable)
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % unavailable
		return
	var display_name := provider.get_display_name()
	if not ProviderService.has_session_credentials(provider_id):
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
	var previous_run_state: Dictionary = graph.get_node_params(batch_node_id).get("run_state", {})
	var retry_row_ids: Array = previous_run_state.get("failed_row_ids", [])
	var request_result := _requests_for_graph(graph, generate_node_id, provider_id, retry_row_ids)
	if not bool(request_result.get("ok", false)):
		var reference_error := String(request_result.get("error", ""))
		_set_graph_status(target_state, "CONTENT_STATUS_FAILED", reference_error)
		_set_batch_run_state(target_state, "failed", reference_error)
		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % reference_error
		return
	var requests: Array = request_result["requests"]
	var estimate := 0.0
	var estimate_known := true
	for request in requests:
		var validation_message := _cloud_request_validation_message(
			provider_id, provider, request, display_name
		)
		if not validation_message.is_empty():
			_set_graph_status(target_state, "CONTENT_STATUS_FAILED", validation_message)
			_set_batch_run_state(target_state, "failed", validation_message)
			_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % validation_message
			return
		var request_estimate := CostService.estimate_request(provider_id, request)
		if request_estimate < 0.0:
			estimate_known = false
		else:
			estimate += request_estimate
	var scope_id := IdUtil.uuid_v4()
	var expected_count := int(request_result["result_count"])
	var run_states: Array[Dictionary] = []
	for request in requests:
		var run_id := IdUtil.uuid_v4()
		request["run_id"] = run_id
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
					"estimate": CostService.estimate_request(provider_id, request),
				}
			)
		)
	_run_scopes[scope_id] = {
		"pending": run_states.size(),
		"failed": 0,
		"asset_ids": [],
		"failed_row_ids": [],
	}
	_set_batch_run_state(run_states[0], "waiting", "")
	_refresh_cost_label(estimate if estimate_known else -1.0)
	if estimate_known and CostService.requires_confirmation(estimate):
		_pending_budget_run = {"runs": run_states, "estimate": estimate}
		_budget_dialog.dialog_text = (
			Strings.STATUS_PROVIDER_BUDGET_CONFIRM_FORMAT
			% [estimate, CostService.get_monthly_budget()]
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
	provider_id: String, provider: PFProvider, request: Dictionary, display_name: String
) -> String:
	if (
		not _request_reference_images(request).is_empty()
		and not bool(provider.get_capabilities().get("img2img", false))
	):
		return Strings.text("CONTENT_DETAIL_REFERENCE_UNSUPPORTED_FORMAT") % display_name
	var error: Variant = ProviderService.validate_generation_request(provider_id, request)
	return String(error.get("message", "")) if error is Dictionary else ""


func _submit_provider_run(run_state: Dictionary) -> void:
	var provider_id := String(run_state["provider_id"])
	var display_name := String(run_state["provider_name"])
	var request: Dictionary = run_state["request"]
	var task: Variant = ProviderService.generate(provider_id, request)
	if task == null:
		var unavailable := Strings.text("CONTENT_DETAIL_PROVIDER_UNAVAILABLE")
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, unavailable]
		)
		_set_graph_status(run_state, "CONTENT_STATUS_FAILED", unavailable)
		_set_batch_run_state(run_state, "failed", unavailable)
		return
	_pending_runs[task.id] = run_state
	var estimate := float(run_state.get("estimate", -1.0))
	var detail := (
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % estimate if estimate >= 0.0 else ""
	)
	_set_graph_status(run_state, "CONTENT_STATUS_RUNNING", detail)
	_set_batch_run_state(run_state, "running", detail)
	task.progress_reported.connect(_on_progress)
	task.finished.connect(_on_finished.bind(task.id))
	task.failed.connect(_on_failed.bind(task.id))
	task.canceled.connect(_on_canceled.bind(task.id))
	TaskQueue.submit(task)
	_status_label.text = Strings.STATUS_PROVIDER_GENERATE_QUEUED_FORMAT % display_name


func get_budget_dialog() -> ConfirmationDialog:
	return _budget_dialog


func _confirm_budget_run() -> void:
	if _pending_budget_run.is_empty():
		return
	var pending := _pending_budget_run
	_pending_budget_run = {}
	_submit_provider_runs(pending.get("runs", []))


func _on_progress(_task_id: String, ratio: float, message: String) -> void:
	var state: Dictionary = _pending_runs.get(_task_id, {})
	var display_name := String(state.get("provider_name", "Provider"))
	var percent := roundi(ratio * 100.0)
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
	var images: Array = result.get("images", [])
	CostService.record_cost(provider_id, float(result.get("cost", -1.0)))
	var runner := GraphRunnerScript.new()
	var scope: Dictionary = _run_scopes.get(String(state.get("scope_id", "")), {})
	var replace_existing := Array(scope.get("asset_ids", [])).is_empty()
	var materialized := runner.materialize_provider_batch(
		graph,
		batch_node_id,
		images,
		_metadata(result, request, images.size(), provider_id),
		AssetLibrary,
		replace_existing
	)
	if not bool(materialized.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_set_batch_run_state(state, "failed", invalid_response)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, invalid_response]
		)
		return
	var asset_ids: Array = materialized["asset_ids"]
	var scope_result := _finish_scope_task(state, false)
	var scope_asset_ids: Array = scope_result.get("asset_ids", [])
	for asset_id in asset_ids:
		scope_asset_ids.append(asset_id)
	if _run_scopes.has(String(state.get("scope_id", ""))):
		_run_scopes[String(state.get("scope_id", ""))]["asset_ids"] = scope_asset_ids
	var scope_done := bool(scope_result.get("done", true))
	if scope_done:
		if int(scope_result.get("failed", 0)) > 0:
			state["failed_row_ids"] = scope_result.get("failed_row_ids", [])
			var partial_detail := (
				Strings.text("CONTENT_DETAIL_PARTIAL_FAILURE_FORMAT")
				% [scope_asset_ids.size(), int(scope_result["failed"])]
			)
			_set_graph_status(state, "CONTENT_STATUS_FAILED", partial_detail)
			_set_batch_run_state(state, "failed", partial_detail)
		else:
			_set_graph_status(
				state,
				"CONTENT_STATUS_COMPLETE",
				Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % scope_asset_ids.size()
			)
			_set_batch_run_state(state, "complete", "", scope_asset_ids.size())
	else:
		_set_batch_run_state(state, "running", "")
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if not batch_card_id.is_empty():
		_canvas._replace_batch_asset_ids(batch_card_id, scope_asset_ids, false)
		_status_label.text = Strings.STATUS_GRAPH_RUN_DONE % scope_asset_ids.size()
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
	var message := String(error.get("message", "")).strip_edges()
	if message.is_empty():
		message = Strings.text("CONTENT_DETAIL_UNKNOWN_ERROR")
	var scope_result := _finish_scope_task(state, true)
	if bool(scope_result.get("done", true)):
		_set_graph_status(state, "CONTENT_STATUS_FAILED", message)
		_set_batch_run_state(state, "failed", message)
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT
		% [String(state.get("provider_name", "Provider")), message]
	)


func _on_canceled(task_id: String) -> void:
	var state: Dictionary = _pending_runs.get(task_id, {})
	_pending_runs.erase(task_id)
	var scope_result := _finish_scope_task(state, true)
	if bool(scope_result.get("done", true)):
		_set_graph_status(state, "CONTENT_STATUS_CANCELED", Strings.text("CONTENT_DETAIL_CANCELED"))
		_set_batch_run_state(state, "canceled", Strings.text("CONTENT_DETAIL_CANCELED"))
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_CANCELED_FORMAT
		% String(state.get("provider_name", "Provider"))
	)
	_refresh_cost_label()


func _finish_scope_task(state: Dictionary, failed: bool) -> Dictionary:
	var scope_id := String(state.get("scope_id", ""))
	if scope_id.is_empty() or not _run_scopes.has(scope_id):
		return {"done": true, "asset_ids": []}
	var scope: Dictionary = _run_scopes[scope_id]
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
		"asset_ids": Array(scope.get("asset_ids", [])).duplicate(),
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


func _set_batch_run_state(
	state: Dictionary, status: String, detail: String, completed_count: int = -1
) -> void:
	var graph: PFGraph = state.get("graph")
	var batch_node_id := String(state.get("batch_node_id", ""))
	if graph == null or batch_node_id.is_empty():
		return
	var params := graph.get_node_params(batch_node_id)
	var request: Dictionary = state.get("request", {})
	var previous_state: Dictionary = params.get("run_state", {})
	var expected_count := int(state.get("scope_expected_count", -1))
	if expected_count < 0:
		expected_count = (
			completed_count
			if completed_count >= 0
			else maxi(1, int(request.get("batch", previous_state.get("expected_count", 1))))
		)
	params["run_state"] = {
		"status": status,
		"expected_count": expected_count,
		"detail": detail,
		"run_id": String(state.get("run_id", "")),
	}
	var failed_row_ids: Array = state.get("failed_row_ids", [])
	if not failed_row_ids.is_empty():
		params["run_state"]["failed_row_ids"] = failed_row_ids.duplicate()
	graph.set_node_params(batch_node_id, params)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	_canvas._refresh_graph_batch_card(graph.id, batch_node_id)


func _refresh_cost_label(estimate: float = -1.0) -> void:
	if _cost_label == null:
		return
	var total := CostService.get_month_total()
	_cost_label.text = (
		Strings.text("COST_MONTH_ESTIMATE_FORMAT") % [total, estimate]
		if estimate >= 0.0
		else Strings.text("COST_MONTH_FORMAT") % total
	)


func _metadata(result: Dictionary, request: Dictionary, count: int, provider_id: String) -> Array:
	var metadata := []
	var seeds: Array = result.get("seeds", [])
	var provider_meta: Dictionary = result.get("provider_meta", {})
	var total_cost := float(result.get("cost", -1.0))
	var model_id := ProviderService.resolve_model_id(
		provider_id, String(request.get("model_id", ""))
	)
	for index in range(count):
		(
			metadata
			. append(
				{
					"provider": provider_id,
					"model": model_id,
					"prompt": request.get("prompt", ""),
					"seed": seeds[index] if index < seeds.size() else null,
					"cost": total_cost / count if total_cost >= 0.0 and count > 0 else -1.0,
					"provider_meta": provider_meta,
					"reference_asset_id": request.get("reference_asset_id", null),
					"reference_content_sha256": request.get("reference_content_sha256", null),
					"reference_asset_ids": request.get("reference_asset_ids", []),
					"reference_content_sha256s": request.get("reference_content_sha256s", []),
					"source_node_id": String(request.get("source_node_id", "")),
					"source_row_id": String(request.get("source_row_id", "")),
					"generation_snapshot":
					_generation_snapshot(
						request,
						provider_id,
						model_id,
						seeds[index] if index < seeds.size() else null,
						total_cost / count if total_cost >= 0.0 and count > 0 else -1.0
					),
					"name": "%s_%03d" % [provider_id, index + 1],
				}
			)
		)
	return metadata


func _generation_snapshot(
	request: Dictionary, provider_id: String, model_id: String, seed: Variant, cost: float
) -> Dictionary:
	return {
		"provider_id": provider_id,
		"model_id": model_id,
		"prompt": String(request.get("prompt", "")),
		"negative_prompt": String(request.get("negative_prompt", "")),
		"style": Dictionary(request.get("style", {})).duplicate(true),
		"width": int(request.get("width", 0)),
		"height": int(request.get("height", 0)),
		"batch_size": int(request.get("batch", 1)),
		"seed": seed,
		"reference_asset_ids": Array(request.get("reference_asset_ids", [])).duplicate(),
		"reference_content_sha256s":
		Array(request.get("reference_content_sha256s", [])).duplicate(),
		"source_generate_node_id": String(request.get("source_generate_node_id", "")),
		"source_row_id": String(request.get("source_row_id", "")),
		"run_id": String(request.get("run_id", "")),
		"cost": cost,
	}


func _make_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_openai_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "OpenAI Generate Batch"
	graph.add_node(
		ObjectListNodeScript.new(),
		"objects",
		{"items": Strings.OPENAI_V1_FIXED_PROMPT},
		Vector2(0, 0)
	)
	graph.add_node(
		SizeSpecNodeScript.new(),
		"size",
		{"width": 32, "height": 32, "per_subject": 2},
		Vector2(0, 150)
	)
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "openai_image", "batch_size": 2, "seed": 1},
		Vector2(280, 75)
	)
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": Strings.OPENAI_BATCH_LABEL}, Vector2(560, 29)
	)
	graph.add_edge("objects", "items", "generate", "items")
	graph.add_edge("size", "spec", "generate", "spec")
	graph.add_edge("generate", "images", "batch_1", "in")
	return graph


func _request_for_graph(graph: PFGraph, generate_node_id: String) -> Dictionary:
	var request := {
		"mode": "txt2img",
		"model_id": "",
		"prompt": Strings.OPENAI_V1_FIXED_PROMPT,
		"style": _project_style_preset(),
		"width": 32,
		"height": 32,
		"batch": 2,
		"seed": -1,
		"extra": {},
	}
	for node_id in _direct_source_node_ids(graph, generate_node_id):
		var node: PFNode = graph.get_node(node_id)
		if node == null:
			continue
		var params := graph.get_node_params(node_id)
		match node.get_type():
			"object_list":
				var rows_value: Variant = params.get("rows", null)
				if rows_value is Array:
					request["__source_rows"] = rows_value.duplicate(true)
					request["source_node_id"] = node_id
				else:
					request["prompt"] = String(params.get("items", request["prompt"]))
			"text_prompt":
				request["prompt"] = String(params.get("text", request["prompt"]))
			"size_spec":
				request["width"] = int(params.get("width", request["width"]))
				request["height"] = int(params.get("height", request["height"]))
	var generate_params := graph.get_node_params(generate_node_id)
	request["batch"] = int(generate_params.get("batch_size", request["batch"]))
	request["seed"] = int(generate_params.get("seed", request["seed"]))
	request["model_id"] = String(generate_params.get("model_id", ""))
	request["source_generate_node_id"] = generate_node_id
	_add_reference_inputs(request, graph, generate_node_id)
	return request


func _requests_for_graph(
	graph: PFGraph, generate_node_id: String, provider_id: String, retry_row_ids: Array = []
) -> Dictionary:
	var base := _request_for_graph(graph, generate_node_id)
	if base.has("__error"):
		return {"ok": false, "error": String(base["__error"]), "requests": []}
	var rows_value: Variant = base.get("__source_rows", null)
	if not (rows_value is Array):
		return {
			"ok": true,
			"requests": [base],
			"result_count": maxi(1, int(base.get("batch", 1))),
		}
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(base.get("model_id", ""))
	)
	var max_batch := maxi(1, int(descriptor.get("capabilities", {}).get("max_batch", 1)))
	var requests: Array[Dictionary] = []
	var result_count := 0
	for raw_row in rows_value:
		if not (raw_row is Dictionary) or not bool(raw_row.get("enabled", true)):
			continue
		if not retry_row_ids.is_empty() and not retry_row_ids.has(String(raw_row.get("id", ""))):
			continue
		var remaining := maxi(1, int(raw_row.get("count", 1)))
		result_count += remaining
		while remaining > 0:
			var request: Dictionary = base.duplicate(true)
			request.erase("__source_rows")
			request["prompt"] = String(raw_row.get("text", ""))
			request["batch"] = mini(remaining, max_batch)
			request["source_row_id"] = String(raw_row.get("id", ""))
			requests.append(request)
			remaining -= int(request["batch"])
	if requests.is_empty():
		return {"ok": false, "error": Strings.text("STATUS_OBJECT_ROWS_EMPTY"), "requests": []}
	return {"ok": true, "requests": requests, "result_count": result_count}


func _add_reference_inputs(request: Dictionary, graph: PFGraph, generate_node_id: String) -> void:
	var asset_ids: Array[String] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[0]) != generate_node_id or String(to_data[1]) != "image":
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
	var images := []
	var hashes: Array[String] = []
	for asset_id in asset_ids:
		if asset_id.is_empty():
			request["__error"] = Strings.text("CONTENT_REFERENCE_NONE")
			return
		if not AssetLibrary.has_asset(asset_id):
			request["__error"] = (
				Strings.text("CONTENT_REFERENCE_MISSING_FORMAT") % asset_id.left(8)
			)
			return
		var image: Image = AssetLibrary.get_image(asset_id)
		if image == null:
			request["__error"] = (
				Strings.text("CONTENT_REFERENCE_DECODE_FAILED_FORMAT") % asset_id.left(8)
			)
			return
		images.append(image)
		hashes.append(GraphContextScript.image_content_sha256(image))
	if not images.is_empty():
		request["mode"] = "img2img"
		request["ref_images"] = images
		request["reference_asset_ids"] = asset_ids
		request["reference_content_sha256s"] = hashes
		request["ref_image"] = images[0]
		request["reference_asset_id"] = asset_ids[0]
		request["reference_content_sha256"] = hashes[0]


func _provider_id_for_graph(graph: PFGraph, generate_node_id: String) -> String:
	var node: PFNode = graph.get_node(generate_node_id)
	if node == null:
		return "mock"
	if node.get_type() == "comfyui.run_workflow":
		return "comfyui"
	return String(graph.get_node_params(generate_node_id).get("provider_id", "mock"))


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
	if value is Array:
		return value
	return [request["ref_image"]] if request.get("ref_image") is Image else []


func _add_canvas_items(graph: PFGraph, asset_ids: Array, anchor: Vector2) -> Array:
	var items := []
	for node_id in ["objects", "size", "generate"]:
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


func _project_style_preset() -> Dictionary:
	var style_data: Variant = ProjectService.current_project.manifest.get("style_preset", {})
	return style_data if style_data is Dictionary else {}
