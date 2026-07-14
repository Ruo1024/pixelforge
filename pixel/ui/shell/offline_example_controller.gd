class_name PFOfflineExampleController
extends Node

## Inserts the bundled starter graph as one undoable action, without running it.

const OfflineExampleGraph := preload("res://services/offline_example_graph.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")

var _canvas: Control = null
var _status_label: Label = null


func setup(canvas: Control, status_label: Label) -> void:
	_canvas = canvas
	_status_label = status_label


func open() -> void:
	var graph: PFGraph = OfflineExampleGraph.build(
		Strings.text("EXAMPLE_TEXT_PROMPT"), Strings.text("EXAMPLE_GRAPH_NAME")
	)
	var anchor: Vector2 = _canvas.get_mouse_world_position()
	var item_ids: Dictionary = {
		"prompt_preset": IdUtil.uuid_v4(),
		"text_prompt": IdUtil.uuid_v4(),
		"reference_set": IdUtil.uuid_v4(),
		"generate": IdUtil.uuid_v4(),
		"cleanup": IdUtil.uuid_v4(),
	}
	var before_graphs: Dictionary = ProjectService.get_graphs_data()
	var after_graphs: Dictionary = before_graphs.duplicate(true)
	after_graphs[graph.id] = graph.to_json()
	var items: Array = []
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		items = _add_canvas_items(graph, anchor, item_ids)
	var undo_add := func() -> void:
		for item_id in item_ids.values():
			_canvas._remove_item_direct(String(item_id))
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action(Strings.text("UNDO_OPEN_EXAMPLE"), do_add, undo_add)
	if not items.is_empty():
		_canvas._focus_item_ids(_canvas._items_by_id.keys())
	_status_label.text = Strings.text("STATUS_EXAMPLE_OPENED")


func _add_canvas_items(graph: PFGraph, anchor: Vector2, item_ids: Dictionary) -> Array:
	var items_by_node: Dictionary = {}
	var effective_sizes: Dictionary = {}
	for node_id in OfflineExampleGraph.INPUT_NODE_IDS + ["generate", "cleanup"]:
		var node_item: Node = _canvas._add_graph_node_card(
			graph.id, node_id, anchor, String(item_ids[node_id]), false
		)
		if node_item != null:
			items_by_node[node_id] = node_item
			effective_sizes[node_id] = node_item.get_canvas_bounds().size
	var positions: Dictionary = OfflineExampleGraph.layout_positions(effective_sizes)
	for node_id in items_by_node:
		items_by_node[node_id].position = (anchor + Vector2(positions[node_id])).round()
	_canvas._emit_canvas_changed()
	return items_by_node.values()
