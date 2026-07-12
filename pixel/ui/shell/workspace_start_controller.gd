class_name PFWorkspaceStartController
extends Node

## 工作区首步动作接线；只组合已有 graph、导入与 mock 能力。

var _canvas: Control = null
var _import_flow: Node = null
var _open_example: Callable
var _create_graph_node: Callable


func setup(
	canvas: Control,
	_status_label: Label,
	import_flow: Node,
	open_example: Callable,
	create_graph_node: Callable
) -> void:
	_canvas = canvas
	_import_flow = import_flow
	_open_example = open_example
	_create_graph_node = create_graph_node
	_import_flow.add_input_requested.connect(create_input_workspace)
	_import_flow.open_example_requested.connect(open_example_workspace)
	_import_flow.reference_asset_imported.connect(_on_reference_asset_imported)


func import_reference() -> void:
	_import_flow.show_reference_import_dialog({"mode": "workspace"})


func open_example_workspace() -> void:
	_open_example.call()


func create_input_workspace() -> String:
	var world_position: Vector2 = _canvas.screen_to_world(_canvas.size * 0.5).round()
	return String(_create_graph_node.call("object_list", world_position, {}))


func _on_reference_asset_imported(target: Dictionary, asset_id: String) -> void:
	if String(target.get("mode", "")) != "workspace":
		return
	var world_position: Vector2 = _canvas.screen_to_world(_canvas.size * 0.5).round()
	_create_graph_node.call("image_input", world_position, {"asset_id": asset_id})
