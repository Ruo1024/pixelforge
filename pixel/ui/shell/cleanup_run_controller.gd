class_name PFCleanupRunController
extends Node

## Explicit Pixel Cleanup application flow. All Output mutations stay in the
## shared generation coordinator; this class only sequences local operations.

const Strings := preload("res://ui/shell/strings.gd")
const PlanBuilderScript := preload("res://services/cleanup_run_plan_builder.gd")
const OperationAdapterScript := preload("res://services/cleanup_operation_adapter.gd")
const OutputAutoPlacementScript := preload("res://services/output_auto_placement.gd")
const CardContractScript := preload("res://ui/canvas/canvas_card_contract.gd")
const IdUtil := preload("res://core/util/id_util.gd")

var _canvas: Control
var _status_label: Label
var _coordinator: PFGenerationRunCoordinator
var _adapter: PFCleanupOperationAdapter
var _asset_library: Variant
var _runs := {}


func setup(canvas: Control, status_label: Label, coordinator: PFGenerationRunCoordinator, queue: Variant = null, asset_library: Variant = null) -> void:
	_canvas = canvas
	_status_label = status_label
	_coordinator = coordinator
	_asset_library = asset_library if asset_library != null else AssetLibrary
	_adapter = OperationAdapterScript.new(queue if queue != null else TaskQueue, _asset_library)


func run_graph(graph: PFGraph, cleanup_node_id: String) -> bool:
	var plan: Dictionary = PlanBuilderScript.build(graph, cleanup_node_id, _asset_library)
	if not bool(plan.get("ok", false)):
		_status_label.text = String(plan.get("issue", {}).get("code", "cleanup_failed"))
		return false
	var output_node_id := "output_%s" % IdUtil.uuid_v4().left(8)
	var prepared: Dictionary = _coordinator.prepare_cleanup_run(graph, cleanup_node_id, output_node_id, plan)
	if not bool(prepared.get("ok", false)):
		return false
	var bounds := _canvas_item_bounds(graph, cleanup_node_id)
	var position := OutputAutoPlacementScript.find_position(
		bounds["source"], bounds["existing"], CardContractScript.default_size_for_type("batch")
	)
	var card: Node = _canvas._add_batch_card(
		[], position, Strings.text("BATCH_DEFAULT_LABEL"), "", false, graph.id, output_node_id
	)
	if card == null:
		_coordinator.rollback_pending_run(graph, prepared["rollback_token"])
		return false
	_runs[graph.id] = _run_state(graph, cleanup_node_id, output_node_id)
	_persist_and_refresh(_runs[graph.id])
	_status_label.text = Strings.text("STATUS_CLEANUP_QUEUED")
	_dispatch_next(graph.id)
	return true


func retry_graph(graph: PFGraph, selected_node_id: String) -> bool:
	var output_node_id := _cleanup_output_id(graph, selected_node_id)
	if output_node_id.is_empty():
		return false
	var prepared := _coordinator.prepare_cleanup_retry(graph, output_node_id, IdUtil.uuid_v4())
	if not bool(prepared.get("ok", false)):
		return false
	var cleanup_node_id := String(graph.get_node_params(output_node_id).get("source_node_id", ""))
	_runs[graph.id] = _run_state(graph, cleanup_node_id, output_node_id)
	_persist_and_refresh(_runs[graph.id])
	_dispatch_next(graph.id)
	return true


func cancel_graph(graph_id: String, node_id: String = "") -> bool:
	if not _runs.has(graph_id):
		return false
	var state: Dictionary = _runs[graph_id]
	if not node_id.is_empty() and node_id not in [state["cleanup_node_id"], state["output_node_id"]]:
		return false
	var request_id := String(state.get("active_request_id", ""))
	if request_id.is_empty():
		return false
	var wrapper: PFCancelTaskV2 = _adapter.cancel(request_id)
	wrapper.resolved.connect(_on_cancel_resolved.bind(graph_id, request_id), CONNECT_ONE_SHOT)
	wrapper.rejected.connect(_on_cancel_rejected.bind(graph_id, request_id), CONNECT_ONE_SHOT)
	return true


func _dispatch_next(graph_id: String) -> void:
	if not _runs.has(graph_id):
		return
	var state: Dictionary = _runs[graph_id]
	var graph: PFGraph = state["graph"]
	var operation := _coordinator.next_cleanup_operation(graph, String(state["output_node_id"]))
	if operation.is_empty():
		_status_label.text = Strings.text("STATUS_CLEANUP_DONE")
		_runs.erase(graph_id)
		return
	var request_id := String(operation["request_id"])
	if not bool(_coordinator.mark_cleanup_running(graph, String(state["output_node_id"]), request_id).get("ok", false)):
		return
	state["active_request_id"] = request_id
	_runs[graph_id] = state
	_persist_and_refresh(state)
	var task: PFTask = _adapter.submit(operation)
	task.finished.connect(_on_operation_finished.bind(graph_id, request_id), CONNECT_ONE_SHOT)


func _on_operation_finished(result: Variant, graph_id: String, request_id: String) -> void:
	if not _runs.has(graph_id):
		return
	var state: Dictionary = _runs[graph_id]
	var graph: PFGraph = state["graph"]
	if result is Dictionary and result.get("image") is Image and result.get("report") is Dictionary:
		_coordinator.apply_cleanup_success(graph, String(state["output_node_id"]), request_id, result["image"], result["report"], _asset_library)
	else:
		_coordinator.apply_cleanup_failure(graph, String(state["output_node_id"]), request_id, _cleanup_error(request_id))
	state["active_request_id"] = ""
	_runs[graph_id] = state
	_persist_and_refresh(state)
	_dispatch_next(graph_id)


func _on_cancel_resolved(_result: Dictionary, graph_id: String, request_id: String) -> void:
	if not _runs.has(graph_id):
		return
	var state: Dictionary = _runs[graph_id]
	_coordinator.cancel_cleanup_remaining(state["graph"], String(state["output_node_id"]), request_id)
	_persist_and_refresh(state)
	_runs.erase(graph_id)


func _on_cancel_rejected(error: Dictionary, graph_id: String, request_id: String) -> void:
	if not _runs.has(graph_id):
		return
	var state: Dictionary = _runs[graph_id]
	_coordinator.apply_cleanup_failure(state["graph"], String(state["output_node_id"]), request_id, error)
	_persist_and_refresh(state)
	_runs.erase(graph_id)


func _run_state(graph: PFGraph, cleanup_node_id: String, output_node_id: String) -> Dictionary:
	return {"graph": graph, "cleanup_node_id": cleanup_node_id, "output_node_id": output_node_id, "active_request_id": ""}


func _persist_and_refresh(state: Dictionary) -> void:
	var graph: PFGraph = state["graph"]
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	_canvas._refresh_graph_node_card(graph.id, String(state["cleanup_node_id"]))
	_canvas._refresh_graph_batch_card(graph.id, String(state["output_node_id"]))


func _cleanup_output_id(graph: PFGraph, selected_node_id: String) -> String:
	var selected := graph.get_node(selected_node_id)
	if selected != null and selected.get_type() == "batch":
		var source := graph.get_node(String(graph.get_node_params(selected_node_id).get("source_node_id", "")))
		if source != null and source.get_type() == "pixel_cleanup":
			return selected_node_id
	for node_id in graph.nodes:
		if graph.get_node(String(node_id)).get_type() == "batch" and String(graph.get_node_params(String(node_id)).get("source_node_id", "")) == selected_node_id:
			return String(node_id)
	return ""


func _canvas_item_bounds(graph: PFGraph, source_node_id: String) -> Dictionary:
	var existing := []
	var source := Rect2(Vector2.ZERO, CardContractScript.default_size_for_type("pixel_cleanup"))
	for item in _canvas._items_by_id.values():
		if item == null or not item.has_method("get_canvas_bounds"):
			continue
		var bounds: Rect2 = item.get_canvas_bounds()
		existing.append(bounds)
		if str(item.get("graph_id")) == graph.id and str(item.get("node_id")) == source_node_id:
			source = bounds
	return {"source": source, "existing": existing}


func _cleanup_error(request_id: String) -> Dictionary:
	return {"code": "cleanup_failed", "stage": "cleanup", "provider_id": "", "retryable": false, "retry_after_seconds": null, "status_code": null, "request_id": request_id, "attempts": 1, "expected_count": 1, "received_count": 0}
