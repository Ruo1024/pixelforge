class_name PFOfflineExampleController
extends Node

## Owns the bundled reference-to-batch example as one undoable workspace action.

const OfflineExampleGraph := preload("res://services/offline_example_graph.gd")
const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")
const Log := preload("res://core/util/log_util.gd")

var _canvas: Control = null
var _status_label: Label = null


func setup(canvas: Control, status_label: Label) -> void:
	_canvas = canvas
	_status_label = status_label


func open() -> void:
	var reference_id := AssetLibrary.register_image(
		OfflineExampleGraph.make_reference_image(), "offline_reference", {"origin": "imported"}
	)
	var graph := OfflineExampleGraph.build(reference_id, Strings.text("BATCH_DEFAULT_LABEL"))
	var result: Dictionary = GraphMockRunnerScript.new().run_to_batch(
		graph, AssetLibrary, "batch_1"
	)
	if not bool(result.get("ok", false)):
		Log.warn("Mock graph generation failed", result.get("error", {}))
		_status_label.text = Strings.text("STATUS_MOCK_GENERATE_FAILED")
		return
	var asset_ids: Array = BatchNodeScript.get_visible_asset_ids(
		graph.get_node_params("batch_1")
	)
	var anchor: Vector2 = _canvas.get_mouse_world_position()
	var item_ids := {
		"objects": IdUtil.uuid_v4(),
		"prompt_preset": IdUtil.uuid_v4(),
		"reference": IdUtil.uuid_v4(),
		"generate": IdUtil.uuid_v4(),
		"batch_1": IdUtil.uuid_v4(),
	}
	var before_graphs := ProjectService.get_graphs_data()
	var after_graphs := before_graphs.duplicate(true)
	after_graphs[graph.id] = graph.to_json()
	var items := []
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		items = _add_canvas_items(graph, asset_ids, anchor, item_ids)
	var undo_add := func() -> void:
		for item_id in item_ids.values():
			_canvas._remove_item_direct(String(item_id))
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Open offline example", do_add, undo_add)
	if not items.is_empty():
		_focus_canvas_on_bounds(_bounds_for_items(items))
	_status_label.text = Strings.text("STATUS_MOCK_GENERATE_DONE_FORMAT") % asset_ids.size()


func _add_canvas_items(
	graph: PFGraph, asset_ids: Array, anchor: Vector2, item_ids: Dictionary
) -> Array:
	var items := []
	for node_id in ["objects", "prompt_preset", "reference", "generate"]:
		var node_item: Node = _canvas._add_graph_node_card(
			graph.id,
			node_id,
			anchor + _graph_node_position(graph, node_id),
			String(item_ids[node_id]),
			false
		)
		if node_item != null:
			items.append(node_item)
	var batch_card: Node = _canvas._add_batch_card(
		asset_ids,
		anchor + _graph_node_position(graph, "batch_1"),
		Strings.text("BATCH_DEFAULT_LABEL"),
		String(item_ids["batch_1"]),
		false,
		graph.id,
		"batch_1"
	)
	if batch_card != null:
		items.append(batch_card)
	return items


func _graph_node_position(graph: PFGraph, node_id: String) -> Vector2:
	var node_data: Dictionary = graph.nodes.get(node_id, {})
	var raw_position: Variant = node_data.get("position", [0, 0])
	return Vector2(float(raw_position[0]), float(raw_position[1])).round()


func _bounds_for_items(items: Array) -> Rect2:
	var bounds: Rect2 = items[0].get_canvas_bounds()
	for index in range(1, items.size()):
		bounds = bounds.merge(items[index].get_canvas_bounds())
	return bounds


func _focus_canvas_on_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or _canvas.size.is_zero_approx():
		return
	var target_zoom := minf(
		_canvas.size.x * 0.62 / bounds.size.x, _canvas.size.y * 0.62 / bounds.size.y
	)
	_canvas.set_camera_zoom(target_zoom, _canvas.size * 0.5)
	_canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)
