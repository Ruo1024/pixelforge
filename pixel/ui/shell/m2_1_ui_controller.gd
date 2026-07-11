class_name PFM21UiController
extends Node

## M2.1 UI 接线控制器。
## 主窗口保留布局和项目命令；本控制器承接导入、工具、M2 参数对话框与批次菜单。

signal export_snapshots_requested(snapshots: Array, default_file: String)

const Strings := preload("res://ui/shell/strings.gd")
const ToolManagerScript := preload("res://ui/tools/tool_manager.gd")
const MagicWandToolScript := preload("res://ui/tools/magic_wand_tool.gd")
const RectangleToolScript := preload("res://ui/tools/rectangle_tool.gd")
const LassoToolScript := preload("res://ui/tools/lasso_tool.gd")
const MatteDialogScript := preload("res://ui/dialogs/matte_dialog.gd")
const SliceDialogScript := preload("res://ui/dialogs/slice_dialog.gd")
const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
const GraphNodeParamsDialogScript := preload("res://ui/dialogs/graph_node_params_dialog.gd")
const ImportFlowControllerScript := preload("res://ui/shell/import_flow_controller.gd")
const OpenAIGenerationControllerScript := preload("res://ui/shell/openai_generation_controller.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Log := preload("res://core/util/log_util.gd")

const TOOLBAR_BUTTON_HEIGHT := 34
const TOOLBAR_FONT_SIZE := 14
const FILE_MENU_BUTTON_WIDTH := 84
const TOOL_BUTTON_SIZE := 84
const FILE_MENU_IMPORT_IMAGES := 0
const FILE_MENU_GENERATE_MOCK_BATCH := 1
const FILE_MENU_RUN_SELECTED_GRAPH := 2
const FILE_MENU_EDIT_SELECTED_GRAPH_NODE := 3
const FILE_MENU_NEW := 4
const FILE_MENU_OPEN := 5
const FILE_MENU_SAVE := 6
const FILE_MENU_FOCUS_LAST_IMPORT := 7
const FILE_MENU_RETRY_IMPORT := 8
const FILE_MENU_CONFIGURE_OPENAI_SESSION := 9
const FILE_MENU_GENERATE_OPENAI_BATCH := 10
const GRAPH_ADD_MENU_ID_START := 100
const BATCH_MENU_CLEANUP := 0
const BATCH_MENU_MATTE := 1
const BATCH_MENU_OUTLINE := 2
const BATCH_MENU_SPLIT := 3
const BATCH_MENU_EXPORT := 4
const BATCH_MENU_MARK_KEEP := 5
const BATCH_MENU_MARK_REJECT := 6
const BATCH_MENU_MARK_FLAG := 7
const BATCH_MENU_CLEAR_MARK := 8
const BATCH_MENU_SPLIT_KEEP := 9
const BATCH_MENU_FILTER_ALL := 10
const BATCH_MENU_FILTER_KEEP := 11
const BATCH_MENU_FILTER_PENDING := 12
const BATCH_MENU_FILTER_REJECT := 13
const BATCH_MENU_FILTER_FLAG := 14
const BATCH_MENU_COMPARE_CURRENT := 15
const BATCH_MENU_COMPARE_PREVIOUS := 16
const BATCH_MENU_COMPARE_SPLIT := 17
const BATCH_MENU_LAYOUT_CONTACT := 18
const BATCH_MENU_LAYOUT_FOCUS := 19
const SELECTION_TOOLS_VISIBLE := false
const EDITABLE_GRAPH_NODE_TYPES := ["object_list", "size_spec", "ai_generate"]

var _canvas: Control = null
var _cleanup_inspector: Control = null
var _status_label: Label = null
var _m2_actions: Variant = null
var _new_project_callback: Callable
var _open_project_callback: Callable
var _save_project_callback: Callable
var _tool_manager: Variant = null
var _tool_buttons := {}
var _matte_dialog: ConfirmationDialog = null
var _slice_dialog: ConfirmationDialog = null
var _outline_dialog: ConfirmationDialog = null
var _graph_node_params_dialog: ConfirmationDialog = null
var _graph_add_menu: PopupMenu = null
var _graph_quick_add_menu: PopupMenu = null
var _graph_add_types := {}
var _graph_quick_add_world_position := Vector2.ZERO
var _batch_menu: PopupMenu = null
var _batch_menu_card_id := ""
var _import_flow: Node = null
var _openai_flow: Node = null


func setup(
	canvas: Control,
	cleanup_inspector: Control,
	status_label: Label,
	m2_actions: Variant,
	new_project_callback: Callable,
	open_project_callback: Callable,
	save_project_callback: Callable
) -> void:
	_canvas = canvas
	_cleanup_inspector = cleanup_inspector
	_status_label = status_label
	_m2_actions = m2_actions
	_new_project_callback = new_project_callback
	_open_project_callback = open_project_callback
	_save_project_callback = save_project_callback
	_import_flow = ImportFlowControllerScript.new()
	_import_flow.name = "ImportFlowController"
	add_child(_import_flow)
	_import_flow.setup(_canvas, _status_label, self)
	_openai_flow = OpenAIGenerationControllerScript.new()
	_openai_flow.name = "OpenAIGenerationController"
	add_child(_openai_flow)
	_openai_flow.setup(_canvas, _status_label)
	_create_m2_dialogs()
	_create_graph_node_params_dialog()
	_create_batch_menu()
	_init_tools()
	_canvas.batch_context_requested.connect(_show_batch_menu)
	_canvas.graph_quick_add_requested.connect(show_graph_quick_add_menu)


func add_file_menu(parent: Control) -> void:
	var file_menu_button := MenuButton.new()
	file_menu_button.text = Strings.MENU_FILE
	file_menu_button.custom_minimum_size = Vector2(FILE_MENU_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	file_menu_button.focus_mode = Control.FOCUS_NONE
	file_menu_button.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
	var popup := file_menu_button.get_popup()
	popup.add_item(Strings.MENU_IMPORT_IMAGES, FILE_MENU_IMPORT_IMAGES)
	popup.add_item(Strings.ACTION_FOCUS_LAST_IMPORT, FILE_MENU_FOCUS_LAST_IMPORT)
	popup.add_item(Strings.ACTION_RETRY_IMPORT, FILE_MENU_RETRY_IMPORT)
	popup.add_separator()
	popup.add_item(Strings.MENU_GENERATE_MOCK_BATCH, FILE_MENU_GENERATE_MOCK_BATCH)
	popup.add_item(Strings.MENU_CONFIGURE_OPENAI_SESSION, FILE_MENU_CONFIGURE_OPENAI_SESSION)
	popup.add_item(Strings.MENU_GENERATE_OPENAI_BATCH, FILE_MENU_GENERATE_OPENAI_BATCH)
	popup.add_item(Strings.MENU_RUN_SELECTED_GRAPH, FILE_MENU_RUN_SELECTED_GRAPH)
	_add_graph_node_submenu(popup)
	popup.add_item(Strings.MENU_EDIT_SELECTED_GRAPH_NODE, FILE_MENU_EDIT_SELECTED_GRAPH_NODE)
	popup.add_separator()
	popup.add_item(Strings.ACTION_NEW, FILE_MENU_NEW)
	popup.add_item(Strings.ACTION_OPEN, FILE_MENU_OPEN)
	popup.add_item(Strings.ACTION_SAVE, FILE_MENU_SAVE)
	popup.id_pressed.connect(_on_file_menu_pressed)
	_import_flow.configure_file_menu(popup, FILE_MENU_FOCUS_LAST_IMPORT, FILE_MENU_RETRY_IMPORT)
	parent.add_child(file_menu_button)


func add_tool_buttons(parent: Control) -> void:
	if not SELECTION_TOOLS_VISIBLE:
		return
	for spec in [
		{"id": "magic_wand", "text": "W", "tooltip": Strings.TOOL_MAGIC_WAND},
		{"id": "rectangle", "text": "M", "tooltip": Strings.TOOL_RECTANGLE},
		{"id": "lasso", "text": "L", "tooltip": Strings.TOOL_LASSO},
	]:
		var button := Button.new()
		button.text = String(spec["text"])
		button.tooltip_text = "%s (%s)" % [String(spec["tooltip"]), String(spec["text"])]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(TOOL_BUTTON_SIZE, TOOLBAR_BUTTON_HEIGHT)
		button.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
		var tool_id := String(spec["id"])
		button.toggled.connect(
			func(is_pressed: bool) -> void:
				if is_pressed:
					_tool_manager.set_active_tool(tool_id)
				elif _tool_manager.get_active_tool_id() == tool_id:
					_tool_manager.clear_active_tool()
		)
		_tool_buttons[tool_id] = button
		parent.add_child(button)


func handle_shortcut(event: InputEventKey) -> bool:
	if _tool_manager == null:
		return false
	if event.keycode == KEY_ESCAPE and not _tool_manager.get_active_tool_id().is_empty():
		_tool_manager.clear_active_tool()
		return true
	if _handle_batch_review_shortcut(event):
		return true
	if not SELECTION_TOOLS_VISIBLE:
		return false
	return _tool_manager.handle_shortcut(event.keycode)


func import_files_at_mouse(files: PackedStringArray) -> void:
	_import_flow.import_files_at_mouse(files)


func open_matte_dialog() -> void:
	var source := _single_selected_image()
	if source == null:
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
		return
	_matte_dialog.set_source_image(source)
	_matte_dialog.popup_centered()


func open_slice_dialog() -> void:
	var source := _single_selected_image()
	if source == null:
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
		return
	_slice_dialog.set_source_image(source)
	_slice_dialog.popup_centered()


func open_outline_dialog() -> void:
	var source := _single_selected_image()
	if source == null:
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
		return
	_outline_dialog.set_source_image(source)
	_outline_dialog.popup_centered()


func batch_selected_sprites() -> void:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.size() < 2:
		_status_label.text = Strings.STATUS_BATCH_NEEDS_SELECTION
		return

	var asset_ids: Array[String] = []
	var min_position := Vector2(INF, INF)
	for snapshot in snapshots:
		var data: Dictionary = snapshot["data"]
		var asset_id := String(data.get("asset_id", ""))
		if asset_id.is_empty():
			continue
		asset_ids.append(asset_id)
		var raw_position: Array = data.get("position", [0, 0])
		min_position.x = minf(min_position.x, float(raw_position[0]))
		min_position.y = minf(min_position.y, float(raw_position[1]))

	if asset_ids.size() < 2:
		_status_label.text = Strings.STATUS_BATCH_NEEDS_SELECTION
		return
	var card: Node = _canvas._add_batch_card(
		asset_ids, min_position + Vector2(0, -96), Strings.BATCH_DEFAULT_LABEL
	)
	if card != null:
		_focus_canvas_on_card(card)


func generate_mock_batch() -> void:
	var graph := _make_mock_generate_graph()
	var runner := GraphMockRunnerScript.new()
	var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, "batch_1")
	if not bool(result.get("ok", false)):
		var error: Dictionary = result.get("error", {})
		Log.warn("Mock graph generation failed", error)
		_status_label.text = Strings.STATUS_MOCK_GENERATE_FAILED
		return

	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	var asset_ids: Array = result["asset_ids"]
	var items := _add_generate_graph_canvas_items(
		graph, asset_ids, _canvas.get_mouse_world_position(), Strings.MOCK_BATCH_LABEL
	)
	if not items.is_empty():
		_focus_canvas_on_bounds(_bounds_for_items(items))
	_status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()


func configure_openai_session() -> void:
	_openai_flow.configure_session()


func generate_openai_batch() -> void:
	_openai_flow.generate_batch()


func run_selected_mock_graph() -> void:
	var binding := _selected_graph_binding()
	if binding.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_RUN_NEEDS_SELECTION
		return

	var graph_id := String(binding["graph_id"])
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.STATUS_GRAPH_RUN_MISSING_GRAPH}
		)
		return

	var graph := GraphScript.from_json(graph_data)
	var ghost_error := _first_ghost_node_error(graph)
	if not ghost_error.is_empty():
		_status_label.text = _graph_run_failure_status(ghost_error)
		return
	var batch_node_id := _first_batch_node_id(graph)
	if batch_node_id.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.STATUS_GRAPH_RUN_NO_BATCH}
		)
		return
	var batch_card_id := _graph_batch_card_id(graph.id, batch_node_id)
	if _route_openai_graph_run(graph, batch_node_id, batch_card_id):
		return
	_run_mock_graph(graph, batch_node_id, batch_card_id)


func _run_mock_graph(graph: PFGraph, batch_node_id: String, batch_card_id: String) -> void:
	var runner := GraphMockRunnerScript.new()
	var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, batch_node_id, true)
	if not bool(result.get("ok", false)):
		var error: Dictionary = result.get("error", {})
		Log.warn("Selected mock graph run failed", error)
		_status_label.text = _graph_run_failure_status(error)
		return

	var asset_ids: Array = result["asset_ids"]
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if batch_card_id.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.STATUS_GRAPH_RUN_MISSING_BATCH_CARD}
		)
		return
	_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
	_status_label.text = Strings.STATUS_GRAPH_RUN_DONE % asset_ids.size()


func edit_selected_graph_node() -> void:
	var binding := _selected_graph_binding()
	var node_id := String(binding.get("node_id", ""))
	if binding.is_empty() or node_id.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_EDIT_NEEDS_SELECTION
		return
	var graph_id := String(binding["graph_id"])
	var graph_data := ProjectService.get_graph_data(graph_id)
	var graph := GraphScript.from_json(graph_data)
	var node: PFNode = graph.get_node(node_id)
	if (
		node == null
		or node.is_ghost()
		or not EDITABLE_GRAPH_NODE_TYPES.has(node.get_type())
		or node.get_param_schema().is_empty()
	):
		_status_label.text = Strings.STATUS_GRAPH_EDIT_NOT_AVAILABLE
		return
	_graph_node_params_dialog.configure_for_node(
		graph_id, node_id, node, graph.get_node_params(node_id)
	)
	_graph_node_params_dialog.popup_centered()


func apply_graph_node_params(graph_id: String, node_id: String, params: Dictionary) -> bool:
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_EDIT_FAILED
		return false
	var graph := GraphScript.from_json(graph_data)
	var node: PFNode = graph.get_node(node_id)
	if node == null or node.is_ghost():
		_status_label.text = Strings.STATUS_GRAPH_EDIT_FAILED
		return false
	var merged_params := graph.get_node_params(node_id)
	merged_params.merge(params, true)
	if not graph.set_node_params(node_id, merged_params):
		_status_label.text = Strings.STATUS_GRAPH_EDIT_FAILED
		return false

	var before := graph_data.duplicate(true)
	var after := graph.to_json()
	var apply_snapshot := func(snapshot: Dictionary) -> void:
		ProjectService.set_graph_data(graph_id, snapshot, true)
		_canvas._refresh_graph_node_card(graph_id, node_id)
	UndoService.perform_action(
		"Edit graph node parameters",
		func() -> void: apply_snapshot.call(after),
		func() -> void: apply_snapshot.call(before)
	)
	_status_label.text = Strings.STATUS_GRAPH_EDIT_DONE
	return true


func add_graph_node_to_selected_graph(
	type_name: String, requested_world_position: Variant = null
) -> String:
	var binding := _selected_graph_binding()
	var graph_id := String(binding.get("graph_id", ""))
	if graph_id.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_NEEDS_SELECTION
		return ""
	var registry := NodeRegistryScript.new()
	var node: PFNode = registry.create(type_name)
	if node == null or node.get_type() == "batch":
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return ""
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return ""
	var graph := GraphScript.from_json(graph_data)
	var world_position := _graph_node_add_position(binding)
	if requested_world_position is Vector2:
		var requested_position: Vector2 = requested_world_position
		world_position = requested_position.round()
	var node_id := "%s_%s" % [type_name, IdUtil.uuid_v4().left(8)]
	var item_id := IdUtil.uuid_v4()
	if graph.add_node(node, node_id, {}, world_position).is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return ""

	var before := graph_data.duplicate(true)
	var after := graph.to_json()
	var do_add := func() -> void:
		ProjectService.set_graph_data(graph_id, after, true)
		_canvas._add_graph_node_card(graph_id, node_id, world_position, item_id, false)
		_canvas.select_ids([item_id])
	var undo_add := func() -> void:
		_canvas._remove_item_direct(item_id)
		ProjectService.set_graph_data(graph_id, before, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Add graph node", do_add, undo_add)
	_status_label.text = Strings.STATUS_GRAPH_ADD_DONE % node.get_display_name()
	return node_id


func show_graph_quick_add_menu(screen_position: Vector2i) -> bool:
	if _selected_graph_binding().is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_NEEDS_SELECTION
		return false
	if _graph_quick_add_menu == null:
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return false
	var local_screen_position := Vector2(screen_position) - _canvas.get_screen_position()
	_graph_quick_add_world_position = _canvas.screen_to_world(local_screen_position).round()
	_graph_quick_add_menu.position = screen_position
	_graph_quick_add_menu.popup()
	return true


func show_onboarding_if_needed() -> void:
	call_deferred("_refresh_import_hint")


func _refresh_import_hint() -> void:
	_import_flow.refresh_empty_hint()


func _create_m2_dialogs() -> void:
	_matte_dialog = MatteDialogScript.new()
	_matte_dialog.params_confirmed.connect(_m2_actions.matte_selection_with_params)
	add_child(_matte_dialog)

	_slice_dialog = SliceDialogScript.new()
	_slice_dialog.params_confirmed.connect(_m2_actions.slice_selection_with_params)
	add_child(_slice_dialog)

	_outline_dialog = OutlineDialogScript.new()
	_outline_dialog.params_confirmed.connect(_m2_actions.outline_selection_with_params)
	add_child(_outline_dialog)


func _create_graph_node_params_dialog() -> void:
	_graph_node_params_dialog = GraphNodeParamsDialogScript.new()
	_graph_node_params_dialog.name = "GraphNodeParamsDialog"
	_graph_node_params_dialog.params_confirmed.connect(apply_graph_node_params)
	add_child(_graph_node_params_dialog)


func _add_graph_node_submenu(parent_menu: PopupMenu) -> void:
	_graph_add_menu = PopupMenu.new()
	_graph_add_menu.name = "GraphNodeAddMenu"
	_graph_quick_add_menu = PopupMenu.new()
	_graph_quick_add_menu.name = "GraphNodeQuickAddMenu"
	_graph_add_types.clear()
	var registry := NodeRegistryScript.new()
	var menu_id := GRAPH_ADD_MENU_ID_START
	for type_name in registry.get_registered_types():
		var node: PFNode = registry.create(String(type_name))
		if node == null or node.get_type() == "batch":
			continue
		_graph_add_menu.add_item(node.get_display_name(), menu_id)
		_graph_quick_add_menu.add_item(node.get_display_name(), menu_id)
		_graph_add_types[menu_id] = node.get_type()
		menu_id += 1
	_graph_add_menu.id_pressed.connect(_on_graph_add_menu_pressed)
	_graph_quick_add_menu.id_pressed.connect(_on_graph_quick_add_menu_pressed)
	add_child(_graph_quick_add_menu)
	parent_menu.add_child(_graph_add_menu)
	parent_menu.add_submenu_item(Strings.MENU_ADD_GRAPH_NODE, _graph_add_menu.name)


func _create_batch_menu() -> void:
	_batch_menu = PopupMenu.new()
	_batch_menu.add_item(Strings.BATCH_ACTION_CLEANUP, BATCH_MENU_CLEANUP)
	_batch_menu.add_item(Strings.BATCH_ACTION_MATTE, BATCH_MENU_MATTE)
	_batch_menu.add_item(Strings.BATCH_ACTION_OUTLINE, BATCH_MENU_OUTLINE)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_KEEP, BATCH_MENU_MARK_KEEP)
	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_REJECT, BATCH_MENU_MARK_REJECT)
	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_FLAG, BATCH_MENU_MARK_FLAG)
	_batch_menu.add_item(Strings.BATCH_ACTION_CLEAR_MARK, BATCH_MENU_CLEAR_MARK)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_ALL, BATCH_MENU_FILTER_ALL)
	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_KEEP, BATCH_MENU_FILTER_KEEP)
	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_PENDING, BATCH_MENU_FILTER_PENDING)
	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_REJECT, BATCH_MENU_FILTER_REJECT)
	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_FLAG, BATCH_MENU_FILTER_FLAG)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_LAYOUT_CONTACT, BATCH_MENU_LAYOUT_CONTACT)
	_batch_menu.add_item(Strings.BATCH_ACTION_LAYOUT_FOCUS, BATCH_MENU_LAYOUT_FOCUS)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_CURRENT, BATCH_MENU_COMPARE_CURRENT)
	_batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_PREVIOUS, BATCH_MENU_COMPARE_PREVIOUS)
	_batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_SPLIT, BATCH_MENU_COMPARE_SPLIT)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_EXPORT, BATCH_MENU_EXPORT)
	_batch_menu.id_pressed.connect(_on_batch_menu_id_pressed)
	add_child(_batch_menu)


func _init_tools() -> void:
	_tool_manager = ToolManagerScript.new()
	_tool_manager.register_tool("magic_wand", MagicWandToolScript.new())
	_tool_manager.register_tool("rectangle", RectangleToolScript.new())
	_tool_manager.register_tool("lasso", LassoToolScript.new())
	_tool_manager.tool_changed.connect(_on_tool_changed)
	_tool_manager.selection_changed.connect(_on_tool_selection_changed)
	_canvas.tool_manager = _tool_manager


func _on_file_menu_pressed(id: int) -> void:
	match id:
		FILE_MENU_IMPORT_IMAGES:
			_import_flow.show_import_dialog()
		FILE_MENU_FOCUS_LAST_IMPORT:
			_import_flow.focus_last_import()
		FILE_MENU_RETRY_IMPORT:
			_import_flow.retry_import()
		FILE_MENU_GENERATE_MOCK_BATCH:
			generate_mock_batch()
		FILE_MENU_CONFIGURE_OPENAI_SESSION:
			configure_openai_session()
		FILE_MENU_GENERATE_OPENAI_BATCH:
			generate_openai_batch()
		FILE_MENU_RUN_SELECTED_GRAPH:
			run_selected_mock_graph()
		FILE_MENU_EDIT_SELECTED_GRAPH_NODE:
			edit_selected_graph_node()
		FILE_MENU_NEW:
			_new_project_callback.call()
		FILE_MENU_OPEN:
			_open_project_callback.call()
		FILE_MENU_SAVE:
			_save_project_callback.call()


func _on_graph_add_menu_pressed(id: int) -> void:
	var type_name := String(_graph_add_types.get(id, ""))
	if type_name.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return
	add_graph_node_to_selected_graph(type_name)


func _on_graph_quick_add_menu_pressed(id: int) -> void:
	var type_name := String(_graph_add_types.get(id, ""))
	if type_name.is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return
	add_graph_node_to_selected_graph(type_name, _graph_quick_add_world_position)


func _show_batch_menu(card_id: String, screen_position: Vector2i) -> void:
	_batch_menu_card_id = card_id
	_batch_menu.position = screen_position
	_batch_menu.popup()


func _on_batch_menu_id_pressed(id: int) -> void:
	var asset_ids: Array = _canvas._get_batch_asset_ids(_batch_menu_card_id, true)
	match id:
		BATCH_MENU_CLEANUP:
			_m2_actions.batch_cleanup(
				_batch_menu_card_id,
				asset_ids,
				Pipeline.normalize_params(_cleanup_inspector.get_params(), _project_style_preset())
			)
		BATCH_MENU_MATTE:
			_m2_actions.batch_matte(
				_batch_menu_card_id, asset_ids, {"mode": "flood", "tolerance": 12.0, "feather": 0}
			)
		BATCH_MENU_OUTLINE:
			_m2_actions.batch_outline(
				_batch_menu_card_id, asset_ids, {"type": "outer", "color": Color.BLACK}
			)
		BATCH_MENU_MARK_KEEP:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
			)
		BATCH_MENU_MARK_REJECT:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
			)
		BATCH_MENU_MARK_FLAG:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
			)
		BATCH_MENU_CLEAR_MARK:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
			)
		BATCH_MENU_FILTER_ALL:
			_set_batch_review_filter(
				CanvasBatchCardScript.FILTER_ALL, Strings.STATUS_BATCH_SHOW_ALL
			)
		BATCH_MENU_FILTER_KEEP:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_SHOW_KEEP
			)
		BATCH_MENU_FILTER_PENDING:
			_set_batch_review_filter(
				CanvasBatchCardScript.FILTER_PENDING, Strings.STATUS_BATCH_SHOW_PENDING
			)
		BATCH_MENU_FILTER_REJECT:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_SHOW_REJECT
			)
		BATCH_MENU_FILTER_FLAG:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_SHOW_FLAG
			)
		BATCH_MENU_LAYOUT_CONTACT:
			_set_batch_review_layout(
				CanvasBatchCardScript.LAYOUT_CONTACT, Strings.STATUS_BATCH_LAYOUT_CONTACT
			)
		BATCH_MENU_LAYOUT_FOCUS:
			_set_batch_review_layout(
				CanvasBatchCardScript.LAYOUT_FOCUS, Strings.STATUS_BATCH_LAYOUT_FOCUS
			)
		BATCH_MENU_COMPARE_CURRENT:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_CURRENT, Strings.STATUS_BATCH_COMPARE_CURRENT
			)
		BATCH_MENU_COMPARE_PREVIOUS:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_PREVIOUS, Strings.STATUS_BATCH_COMPARE_PREVIOUS
			)
		BATCH_MENU_COMPARE_SPLIT:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_SPLIT, Strings.STATUS_BATCH_COMPARE_SPLIT
			)
		BATCH_MENU_SPLIT_KEEP:
			var new_keep_card: Variant = _canvas._split_batch_marked(
				_batch_menu_card_id,
				CanvasBatchCardScript.REVIEW_KEEP,
				Strings.BATCH_KEEP_LABEL_SUFFIX
			)
			_status_label.text = (
				Strings.STATUS_BATCH_SPLIT_KEEP
				if new_keep_card != null
				else Strings.STATUS_BATCH_SPLIT_KEEP_EMPTY
			)
		BATCH_MENU_SPLIT:
			var new_card: Variant = _canvas._split_batch_selection(_batch_menu_card_id)
			_status_label.text = (
				Strings.STATUS_BATCH_SPLIT if new_card != null else Strings.STATUS_BATCH_SPLIT_EMPTY
			)
		BATCH_MENU_EXPORT:
			_emit_batch_export(asset_ids)


func _mark_batch_review_state(review_state: String, status_format: String) -> void:
	_mark_batch_review_state_for_card(_batch_menu_card_id, review_state, status_format)


func _mark_batch_review_state_for_card(
	card_id: String, review_state: String, status_format: String
) -> bool:
	var selected_ids: Array = _canvas._get_batch_selected_asset_ids(card_id)
	if selected_ids.is_empty():
		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
		return false
	var marked_count: int = _canvas._set_batch_review_state(
		card_id, selected_ids, review_state, true
	)
	if marked_count <= 0:
		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
		return false
	_status_label.text = status_format % marked_count
	return true


func _handle_batch_review_shortcut(event: InputEventKey) -> bool:
	if event.is_command_or_control_pressed() or event.alt_pressed:
		return false
	if _handle_batch_focus_shortcut(event):
		return true
	var card_id := _selected_batch_card_id()
	var review_state := ""
	var status_format := ""
	match event.keycode:
		KEY_K:
			review_state = CanvasBatchCardScript.REVIEW_KEEP
			status_format = Strings.STATUS_BATCH_MARK_KEEP
		KEY_R:
			review_state = CanvasBatchCardScript.REVIEW_REJECT
			status_format = Strings.STATUS_BATCH_MARK_REJECT
		KEY_F:
			review_state = CanvasBatchCardScript.REVIEW_FLAG
			status_format = Strings.STATUS_BATCH_MARK_FLAG
		KEY_C:
			review_state = CanvasBatchCardScript.REVIEW_NONE
			status_format = Strings.STATUS_BATCH_MARK_CLEAR
		_:
			return false
	_mark_batch_review_state_for_card(card_id, review_state, status_format)
	return true


func _handle_batch_focus_shortcut(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_RIGHT, KEY_DOWN:
			return _focus_selected_batch_relative(1)
		KEY_LEFT, KEY_UP:
			return _focus_selected_batch_relative(-1)
	return false


func _focus_selected_batch_relative(step: int) -> bool:
	var card_id := _selected_batch_card_id()
	if card_id.is_empty():
		return false
	var focus_result: Dictionary = _canvas._focus_batch_relative(card_id, step, true)
	if focus_result.is_empty():
		_status_label.text = Strings.STATUS_BATCH_FOCUS_EMPTY
		return true
	_status_label.text = (
		Strings.STATUS_BATCH_FOCUS_FORMAT % [focus_result["index"], focus_result["total"]]
	)
	return true


func _selected_batch_card_id() -> String:
	var selected_ids: Array = _canvas.get_selected_ids()
	if selected_ids.is_empty():
		return ""
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		var item_id := String(item_data.get("id", ""))
		if selected_ids.has(item_id) and not _canvas._get_batch_asset_ids(item_id).is_empty():
			return item_id
	return ""


func _set_batch_review_filter(review_filter: String, status_text: String) -> void:
	if not _canvas._set_batch_review_filter(_batch_menu_card_id, review_filter, true):
		_status_label.text = Strings.STATUS_BATCH_FILTER_FAILED
		return
	_status_label.text = status_text


func _set_batch_review_layout(review_layout: String, status_text: String) -> void:
	if not _canvas._set_batch_review_layout(_batch_menu_card_id, review_layout, true):
		_status_label.text = Strings.STATUS_BATCH_LAYOUT_FAILED
		return
	_status_label.text = status_text


func _set_batch_compare_mode(compare_mode: String, status_text: String) -> void:
	if not _canvas._set_batch_compare_mode(_batch_menu_card_id, compare_mode, true):
		_status_label.text = Strings.STATUS_BATCH_COMPARE_EMPTY
		return
	_status_label.text = status_text


func _emit_batch_export(asset_ids: Array) -> void:
	var snapshots := []
	for asset_id in asset_ids:
		var image := AssetLibrary.get_image(String(asset_id))
		if image == null:
			continue
		snapshots.append({"data": {"asset_id": String(asset_id)}, "image": image})
	if snapshots.is_empty():
		_status_label.text = Strings.STATUS_EXPORT_EMPTY
		return
	export_snapshots_requested.emit(snapshots, "batch.png")


func _focus_canvas_on_card(card: Node) -> void:
	_focus_canvas_on_bounds(card.get_canvas_bounds())


func _focus_canvas_on_bounds(bounds: Rect2) -> void:
	if (
		bounds.size.x <= 0.0
		or bounds.size.y <= 0.0
		or _canvas.size.x <= 0.0
		or _canvas.size.y <= 0.0
	):
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


func _single_selected_image() -> Image:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.size() != 1:
		return null
	return snapshots[0]["image"]


func _on_tool_changed(tool_id: String) -> void:
	for button_id in _tool_buttons.keys():
		var button: Button = _tool_buttons[button_id]
		button.set_pressed_no_signal(String(button_id) == tool_id)
	if tool_id.is_empty():
		_status_label.text = Strings.STATUS_TOOL_OFF
		return
	var tool: Variant = _tool_manager.get_current_tool()
	_status_label.text = Strings.STATUS_TOOL_FORMAT % tool.get_name()


func _on_tool_selection_changed(selection: PFSelection) -> void:
	if selection == null or selection.is_empty():
		_status_label.text = Strings.STATUS_SELECTION_EMPTY
		return
	var bbox := selection.get_bbox()
	_status_label.text = (
		Strings.STATUS_SELECTION_FORMAT % [bbox.size.x, bbox.size.y, selection.get_selected_count()]
	)


func _graph_run_failure_status(error: Dictionary) -> String:
	var message := String(error.get("message", "")).strip_edges()
	if message.is_empty():
		return Strings.STATUS_GRAPH_RUN_FAILED
	return Strings.STATUS_GRAPH_RUN_FAILED_DETAIL % message


func _graph_node_add_position(binding: Dictionary) -> Vector2:
	var item_id := String(binding.get("item_id", ""))
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		if String(item_data.get("id", "")) != item_id:
			continue
		var raw_position: Variant = item_data.get("position", [0, 0])
		return Vector2(float(raw_position[0]), float(raw_position[1])) + Vector2(280, 0)
	return _canvas.screen_to_world(_canvas.size * 0.5)


func _graph_provider_id(graph: PFGraph) -> String:
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node != null and node.get_type() == "ai_generate":
			return String(graph.get_node_params(String(node_id)).get("provider_id", "mock"))
	return "mock"


func _route_openai_graph_run(graph: PFGraph, batch_node_id: String, batch_card_id: String) -> bool:
	if _graph_provider_id(graph) != "openai_image":
		return false
	if batch_card_id.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.STATUS_GRAPH_RUN_MISSING_BATCH_CARD}
		)
		return true
	_openai_flow.run_graph(graph, batch_node_id, batch_card_id)
	return true


func _project_style_preset() -> Dictionary:
	var style_data: Variant = ProjectService.current_project.manifest.get("style_preset", {})
	return style_data if style_data is Dictionary else {}


func _make_mock_generate_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_mock_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "Mock Generate Batch"
	graph.add_node(
		ObjectListNodeScript.new(),
		"objects",
		{"items": "barrel\nfence\nscarecrow\ncrate\nwell"},
		Vector2(0, 0)
	)
	graph.add_node(
		SizeSpecNodeScript.new(),
		"size",
		{"width": 32, "height": 32, "per_subject": 1},
		Vector2(0, 150)
	)
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 2, "seed": 1000},
		Vector2(280, 75)
	)
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, 29)
	)
	graph.add_edge("objects", "items", "generate", "items")
	graph.add_edge("size", "spec", "generate", "spec")
	graph.add_edge("generate", "images", "batch_1", "in")
	return graph


func _add_generate_graph_canvas_items(
	graph: PFGraph, asset_ids: Array, anchor: Vector2, batch_label: String
) -> Array:
	var items := []
	for node_id in ["objects", "size", "generate"]:
		var node_item: Node = _canvas._add_graph_node_card(
			graph.id, node_id, anchor + _graph_node_position(graph, node_id), "", false
		)
		if node_item != null:
			items.append(node_item)
	var batch_card: Node = _canvas._add_batch_card(
		asset_ids,
		anchor + _graph_node_position(graph, "batch_1"),
		batch_label,
		"",
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


func _first_batch_node_id(graph: PFGraph) -> String:
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node != null and node.get_type() == "batch":
			return String(node_id)
	return ""


func _first_ghost_node_error(graph: PFGraph) -> Dictionary:
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node != null and node.is_ghost():
			return {
				"code": "ghost_node",
				"message": Strings.STATUS_GRAPH_RUN_MISSING_NODE_TYPE % node.get_type(),
			}
	return {}


func _selected_graph_binding() -> Dictionary:
	var selected_ids: Array = _canvas.get_selected_ids()
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		if not selected_ids.has(String(item_data.get("id", ""))):
			continue
		var graph_id := String(item_data.get("graph_id", ""))
		var node_id := String(item_data.get("node_id", ""))
		if graph_id.is_empty() or node_id.is_empty():
			continue
		return {"item_id": String(item_data["id"]), "graph_id": graph_id, "node_id": node_id}
	var selected_edge: Dictionary = _canvas._selected_graph_edge.duplicate(true)
	var edge_graph_id := String(selected_edge.get("graph_id", ""))
	if not edge_graph_id.is_empty():
		return {"item_id": "", "graph_id": edge_graph_id, "node_id": ""}
	return {}


func _graph_batch_card_id(graph_id: String, batch_node_id: String) -> String:
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		if (
			String(item_data.get("graph_id", "")) == graph_id
			and String(item_data.get("node_id", "")) == batch_node_id
		):
			return String(item_data.get("id", ""))
	return ""
