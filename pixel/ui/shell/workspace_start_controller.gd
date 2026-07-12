class_name PFWorkspaceStartController
extends Node

## 工作区首步动作接线；只组合已有 graph、导入与 mock 能力。

const GraphScript := preload("res://core/graph/pf_graph.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")

var _canvas: Control = null
var _status_label: Label = null
var _import_flow: Node = null
var _open_example: Callable


func setup(canvas: Control, status_label: Label, import_flow: Node, open_example: Callable) -> void:
	_canvas = canvas
	_status_label = status_label
	_import_flow = import_flow
	_open_example = open_example
	_import_flow.add_input_requested.connect(create_input_workspace)
	_import_flow.open_example_requested.connect(open_example_workspace)
	_import_flow.reference_asset_imported.connect(_on_reference_asset_imported)


func import_reference() -> void:
	_import_flow.show_reference_import_dialog({"mode": "workspace"})


func open_example_workspace() -> void:
	_open_example.call()


func create_input_workspace() -> String:
	var graph := GraphScript.new()
	graph.id = "graph_input_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "Input Workspace"
	var node_id := "objects"
	var world_position: Vector2 = _canvas.screen_to_world(_canvas.size * 0.5).round()
	graph.add_node(ObjectListNodeScript.new(), node_id, {}, world_position)

	var item_id := IdUtil.uuid_v4()
	var before_graphs: Dictionary = ProjectService.get_graphs_data()
	var after_graphs := before_graphs.duplicate(true)
	after_graphs[graph.id] = graph.to_json()
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		_canvas._add_graph_node_card(graph.id, node_id, world_position, item_id, false)
		_canvas.select_ids([item_id])
	var undo_add := func() -> void:
		_canvas._remove_item_direct(item_id)
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Add input module", do_add, undo_add)
	_status_label.text = Strings.text("STATUS_INPUT_WORKSPACE_CREATED")
	return item_id


func _on_reference_asset_imported(target: Dictionary, asset_id: String) -> void:
	if String(target.get("mode", "")) != "workspace":
		return
	var graph := GraphScript.new()
	graph.id = "graph_reference_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "Reference Workspace"
	var node_id := "reference"
	var world_position: Vector2 = _canvas.screen_to_world(_canvas.size * 0.5).round()
	graph.add_node(ImageInputNodeScript.new(), node_id, {"asset_id": asset_id}, world_position)
	var item_id := IdUtil.uuid_v4()
	var before_graphs: Dictionary = ProjectService.get_graphs_data()
	var after_graphs := before_graphs.duplicate(true)
	after_graphs[graph.id] = graph.to_json()
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		_canvas._add_graph_node_card(graph.id, node_id, world_position, item_id, false)
		_canvas.select_ids([item_id])
	var undo_add := func() -> void:
		_canvas._remove_item_direct(item_id)
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Add reference module", do_add, undo_add)
