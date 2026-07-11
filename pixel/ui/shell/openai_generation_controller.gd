class_name PFOpenAIGenerationController
extends Node

## 云端 Provider 会话与异步生成闭环。
## 保留 M4-V1 OpenAI 会话入口，同时执行所有已验证的非 mock Provider graph。

const Strings := preload("res://ui/shell/strings.gd")
const OpenAISessionDialogScript := preload("res://ui/dialogs/openai_session_dialog.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const IdUtil := preload("res://core/util/id_util.gd")

var _canvas: Control = null
var _status_label: Label = null
var _cost_label: Label = null
var _session_dialog: ConfirmationDialog = null
var _budget_dialog: ConfirmationDialog = null
var _pending_runs := {}
var _pending_budget_run := {}


func setup(canvas: Control, status_label: Label, cost_label: Label = null) -> void:
	_canvas = canvas
	_status_label = status_label
	_cost_label = cost_label
	_session_dialog = OpenAISessionDialogScript.new()
	_session_dialog.name = "OpenAISessionDialog"
	_session_dialog.session_configured.connect(_on_session_configured)
	add_child(_session_dialog)
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
	_session_dialog.popup_for_session()


func generate_batch() -> void:
	_queue_graph(_make_graph(), "batch_1", "", "openai_image")


func run_graph(graph: PFGraph, batch_node_id: String, batch_card_id: String) -> void:
	_queue_graph(graph, batch_node_id, batch_card_id, _provider_id_for_graph(graph))


func cancel_graph(graph_id: String) -> bool:
	for task_id in _pending_runs.keys():
		var graph: PFGraph = _pending_runs[task_id].get("graph")
		if graph != null and graph.id == graph_id:
			TaskQueue.cancel(String(task_id))
			return true
	return false


func _queue_graph(
	graph: PFGraph, batch_node_id: String, batch_card_id: String, provider_id: String
) -> void:
	var provider: PFProvider = ProviderService.get_provider(provider_id)
	if provider == null:
		var unavailable := Strings.text("CONTENT_DETAIL_PROVIDER_UNAVAILABLE")
		_set_graph_status({"graph": graph}, "CONTENT_STATUS_FAILED", unavailable)
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
		_set_graph_status({"graph": graph}, "CONTENT_STATUS_FAILED", _status_label.text)
		return
	var request := _request_for_graph(graph)
	var estimate := CostService.estimate_request(provider_id, request)
	var run_state := {
		"graph": graph,
		"request": request,
		"provider_id": provider_id,
		"provider_name": display_name,
		"anchor": _canvas.get_mouse_world_position(),
		"batch_node_id": batch_node_id,
		"batch_card_id": batch_card_id,
		"estimate": estimate,
	}
	_refresh_cost_label(estimate)
	if CostService.requires_confirmation(estimate):
		_pending_budget_run = run_state
		_budget_dialog.dialog_text = (
			Strings.STATUS_PROVIDER_BUDGET_CONFIRM_FORMAT
			% [estimate, CostService.get_monthly_budget()]
		)
		_status_label.text = _budget_dialog.dialog_text
		_set_graph_status(run_state, "CONTENT_STATUS_WAITING", _budget_dialog.dialog_text)
		_budget_dialog.popup_centered()
		return
	_submit_provider_run(run_state)


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
		return
	_pending_runs[task.id] = run_state
	var estimate := float(run_state.get("estimate", -1.0))
	var detail := (
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % estimate if estimate >= 0.0 else ""
	)
	_set_graph_status(run_state, "CONTENT_STATUS_RUNNING", detail)
	task.progress_reported.connect(_on_progress)
	task.finished.connect(_on_finished.bind(task.id))
	task.failed.connect(_on_failed.bind(task.id))
	task.canceled.connect(_on_canceled.bind(task.id))
	TaskQueue.submit(task)
	_status_label.text = Strings.STATUS_PROVIDER_GENERATE_QUEUED_FORMAT % display_name


func get_session_dialog() -> ConfirmationDialog:
	return _session_dialog


func get_budget_dialog() -> ConfirmationDialog:
	return _budget_dialog


func _confirm_budget_run() -> void:
	if _pending_budget_run.is_empty():
		return
	var run_state := _pending_budget_run
	_pending_budget_run = {}
	_submit_provider_run(run_state)


func _on_session_configured(api_key: String) -> void:
	var error: Variant = ProviderService.configure_session("openai_image", {"api_key": api_key})
	_status_label.text = (
		Strings.STATUS_OPENAI_SESSION_READY
		if error == null
		else Strings.STATUS_OPENAI_SESSION_REQUIRED
	)


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
	var graph: PFGraph = state["graph"]
	var request: Dictionary = state["request"]
	var provider_id := String(state["provider_id"])
	var display_name := String(state["provider_name"])
	var batch_node_id := String(state["batch_node_id"])
	var batch_card_id := String(state["batch_card_id"])
	var images: Array = result.get("images", [])
	CostService.record_cost(provider_id, float(result.get("cost", -1.0)))
	var runner := GraphRunnerScript.new()
	var materialized := runner.materialize_provider_batch(
		graph,
		batch_node_id,
		images,
		_metadata(result, request, images.size(), provider_id),
		AssetLibrary,
		not batch_card_id.is_empty()
	)
	if not bool(materialized.get("ok", false)):
		var invalid_response := Strings.text("CONTENT_DETAIL_INVALID_RESPONSE")
		_set_graph_status(state, "CONTENT_STATUS_FAILED", invalid_response)
		_status_label.text = (
			Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT % [display_name, invalid_response]
		)
		return
	var asset_ids: Array = materialized["asset_ids"]
	_set_graph_status(
		state,
		"CONTENT_STATUS_COMPLETE",
		Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % asset_ids.size()
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if not batch_card_id.is_empty():
		_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
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
	var message := String(error.get("message", "")).strip_edges()
	if message.is_empty():
		message = Strings.text("CONTENT_DETAIL_UNKNOWN_ERROR")
	_set_graph_status(state, "CONTENT_STATUS_FAILED", message)
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_FAILED_FORMAT
		% [String(state.get("provider_name", "Provider")), message]
	)


func _on_canceled(task_id: String) -> void:
	var state: Dictionary = _pending_runs.get(task_id, {})
	_pending_runs.erase(task_id)
	_set_graph_status(state, "CONTENT_STATUS_CANCELED", Strings.text("CONTENT_DETAIL_CANCELED"))
	_status_label.text = (
		Strings.STATUS_PROVIDER_GENERATE_CANCELED_FORMAT
		% String(state.get("provider_name", "Provider"))
	)
	_refresh_cost_label()


func _set_graph_status(state: Dictionary, status_key: String, detail: String = "") -> void:
	var graph: PFGraph = state.get("graph")
	if graph != null:
		_canvas._set_graph_node_type_status(graph.id, "ai_generate", status_key, detail)


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
	for index in range(count):
		(
			metadata
			. append(
				{
					"provider": provider_id,
					"model": String(provider_meta.get("model", "")),
					"prompt": request.get("prompt", ""),
					"seed": seeds[index] if index < seeds.size() else null,
					"cost": total_cost / count if total_cost >= 0.0 and count > 0 else -1.0,
					"provider_meta": provider_meta,
					"name": "%s_%03d" % [provider_id, index + 1],
				}
			)
		)
	return metadata


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


func _request_for_graph(graph: PFGraph) -> Dictionary:
	var request := {
		"mode": "txt2img",
		"prompt": Strings.OPENAI_V1_FIXED_PROMPT,
		"style": _project_style_preset(),
		"width": 32,
		"height": 32,
		"batch": 2,
		"seed": -1,
		"extra": {},
	}
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node == null:
			continue
		var params := graph.get_node_params(String(node_id))
		match node.get_type():
			"object_list":
				request["prompt"] = String(params.get("items", request["prompt"]))
			"size_spec":
				request["width"] = int(params.get("width", request["width"]))
				request["height"] = int(params.get("height", request["height"]))
			"ai_generate":
				request["batch"] = int(params.get("batch_size", request["batch"]))
				request["seed"] = int(params.get("seed", request["seed"]))
			"comfyui.run_workflow":
				request["batch"] = 1
				request["seed"] = int(params.get("seed", request["seed"]))
				request["extra"]["template_id"] = String(
					params.get("template_id", "sdxl_pixel_txt2img")
				)
	return request


func _provider_id_for_graph(graph: PFGraph) -> String:
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node != null and node.get_type() == "ai_generate":
			return String(graph.get_node_params(String(node_id)).get("provider_id", "mock"))
		if node != null and node.get_type() == "comfyui.run_workflow":
			return "comfyui"
	return "mock"


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
