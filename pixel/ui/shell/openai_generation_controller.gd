class_name PFOpenAIGenerationController
extends Node

## M4-V1 OpenAI 会话与异步生成闭环。
## 入口/反馈/出口：会话 key → 队列状态 → graph + batch + provenance。

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
var _session_dialog: ConfirmationDialog = null
var _pending_runs := {}


func setup(canvas: Control, status_label: Label) -> void:
	_canvas = canvas
	_status_label = status_label
	_session_dialog = OpenAISessionDialogScript.new()
	_session_dialog.name = "OpenAISessionDialog"
	_session_dialog.session_configured.connect(_on_session_configured)
	add_child(_session_dialog)


func configure_session() -> void:
	_session_dialog.popup_for_session()


func generate_batch() -> void:
	_queue_graph(_make_graph(), "batch_1", "")


func run_graph(graph: PFGraph, batch_node_id: String, batch_card_id: String) -> void:
	_queue_graph(graph, batch_node_id, batch_card_id)


func _queue_graph(graph: PFGraph, batch_node_id: String, batch_card_id: String) -> void:
	if not ProviderService.has_session_credentials("openai_image"):
		_status_label.text = Strings.STATUS_OPENAI_SESSION_REQUIRED
		configure_session()
		return
	var request := _request_for_graph(graph)
	var task: Variant = ProviderService.generate("openai_image", request)
	if task == null:
		_status_label.text = Strings.STATUS_OPENAI_GENERATE_FAILED_FORMAT % "provider unavailable"
		return
	_pending_runs[task.id] = {
		"graph": graph,
		"request": request,
		"anchor": _canvas.get_mouse_world_position(),
		"batch_node_id": batch_node_id,
		"batch_card_id": batch_card_id,
	}
	task.progress_reported.connect(_on_progress)
	task.finished.connect(_on_finished.bind(task.id))
	task.failed.connect(_on_failed.bind(task.id))
	task.canceled.connect(_on_canceled.bind(task.id))
	TaskQueue.submit(task)
	_status_label.text = Strings.STATUS_OPENAI_GENERATE_QUEUED


func get_session_dialog() -> ConfirmationDialog:
	return _session_dialog


func _on_session_configured(api_key: String) -> void:
	var error: Variant = ProviderService.configure_session("openai_image", {"api_key": api_key})
	_status_label.text = (
		Strings.STATUS_OPENAI_SESSION_READY
		if error == null
		else Strings.STATUS_OPENAI_SESSION_REQUIRED
	)


func _on_progress(_task_id: String, ratio: float, message: String) -> void:
	_status_label.text = (
		Strings.STATUS_OPENAI_GENERATE_RUNNING_FORMAT % [roundi(ratio * 100.0), message]
	)


func _on_finished(result: Variant, task_id: String) -> void:
	if not _pending_runs.has(task_id) or not (result is Dictionary):
		return
	var state: Dictionary = _pending_runs[task_id]
	_pending_runs.erase(task_id)
	var graph: PFGraph = state["graph"]
	var request: Dictionary = state["request"]
	var batch_node_id := String(state["batch_node_id"])
	var batch_card_id := String(state["batch_card_id"])
	var images: Array = result.get("images", [])
	var runner := GraphRunnerScript.new()
	var materialized := runner.materialize_provider_batch(
		graph,
		batch_node_id,
		images,
		_metadata(result, request, images.size()),
		AssetLibrary,
		not batch_card_id.is_empty()
	)
	if not bool(materialized.get("ok", false)):
		_status_label.text = Strings.STATUS_OPENAI_GENERATE_FAILED_FORMAT % "invalid image response"
		return
	var asset_ids: Array = materialized["asset_ids"]
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if not batch_card_id.is_empty():
		_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
		_status_label.text = Strings.STATUS_GRAPH_RUN_DONE % asset_ids.size()
		return
	var items := _add_canvas_items(graph, asset_ids, state["anchor"])
	if not items.is_empty():
		_focus_bounds(_bounds_for_items(items))
	_status_label.text = Strings.STATUS_OPENAI_GENERATE_DONE % asset_ids.size()


func _on_failed(error: Dictionary, task_id: String) -> void:
	_pending_runs.erase(task_id)
	var message := String(error.get("message", "unknown error"))
	_status_label.text = Strings.STATUS_OPENAI_GENERATE_FAILED_FORMAT % message


func _on_canceled(task_id: String) -> void:
	_pending_runs.erase(task_id)
	_status_label.text = Strings.STATUS_OPENAI_GENERATE_CANCELED


func _metadata(result: Dictionary, request: Dictionary, count: int) -> Array:
	var metadata := []
	var seeds: Array = result.get("seeds", [])
	for index in range(count):
		(
			metadata
			. append(
				{
					"provider": "openai_image",
					"model": "gpt-image-2",
					"prompt": request.get("prompt", ""),
					"seed": seeds[index] if index < seeds.size() else null,
					"cost": result.get("cost", -1.0),
					"provider_meta": result.get("provider_meta", {}),
					"name": "openai_%03d" % (index + 1),
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
	return request


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
