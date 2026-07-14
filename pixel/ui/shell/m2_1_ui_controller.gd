# gdlint: disable=max-file-lines,max-public-methods
class_name PFM21UiController
extends Node

## M2.1 UI 接线控制器。

signal export_snapshots_requested(snapshots: Array, default_file: String)
signal recent_project_requested(path: String)

const Strings := preload("res://ui/shell/strings.gd")
const ToolManagerScript := preload("res://ui/tools/tool_manager.gd")
const MagicWandToolScript := preload("res://ui/tools/magic_wand_tool.gd")
const RectangleToolScript := preload("res://ui/tools/rectangle_tool.gd")
const LassoToolScript := preload("res://ui/tools/lasso_tool.gd")
const MatteDialogScript := preload("res://ui/dialogs/matte_dialog.gd")
const SliceDialogScript := preload("res://ui/dialogs/slice_dialog.gd")
const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
const GraphNodeParamsDialogScript := preload("res://ui/dialogs/graph_node_params_dialog.gd")
const GenerationModelPolicyScript := preload("res://services/generation_model_policy.gd")
const ImportFlowControllerScript := preload("res://ui/shell/import_flow_controller.gd")
const MenuBuilder := preload("res://ui/shell/m2_menu_builder.gd")
const OpenAIGenerationControllerScript := preload("res://ui/shell/openai_generation_controller.gd")
const ProviderSettingsDialogScript := preload("res://ui/dialogs/provider_settings_dialog.gd")
const BoardEditorScript := preload("res://ui/board/board_editor.gd")
const PixelEditorScript := preload("res://ui/editor/pixel_editor.gd")
const PluginManagerDialogScript := preload("res://ui/dialogs/plugin_manager_dialog.gd")
const ComfyUITemplateDialogScript := preload("res://ui/dialogs/comfyui_template_dialog.gd")
const V1OnboardingDialogScript := preload("res://ui/dialogs/v1_onboarding_dialog.gd")
const PixelEditorFlowControllerScript := preload("res://ui/shell/pixel_editor_flow_controller.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const OfflineExampleControllerScript := preload("res://ui/shell/offline_example_controller.gd")
const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ResultBranchBuilder := preload("res://services/result_branch_builder.gd")
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")
const FrameRunPlanner := preload("res://services/frame_run_planner.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
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
const FILE_MENU_PROVIDER_SETTINGS := 11
const FILE_MENU_OPEN_BOARD := 12
const FILE_MENU_OPEN_PIXEL_EDITOR := 13
const FILE_MENU_PLUGIN_MANAGER := 14
const FILE_MENU_COMFY_TEMPLATES := 15
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
const BATCH_MENU_EDIT := 20
const SELECTION_TOOLS_VISIBLE := false
const RECENT_MENU_REMOVE_MISSING := 999

var _canvas: Control = null
var _cleanup_inspector: Control = null
var _status_label: Label = null
var _cost_label: Label = null
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
var _graph_add_parent_menu: PopupMenu = null
var _graph_add_parent_index := -1
var _graph_add_types := {}
var _graph_quick_add_world_position := Vector2.ZERO
var _active_graph_id := ""
var _batch_menu: PopupMenu = null
var _batch_menu_card_id := ""
var _import_flow: Node = null
var _openai_flow: Node = null
var _offline_example_flow: Node = null
var _provider_settings_dialog: ConfirmationDialog = null
var _board_editor: ConfirmationDialog = null
var _pixel_editor: ConfirmationDialog = null
var _plugin_manager: ConfirmationDialog = null
var _comfy_templates: ConfirmationDialog = null
var _v1_onboarding: ConfirmationDialog = null
var _pixel_editor_flow: RefCounted = null
var _recent_projects_menu: PopupMenu = null
var _recent_project_paths := {}


func setup(
	canvas: Control,
	cleanup_inspector: Control,
	status_label: Label,
	cost_label: Label,
	m2_actions: Variant,
	new_project_callback: Callable,
	open_project_callback: Callable,
	save_project_callback: Callable
) -> void:
	_canvas = canvas
	_cleanup_inspector = cleanup_inspector
	_status_label = status_label
	_cost_label = cost_label
	_m2_actions = m2_actions
	_new_project_callback = new_project_callback
	_open_project_callback = open_project_callback
	_save_project_callback = save_project_callback
	_import_flow = ImportFlowControllerScript.new()
	_import_flow.name = "ImportFlowController"
	add_child(_import_flow)
	_import_flow.setup(_canvas, _status_label, self, _add_reference_assets_to_graph)
	_import_flow.reference_asset_imported.connect(_on_reference_asset_imported)
	_offline_example_flow = OfflineExampleControllerScript.new()
	_offline_example_flow.name = "OfflineExampleController"
	add_child(_offline_example_flow)
	_offline_example_flow.setup(_canvas, _status_label)
	_provider_settings_dialog = ProviderSettingsDialogScript.new()
	_provider_settings_dialog.name = "ProviderSettingsDialog"
	add_child(_provider_settings_dialog)
	_openai_flow = OpenAIGenerationControllerScript.new()
	_openai_flow.name = "OpenAIGenerationController"
	add_child(_openai_flow)
	_openai_flow.setup(_canvas, _status_label, _cost_label, _provider_settings_dialog)
	_board_editor = BoardEditorScript.new()
	_board_editor.name = "BoardEditor"
	add_child(_board_editor)
	_pixel_editor = PixelEditorScript.new()
	_pixel_editor.name = "PixelEditor"
	add_child(_pixel_editor)
	_pixel_editor_flow = PixelEditorFlowControllerScript.new()
	_pixel_editor_flow.setup(_canvas, _status_label, _pixel_editor)
	_plugin_manager = PluginManagerDialogScript.new()
	_plugin_manager.name = "PluginManagerDialog"
	add_child(_plugin_manager)
	_comfy_templates = ComfyUITemplateDialogScript.new()
	_comfy_templates.name = "ComfyUITemplateDialog"
	add_child(_comfy_templates)
	_v1_onboarding = V1OnboardingDialogScript.new()
	_v1_onboarding.name = "V1OnboardingDialog"
	_v1_onboarding.setup_completed.connect(_on_v1_setup_completed)
	add_child(_v1_onboarding)
	_create_m2_dialogs()
	_create_graph_node_params_dialog()
	_create_batch_menu()
	_init_tools()
	_canvas.batch_context_requested.connect(_show_batch_menu)
	_canvas.graph_quick_add_requested.connect(show_graph_quick_add_menu)
	_canvas.asset_edit_requested.connect(_open_pixel_editor)
	_canvas.image_paste_requested.connect(_import_flow.import_clipboard_image)
	ProjectService.project_loaded.connect(func(_project: Variant) -> void: _active_graph_id = "")
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)


func add_file_menu(parent: Control) -> void:
	var file_menu_button := MenuButton.new()
	file_menu_button.name = "FileMenu"
	file_menu_button.set_meta("action_id", "file")
	file_menu_button.custom_minimum_size = Vector2(FILE_MENU_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	file_menu_button.focus_mode = Control.FOCUS_NONE
	file_menu_button.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
	var popup := file_menu_button.get_popup()
	MenuBuilder.populate_file(file_menu_button, popup, self, _add_graph_node_submenu)
	_add_recent_projects_submenu(popup)
	popup.id_pressed.connect(_on_file_menu_pressed)
	_import_flow.configure_file_menu(popup, FILE_MENU_FOCUS_LAST_IMPORT, FILE_MENU_RETRY_IMPORT)
	parent.add_child(file_menu_button)


func _add_recent_projects_submenu(parent_menu: PopupMenu) -> void:
	_recent_projects_menu = PopupMenu.new()
	_recent_projects_menu.name = "RecentProjectsMenu"
	_recent_projects_menu.about_to_popup.connect(_refresh_recent_projects_menu)
	_recent_projects_menu.id_pressed.connect(_on_recent_project_pressed)
	parent_menu.add_child(_recent_projects_menu)
	parent_menu.add_submenu_item(Strings.text("MENU_RECENT_PROJECTS"), _recent_projects_menu.name)
	_refresh_recent_projects_menu()


func _refresh_recent_projects_menu() -> void:
	_recent_projects_menu.clear()
	_recent_project_paths.clear()
	var recent: Array = SettingsService.get_recent_projects()
	for index in range(recent.size()):
		var path := String(recent[index])
		var label := path.get_file().get_basename()
		if not FileAccess.file_exists(path):
			label = Strings.text("RECENT_PROJECT_MISSING_FORMAT") % label
		_recent_projects_menu.add_item(label, index)
		_recent_projects_menu.set_item_disabled(index, not FileAccess.file_exists(path))
		_recent_project_paths[index] = path
	if recent.is_empty():
		_recent_projects_menu.add_item(Strings.text("RECENT_PROJECT_EMPTY"), 0)
		_recent_projects_menu.set_item_disabled(0, true)
	else:
		_recent_projects_menu.add_separator()
		_recent_projects_menu.add_item(
			Strings.text("ACTION_REMOVE_MISSING_RECENT"), RECENT_MENU_REMOVE_MISSING
		)


func _on_recent_project_pressed(id: int) -> void:
	if id == RECENT_MENU_REMOVE_MISSING:
		var removed := SettingsService.remove_missing_recent_projects()
		_status_label.text = Strings.text("STATUS_RECENT_REMOVED_FORMAT") % removed
		_refresh_recent_projects_menu()
	elif _recent_project_paths.has(id):
		recent_project_requested.emit(String(_recent_project_paths[id]))


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
	_offline_example_flow.open()


func configure_openai_session() -> void:
	_openai_flow.configure_session()


func generate_openai_batch() -> void:
	_openai_flow.generate_batch()


func cancel_graph_run(graph_id: String, generate_node_id: String = "") -> bool:
	return _openai_flow.cancel_graph(graph_id, generate_node_id)


func _import_reference_for_node(graph_id: String, node_id: String) -> void:
	_import_flow.show_reference_import_dialog(
		{"mode": "node", "graph_id": graph_id, "node_id": node_id}
	)


func handle_graph_node_action(graph_id: String, node_id: String, action_id: String) -> void:
	match action_id:
		"run", "retry", "retry_failed":
			_run_graph_node(graph_id, node_id)
		"cancel":
			cancel_graph_run(graph_id, node_id)
		"fix_input":
			edit_selected_graph_node()
		"import_reference":
			_import_reference_for_node(graph_id, node_id)
		"import_reference_set":
			_import_flow.show_reference_import_dialog(
				{"mode": "reference_set", "graph_id": graph_id, "node_id": node_id}
			)


func _handle_batch_run_action(graph_id: String, node_id: String, action_id: String) -> void:
	match action_id:
		"retry":
			_run_graph_node(graph_id, node_id)
		"remove":
			_canvas.delete_selected()


func handle_batch_face_action(card_id: String, action_id: String, asset_ids: Array) -> void:
	match action_id:
		"process", "process_all":
			_m2_actions.batch_cleanup(
				card_id, asset_ids, Pipeline.normalize_params(_cleanup_inspector.get_params())
			)
		"export":
			_emit_batch_export(asset_ids)
		"continue":
			var card: Node = _canvas._items_by_id.get(card_id, null)
			if card == null or asset_ids.is_empty():
				_status_label.text = Strings.text("STATUS_CANDIDATE_BRANCH_FAILED")
				return
			var meta: Dictionary = AssetLibrary.get_asset_meta(String(asset_ids[0]))
			var provenance: Dictionary = meta.get("provenance", {})
			_apply_result_branch(
				"continue_branch",
				{
					"graph_id": String(card.graph_id),
					"batch_node_id": String(card.node_id),
					"asset_ids": asset_ids.duplicate(),
					"snapshot": provenance.get("generation_snapshot", {}),
				}
			)


func _handle_candidate_action(action_id: String, context: Dictionary) -> void:
	var snapshot: Dictionary = context.get("snapshot", {})
	match action_id:
		"copy_prompt":
			DisplayServer.clipboard_set(String(snapshot.get("prompt", "")))
			_status_label.text = Strings.text("STATUS_CANDIDATE_PROMPT_COPIED")
		"copy_settings":
			DisplayServer.clipboard_set(JSON.stringify(snapshot, "  "))
			_status_label.text = Strings.text("STATUS_CANDIDATE_SETTINGS_COPIED")
		"rerun":
			_run_graph_node(
				String(context.get("graph_id", "")), String(snapshot.get("source_node_id", ""))
			)
		"as_reference", "continue_branch":
			_apply_result_branch(action_id, context)


func _handle_project_resource_drop(resource: Dictionary, world_position: Vector2) -> void:
	match String(resource.get("kind", "")):
		"project_asset":
			if not bool(resource.get("available", false)):
				_status_label.text = Strings.text("STATUS_RESOURCE_UNAVAILABLE")
				return
			add_graph_node_to_selected_graph(
				"image_input", world_position, {"asset_id": String(resource.get("asset_id", ""))}
			)
		"prompt_preset":
			_drop_prompt_resource(resource.get("preset", {}), world_position)
		"workflow_template":
			_insert_workflow_template(resource.get("template", {}), world_position)


func _save_selected_frame_as_workflow() -> Dictionary:
	var selected_ids: Array = _canvas.get_selected_ids()
	var frame := {}
	for raw_item in _canvas.export_canvas_data().get("items", []):
		if (
			raw_item is Dictionary
			and selected_ids.has(String(raw_item.get("id", "")))
			and String(raw_item.get("type", "")) == "frame"
		):
			frame = raw_item
			break
	if frame.is_empty():
		_status_label.text = Strings.text("STATUS_WORKFLOW_NEEDS_FRAME")
		return {"ok": false, "code": "frame_not_selected"}
	var graph_id := String(frame.get("graph_id", ""))
	var result := WorkflowTemplateService.build_from_frame(
		String(frame.get("title", Strings.text("FRAME_DEFAULT_TITLE"))),
		ProjectService.get_graph_data(graph_id),
		_canvas.export_canvas_data(),
		String(frame.get("id", ""))
	)
	if not bool(result.get("ok", false)):
		_status_label.text = (
			Strings.text("STATUS_WORKFLOW_SAVE_FAILED_FORMAT") % String(result.get("code", ""))
		)
		return result
	var saved := WorkflowTemplateService.save_template(result["template"])
	if bool(saved.get("ok", false)):
		EventBus.workflow_templates_changed.emit()
		_status_label.text = (
			Strings.text("STATUS_WORKFLOW_SAVED_FORMAT")
			% [result["template"]["name"], int(result.get("external_edge_count", 0))]
		)
	else:
		_status_label.text = (
			Strings.text("STATUS_WORKFLOW_SAVE_FAILED_FORMAT") % saved.get("error", -1)
		)
	return saved


func _insert_workflow_template(template_value: Variant, world_position: Vector2) -> Dictionary:
	if not (template_value is Dictionary):
		_status_label.text = Strings.text("STATUS_RESOURCE_UNAVAILABLE")
		return {"ok": false, "code": "template_unavailable"}
	var graphs := ProjectService.get_graphs_data()
	var graph_id := _resolve_target_graph_id(_selected_graph_binding(), graphs)
	var before_graph: Dictionary = graphs.get(graph_id, {})
	if before_graph.is_empty():
		var graph := GraphScript.new()
		graph.id = graph_id
		before_graph = graph.to_json()
	var before_canvas: Dictionary = _canvas.export_canvas_data()
	var instance := WorkflowTemplateService.instantiate(
		template_value, before_graph, before_canvas, world_position
	)
	if not bool(instance.get("ok", false)):
		_status_label.text = (
			Strings.text("STATUS_WORKFLOW_INSERT_FAILED_FORMAT") % String(instance.get("code", ""))
		)
		return instance
	var after_graph: Dictionary = instance["graph"]
	var after_canvas: Dictionary = instance["canvas"]
	var item_ids: Array = instance["item_ids"]
	var apply := func(graph_data: Dictionary, canvas_data: Dictionary, selection: Array) -> void:
		ProjectService.set_graph_data(graph_id, graph_data, true)
		ProjectService.set_canvas_data(canvas_data, true)
		_canvas.load_canvas_data(canvas_data)
		_canvas.select_ids(selection)
	UndoService.perform_action(
		"Insert workflow template",
		func() -> void: apply.call(after_graph, after_canvas, item_ids),
		func() -> void: apply.call(before_graph, before_canvas, [])
	)
	_status_label.text = (
		Strings.text("STATUS_WORKFLOW_INSERTED_FORMAT")
		% [String(template_value.get("name", "")), item_ids.size() - 1]
	)
	return instance


func _drop_prompt_resource(preset_value: Variant, world_position: Vector2) -> void:
	if not (preset_value is Dictionary):
		_status_label.text = Strings.text("STATUS_RESOURCE_UNAVAILABLE")
		return
	var binding := _selected_graph_binding()
	var before_graphs := ProjectService.get_graphs_data()
	var graph_id := _resolve_target_graph_id(binding, before_graphs)
	var before: Dictionary = before_graphs.get(graph_id, {})
	var graph := GraphScript.from_json(before) if not before.is_empty() else GraphScript.new()
	graph.id = graph_id
	var node_id := "prompt_preset_%s" % IdUtil.uuid_v4().left(8)
	graph.add_node(
		PromptPresetNodeScript.new(),
		node_id,
		{"preset": Dictionary(preset_value).duplicate(true)},
		world_position
	)
	var target_generate_id := _target_generate_node_id(graph, String(binding.get("node_id", "")))
	if not target_generate_id.is_empty():
		var kept_edges: Array[Dictionary] = []
		for edge in graph.edges:
			var to_data: Array = edge.get("to", ["", ""])
			if String(to_data[0]) == target_generate_id and String(to_data[1]) == "prefix":
				continue
			kept_edges.append(edge)
		graph.edges = kept_edges
		graph.add_edge(node_id, "prefix", target_generate_id, "prefix")
	var after := graph.to_json()
	var item_id := IdUtil.uuid_v4()
	var do_add := func() -> void:
		ProjectService.set_graph_data(graph_id, after, true)
		_canvas._add_graph_node_card(graph_id, node_id, world_position, item_id, false)
		_canvas.select_ids([item_id])
	var undo_add := func() -> void:
		_canvas._remove_item_direct(item_id)
		if before.is_empty():
			var graphs := ProjectService.get_graphs_data()
			graphs.erase(graph_id)
			ProjectService.set_graphs_data(graphs, true)
		else:
			ProjectService.set_graph_data(graph_id, before, true)
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Add prompt preset resource", do_add, undo_add)
	_status_label.text = Strings.text("STATUS_STYLE_RESOURCE_ADDED")


func _apply_result_branch(action_id: String, context: Dictionary) -> void:
	var graph_id := String(context.get("graph_id", ""))
	var graph_data := ProjectService.get_graph_data(graph_id)
	var asset_ids: Array = context.get("asset_ids", [])
	if graph_data.is_empty() or asset_ids.is_empty():
		_status_label.text = Strings.text("STATUS_CANDIDATE_BRANCH_FAILED")
		return
	var graph := GraphScript.from_json(graph_data)
	var anchor := _result_branch_anchor(String(context.get("batch_node_id", "")))
	var result := ResultBranchBuilder.build(
		graph, action_id, asset_ids, context.get("snapshot", {}), anchor
	)
	if not bool(result.get("ok", false)):
		_status_label.text = Strings.text("STATUS_CANDIDATE_BRANCH_FAILED")
		return
	var after := graph.to_json()
	var item_specs := _result_branch_item_specs(
		after,
		result.get("created_node_ids", []),
		String(result.get("focus_node_id", "")),
		result.get("positions_by_node", {})
	)
	var apply_snapshot := func(snapshot: Dictionary, add_items: bool) -> void:
		ProjectService.set_graph_data(graph_id, snapshot, true)
		if add_items:
			_add_result_branch_items(graph_id, item_specs)
		else:
			for spec in item_specs:
				_canvas._remove_item_direct(String(spec["item_id"]))
		_canvas._emit_canvas_changed()
	UndoService.perform_action(
		"Create result branch",
		func() -> void: apply_snapshot.call(after, true),
		func() -> void: apply_snapshot.call(graph_data, false)
	)
	_status_label.text = Strings.text(
		(
			"STATUS_CANDIDATE_REFERENCE_CREATED"
			if action_id == "as_reference"
			else "STATUS_CANDIDATE_BRANCH_CREATED"
		)
	)


func _result_branch_anchor(batch_node_id: String) -> Vector2:
	for raw_item in _canvas.export_canvas_data().get("items", []):
		var item: Dictionary = raw_item
		if String(item.get("node_id", "")) == batch_node_id:
			var raw_position: Array = item.get("position", [0, 0])
			return Vector2(float(raw_position[0]), float(raw_position[1])) + Vector2(680, 0)
	return _canvas.get_mouse_world_position()


func _result_branch_item_specs(
	graph_data: Dictionary,
	node_ids: Array,
	focus_node_id: String,
	positions_by_node: Dictionary = {}
) -> Array:
	var specs := []
	for raw_node in graph_data.get("nodes", []):
		var node: Dictionary = raw_node
		var node_id := String(node.get("id", ""))
		if not node_ids.has(node_id):
			continue
		(
			specs
			. append(
				{
					"item_id": IdUtil.uuid_v4(),
					"node_id": node_id,
					"type": String(node.get("type", "")),
					"position": positions_by_node.get(node_id, [0, 0]),
					"focus": node_id == focus_node_id,
				}
			)
		)
	return specs


func _add_result_branch_items(graph_id: String, specs: Array) -> void:
	var focus_item_id := ""
	for spec in specs:
		var raw_position: Array = spec.get("position", [0, 0])
		var position := Vector2(float(raw_position[0]), float(raw_position[1]))
		if String(spec.get("type", "")) == "batch":
			_canvas._add_batch_card(
				[],
				position,
				Strings.text("BATCH_DEFAULT_LABEL"),
				String(spec["item_id"]),
				false,
				graph_id,
				String(spec["node_id"])
			)
		else:
			_canvas._add_graph_node_card(
				graph_id, String(spec["node_id"]), position, String(spec["item_id"]), false
			)
		if bool(spec.get("focus", false)):
			focus_item_id = String(spec["item_id"])
	if not focus_item_id.is_empty():
		_canvas.select_ids([focus_item_id])


func run_selected_mock_graph() -> void:
	var selected_frame_id := _selected_frame_id()
	if not selected_frame_id.is_empty():
		_run_selected_frame(selected_frame_id)
		return
	var binding := _selected_graph_binding()
	if binding.is_empty():
		_status_label.text = Strings.text("STATUS_GRAPH_RUN_NEEDS_SELECTION")
		return

	var graph_id := String(binding["graph_id"])
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.text("STATUS_GRAPH_RUN_MISSING_GRAPH")}
		)
		return

	var graph := GraphScript.from_json(graph_data)
	var ghost_error := _first_ghost_node_error(graph)
	if not ghost_error.is_empty():
		_status_label.text = _graph_run_failure_status(ghost_error)
		return
	_run_bound_graph(graph, String(binding.get("node_id", "")))


func _run_selected_frame(frame_id: String) -> void:
	var canvas_data: Dictionary = _canvas.export_canvas_data()
	var frame := {}
	for item in canvas_data.get("items", []):
		if String(item.get("id", "")) == frame_id:
			frame = item
			break
	var graph_id := String(frame.get("graph_id", ""))
	var plan := FrameRunPlanner.plan(ProjectService.get_graph_data(graph_id), canvas_data, frame_id)
	if not bool(plan.get("ok", false)):
		_status_label.text = Strings.text("STATUS_FRAME_RUN_UNAVAILABLE")
		return
	for node_id in plan["included_node_ids"]:
		_canvas._set_graph_node_status(
			graph_id,
			String(node_id),
			"CONTENT_STATUS_WAITING",
			Strings.text("CONTENT_SCOPE_PLANNED")
		)
	_status_label.text = (
		Strings.text("STATUS_FRAME_RUN_PLAN_FORMAT")
		% [plan["target_generate_ids"].size(), plan["request_count"], plan["result_count"]]
	)
	_cost_label.text = (
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % float(plan["known_cost"])
		if float(plan["known_cost"]) >= 0.0
		else Strings.text("CONTENT_COST_UNKNOWN")
	)
	for target_id in plan["target_generate_ids"]:
		_run_graph_node(graph_id, String(target_id))


func _selected_frame_id() -> String:
	var selected_ids: Array = _canvas.get_selected_ids()
	for item in _canvas.export_canvas_data().get("items", []):
		if selected_ids.has(String(item.get("id", ""))) and String(item.get("type", "")) == "frame":
			return String(item.get("id", ""))
	return ""


func _toggle_canvas_edges() -> void:
	var visible: bool = bool(_canvas._toggle_graph_edges())
	_status_label.text = Strings.text("STATUS_EDGES_VISIBLE" if visible else "STATUS_EDGES_HIDDEN")


func _run_graph_node(graph_id: String, node_id: String) -> void:
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.text("STATUS_GRAPH_RUN_MISSING_GRAPH")}
		)
		return
	_run_bound_graph(GraphScript.from_json(graph_data), node_id)


func _run_bound_graph(graph: PFGraph, selected_node_id: String) -> void:
	var generate_node_id := _target_generate_node_id(graph, selected_node_id)
	var target := _prepare_run_target(graph, generate_node_id, selected_node_id)
	var batch_node_id := String(target.get("batch_node_id", ""))
	if batch_node_id.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": String(target.get("error", Strings.text("STATUS_GRAPH_RUN_NO_BATCH")))}
		)
		return
	var batch_card_id := String(target.get("batch_card_id", ""))
	_set_batch_run_state(
		graph,
		batch_node_id,
		"waiting",
		_expected_batch_count(graph, generate_node_id),
		Strings.text("CONTENT_PLACEHOLDER_WAITING")
	)
	if _route_provider_graph_run(graph, generate_node_id, batch_node_id, batch_card_id):
		return
	_run_mock_graph(graph, generate_node_id, batch_node_id, batch_card_id)


func _run_mock_graph(
	graph: PFGraph, generate_node_id: String, batch_node_id: String, batch_card_id: String
) -> void:
	_set_batch_run_state(
		graph,
		batch_node_id,
		"running",
		_expected_batch_count(graph, generate_node_id),
		Strings.text("CONTENT_DETAIL_MOCK_RUNNING")
	)
	_canvas._set_graph_node_status(
		graph.id,
		generate_node_id,
		"CONTENT_STATUS_RUNNING",
		Strings.text("CONTENT_DETAIL_MOCK_RUNNING")
	)
	var runner := GraphMockRunnerScript.new()
	var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, batch_node_id)
	if not bool(result.get("ok", false)):
		var error: Dictionary = result.get("error", {})
		var message := _graph_error_message(error)
		Log.warn("Selected mock graph run failed", error)
		var error_type := (
			"image_input"
			if (
				String(error.get("code", ""))
				in ["missing_asset_reference", "asset_not_found", "asset_decode_failed"]
			)
			else "ai_generate"
		)
		if error_type == "ai_generate":
			_canvas._set_graph_node_status(
				graph.id, generate_node_id, "CONTENT_STATUS_FAILED", message
			)
		else:
			_canvas._set_graph_node_type_status(
				graph.id, error_type, "CONTENT_STATUS_FAILED", message
			)
		_status_label.text = _graph_run_failure_status({"message": message})
		_set_batch_run_state(
			graph, batch_node_id, "failed", _expected_batch_count(graph, generate_node_id), message
		)
		return

	var asset_ids: Array = BatchNodeScript.get_visible_asset_ids(
		graph.get_node_params(batch_node_id)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	if batch_card_id.is_empty():
		var message := Strings.text("STATUS_GRAPH_RUN_MISSING_BATCH_CARD")
		_canvas._set_graph_node_status(graph.id, generate_node_id, "CONTENT_STATUS_FAILED", message)
		_status_label.text = _graph_run_failure_status({"message": message})
		return
	_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
	_set_batch_run_state(graph, batch_node_id, "complete", asset_ids.size(), "")
	_canvas._set_graph_node_status(
		graph.id,
		generate_node_id,
		"CONTENT_STATUS_COMPLETE",
		Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % asset_ids.size()
	)
	_status_label.text = Strings.text("STATUS_GRAPH_RUN_DONE_FORMAT") % asset_ids.size()


func _prepare_run_target(
	graph: PFGraph, generate_node_id: String, selected_node_id: String
) -> Dictionary:
	if generate_node_id.is_empty():
		return {"error": Strings.text("STATUS_GRAPH_RUN_NEEDS_SELECTION")}
	var reusable_batch_id := _reusable_batch_node_id(graph, generate_node_id, selected_node_id)
	if not reusable_batch_id.is_empty():
		return {
			"batch_node_id": reusable_batch_id,
			"batch_card_id": _ensure_batch_card(graph, reusable_batch_id),
		}
	var batch_node_id := "batch_%s" % IdUtil.uuid_v4().left(8)
	var position := _new_result_position(graph, generate_node_id)
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			batch_node_id,
			{
				"label": Strings.text("BATCH_DEFAULT_LABEL"),
				"source_node_id": generate_node_id,
				"source_run_id": "",
				"role": "standalone",
				"input_snapshots": {},
				"request_records": [],
				"result_slots": [],
			},
			position
		)
	)
	var edge_result := graph.add_edge(generate_node_id, "assets", batch_node_id, "in")
	if not bool(edge_result.get("ok", false)):
		graph.remove_node(batch_node_id)
		return {"error": String(edge_result.get("reason", ""))}
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	var card: Node = _canvas._add_batch_card(
		[],
		position,
		Strings.text("BATCH_DEFAULT_LABEL"),
		IdUtil.uuid_v4(),
		false,
		graph.id,
		batch_node_id
	)
	return {
		"batch_node_id": batch_node_id,
		"batch_card_id": card.item_id if card != null else "",
	}


func _reusable_batch_node_id(
	graph: PFGraph, generate_node_id: String, selected_node_id: String
) -> String:
	var selected: PFNode = graph.get_node(selected_node_id)
	if selected != null and selected.get_type() == "batch":
		var selected_params := graph.get_node_params(selected_node_id)
		if Array(selected_params.get("result_slots", [])).is_empty():
			return selected_node_id
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if String(from_data[0]) != generate_node_id:
			continue
		var target_id := String(to_data[0])
		var target: PFNode = graph.get_node(target_id)
		if target != null and target.get_type() == "batch":
			if Array(graph.get_node_params(target_id).get("result_slots", [])).is_empty():
				return target_id
	return ""


func _ensure_batch_card(graph: PFGraph, batch_node_id: String) -> String:
	var card_id := _graph_batch_card_id(graph.id, batch_node_id)
	if not card_id.is_empty():
		return card_id
	var card: Node = _canvas._add_batch_card(
		[],
		_graph_node_position(graph, batch_node_id),
		String(graph.get_node_params(batch_node_id).get("label", "Batch")),
		IdUtil.uuid_v4(),
		false,
		graph.id,
		batch_node_id
	)
	return card.item_id if card != null else ""


func _new_result_position(graph: PFGraph, generate_node_id: String) -> Vector2:
	var branch_index := 0
	for edge in graph.edges:
		if String(edge.get("from", ["", ""])[0]) == generate_node_id:
			var target: PFNode = graph.get_node(String(edge.get("to", ["", ""])[0]))
			if target != null and target.get_type() == "batch":
				branch_index += 1
	return _graph_node_position(graph, generate_node_id) + Vector2(360, branch_index * 250)


func _graph_node_position(graph: PFGraph, target_node_id: String) -> Vector2:
	for raw_node in graph.to_json().get("nodes", []):
		if raw_node is Dictionary and String(raw_node.get("id", "")) == target_node_id:
			var raw_position: Array = raw_node.get("position", [0, 0])
			return Vector2(float(raw_position[0]), float(raw_position[1]))
	return Vector2.ZERO


func _expected_batch_count(graph: PFGraph, generate_node_id: String) -> int:
	return maxi(1, int(graph.get_node_params(generate_node_id).get("batch_size", 1)))


func _set_batch_run_state(
	graph: PFGraph, batch_node_id: String, _status: String, _expected_count: int, _detail: String
) -> void:
	_canvas._refresh_graph_batch_card(graph.id, batch_node_id)


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
	if node == null or node.is_ghost() or node.get_param_schema().is_empty():
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
	type_name: String, requested_world_position: Variant = null, initial_params: Dictionary = {}
) -> String:
	var binding := _selected_graph_binding()
	var before_graphs: Dictionary = ProjectService.get_graphs_data()
	var graph_id := _resolve_target_graph_id(binding, before_graphs)
	var registry := NodeRegistryScript.new()
	var node: PFNode = registry.create(type_name)
	if node == null:
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return ""
	var graph_data: Dictionary = before_graphs.get(graph_id, {})
	var graph: PFGraph
	if graph_data.is_empty():
		graph = GraphScript.new()
		graph.id = graph_id
		graph.name = "Main Graph"
	else:
		graph = GraphScript.from_json(graph_data)
	var world_position := _graph_node_add_position(binding)
	if requested_world_position is Vector2:
		var requested_position: Vector2 = requested_world_position
		world_position = requested_position.round()
	var node_id := "%s_%s" % [type_name, IdUtil.uuid_v4().left(8)]
	var item_id := IdUtil.uuid_v4()
	var resolved_params := initial_params.duplicate(true)
	if type_name == "ai_generate" and initial_params.is_empty():
		var preferred_provider := String(
			SettingsService.get_setting("provider", "default_id", "openai_image")
		)
		resolved_params = GenerationModelPolicyScript.default_params(
			ProviderService.get_model_descriptors(), preferred_provider
		)
	if graph.add_node(node, node_id, resolved_params, world_position).is_empty():
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return ""

	var after_graphs := before_graphs.duplicate(true)
	after_graphs[graph_id] = graph.to_json()
	var is_batch := node.get_type() == "batch"
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		if is_batch:
			_canvas._add_batch_card(
				[],
				world_position,
				Strings.text("BATCH_DEFAULT_LABEL"),
				item_id,
				false,
				graph_id,
				node_id
			)
		else:
			_canvas._add_graph_node_card(graph_id, node_id, world_position, item_id, false)
		_canvas.select_ids([item_id])
	var undo_add := func() -> void:
		_canvas._remove_item_direct(item_id)
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Add graph node", do_add, undo_add)
	_active_graph_id = graph_id
	_status_label.text = (
		Strings.text("STATUS_GRAPH_ADD_DONE_FORMAT", Strings.STATUS_GRAPH_ADD_DONE)
		% _localized_node_display_name(node)
	)
	return node_id


func _add_reference_assets_to_graph(asset_ids: Array, world_positions: Array) -> Dictionary:
	if asset_ids.is_empty() or asset_ids.size() != world_positions.size():
		return {"ok": false, "node_ids": [], "item_ids": []}
	var binding := _selected_graph_binding()
	var before_graphs: Dictionary = ProjectService.get_graphs_data()
	var graph_id := _resolve_target_graph_id(binding, before_graphs)
	var graph_data: Dictionary = before_graphs.get(graph_id, {})
	var graph: PFGraph
	if graph_data.is_empty():
		graph = GraphScript.new()
		graph.id = graph_id
		graph.name = "Main Graph"
	else:
		graph = GraphScript.from_json(graph_data)
	var registry := NodeRegistryScript.new()
	var node_ids: Array[String] = []
	var item_ids: Array[String] = []
	for index in range(asset_ids.size()):
		var node: PFNode = registry.create("image_input")
		var node_id := "image_input_%s" % IdUtil.uuid_v4().left(8)
		var item_id := IdUtil.uuid_v4()
		var position: Vector2 = world_positions[index]
		if (
			graph
			. add_node(node, node_id, {"asset_id": String(asset_ids[index])}, position)
			. is_empty()
		):
			return {"ok": false, "node_ids": [], "item_ids": []}
		node_ids.append(node_id)
		item_ids.append(item_id)
	var after_graphs := before_graphs.duplicate(true)
	after_graphs[graph_id] = graph.to_json()
	var do_add := func() -> void:
		ProjectService.set_graphs_data(after_graphs, true)
		for index in range(node_ids.size()):
			_canvas._add_graph_node_card(
				graph_id, node_ids[index], world_positions[index], item_ids[index], false
			)
		_canvas.select_ids(item_ids)
	var undo_add := func() -> void:
		for item_id in item_ids:
			_canvas._remove_item_direct(item_id)
		ProjectService.set_graphs_data(before_graphs, true)
		_canvas.select_ids([])
		_canvas._emit_canvas_changed()
	UndoService.perform_action("Import reference images", do_add, undo_add)
	_active_graph_id = graph_id
	return {"ok": true, "graph_id": graph_id, "node_ids": node_ids, "item_ids": item_ids}


func show_graph_quick_add_menu(screen_position: Vector2i) -> bool:
	if _graph_quick_add_menu == null:
		_status_label.text = Strings.STATUS_GRAPH_ADD_FAILED
		return false
	var local_screen_position := Vector2(screen_position) - _canvas.get_screen_position()
	_graph_quick_add_world_position = _canvas.screen_to_world(local_screen_position).round()
	_graph_quick_add_menu.position = screen_position
	_graph_quick_add_menu.popup()
	return true


func show_onboarding_if_needed(blocking_dialog: Window = null) -> void:
	call_deferred("_refresh_import_hint")
	if (
		DisplayServer.get_name() != "headless"
		and not bool(SettingsService.get_setting("onboarding", "v1_complete", false))
	):
		call_deferred("_show_onboarding_after_blocker", blocking_dialog)


func _show_onboarding_after_blocker(blocking_dialog: Window) -> void:
	if blocking_dialog != null and blocking_dialog.visible:
		await blocking_dialog.visibility_changed
		# Window exclusivity is released on the following frame after visibility changes.
		await get_tree().process_frame
	_v1_onboarding.show_setup()


func _refresh_import_hint() -> void:
	_import_flow.refresh_empty_hint()


func _on_v1_setup_completed(open_provider_settings: bool, create_sample: bool) -> void:
	if create_sample:
		generate_mock_batch()
	if open_provider_settings:
		_provider_settings_dialog.show_settings()


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
	_graph_node_params_dialog.asset_import_requested.connect(
		func(graph_id: String, node_id: String, _param_key: String) -> void:
			_import_reference_for_node(graph_id, node_id)
	)
	add_child(_graph_node_params_dialog)


func _on_reference_asset_imported(target: Dictionary, asset_id: String) -> void:
	var mode := String(target.get("mode", ""))
	if mode not in ["node", "reference_set"]:
		return
	var params := {"asset_id": asset_id}
	if mode == "reference_set":
		var graph := GraphScript.from_json(
			ProjectService.get_graph_data(String(target.get("graph_id", "")))
		)
		var asset_ids: Array = (
			graph
			. get_node_params(String(target.get("node_id", "")))
			. get("asset_ids", [])
			. duplicate()
		)
		asset_ids.append(asset_id)
		params = {"asset_ids": asset_ids}
	apply_graph_node_params(
		String(target.get("graph_id", "")), String(target.get("node_id", "")), params
	)


func _add_graph_node_submenu(parent_menu: PopupMenu) -> void:
	_graph_add_parent_menu = parent_menu
	_graph_add_menu = PopupMenu.new()
	_graph_add_menu.name = "GraphNodeAddMenu"
	_graph_quick_add_menu = PopupMenu.new()
	_graph_quick_add_menu.name = "GraphNodeQuickAddMenu"
	_graph_add_types.clear()
	var registry := NodeRegistryScript.new()
	var menu_id := GRAPH_ADD_MENU_ID_START
	for type_name in registry.get_registered_types():
		if String(type_name).begins_with("comfyui."):
			continue
		var node: PFNode = registry.create(String(type_name))
		if node == null:
			continue
		var display_name := _localized_node_display_name(node)
		_graph_add_menu.add_item(display_name, menu_id)
		_graph_quick_add_menu.add_item(display_name, menu_id)
		_graph_add_types[menu_id] = node.get_type()
		menu_id += 1
	_graph_add_menu.id_pressed.connect(_on_graph_add_menu_pressed)
	_graph_quick_add_menu.id_pressed.connect(_on_graph_quick_add_menu_pressed)
	add_child(_graph_quick_add_menu)
	parent_menu.add_child(_graph_add_menu)
	_graph_add_parent_index = parent_menu.item_count
	parent_menu.add_submenu_item(
		Strings.text("MENU_ADD_GRAPH_NODE", Strings.MENU_ADD_GRAPH_NODE), _graph_add_menu.name
	)


func _localized_node_display_name(node: PFNode) -> String:
	var key_by_type := {
		"text_prompt": "NODE_TEXT_PROMPT",
		"object_list": "NODE_OBJECT_LIST",
		"prompt_preset": "NODE_PROMPT_PRESET",
		"image_input": "NODE_IMAGE_INPUT",
		"pixel_cleanup": "NODE_PIXEL_CLEANUP",
		"ai_generate": "NODE_AI_GENERATE",
		"batch": "NODE_BATCH",
	}
	var key := String(key_by_type.get(node.get_type(), ""))
	return (
		Strings.text(key, node.get_display_name())
		if not key.is_empty()
		else node.get_display_name()
	)


func _on_language_changed(_preference: String, _locale: String) -> void:
	if _graph_add_menu == null or _graph_quick_add_menu == null:
		return
	if _graph_add_parent_menu != null and _graph_add_parent_index >= 0:
		_graph_add_parent_menu.set_item_text(
			_graph_add_parent_index,
			Strings.text("MENU_ADD_GRAPH_NODE", Strings.MENU_ADD_GRAPH_NODE)
		)
	var registry := NodeRegistryScript.new()
	for menu in [_graph_add_menu, _graph_quick_add_menu]:
		for index in range(menu.item_count):
			var menu_id: int = menu.get_item_id(index)
			var type_name := String(_graph_add_types.get(menu_id, ""))
			var node: PFNode = registry.create(type_name)
			if node != null:
				menu.set_item_text(index, _localized_node_display_name(node))


func _create_batch_menu() -> void:
	_batch_menu = PopupMenu.new()
	MenuBuilder.populate_batch(_batch_menu, self)
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
		FILE_MENU_PROVIDER_SETTINGS:
			_provider_settings_dialog.show_settings()
		FILE_MENU_CONFIGURE_OPENAI_SESSION:
			configure_openai_session()
		FILE_MENU_GENERATE_OPENAI_BATCH:
			generate_openai_batch()
		FILE_MENU_RUN_SELECTED_GRAPH:
			run_selected_mock_graph()
		FILE_MENU_EDIT_SELECTED_GRAPH_NODE:
			edit_selected_graph_node()
		FILE_MENU_OPEN_BOARD:
			_board_editor.show_editor()
		FILE_MENU_OPEN_PIXEL_EDITOR:
			_open_selected_in_pixel_editor()
		FILE_MENU_PLUGIN_MANAGER:
			_plugin_manager.show_manager()
		FILE_MENU_COMFY_TEMPLATES:
			_comfy_templates.show_manager()
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
		BATCH_MENU_EDIT:
			if not asset_ids.is_empty():
				_open_pixel_editor(String(asset_ids[0]), _batch_menu_card_id)
		BATCH_MENU_CLEANUP:
			_m2_actions.batch_cleanup(
				_batch_menu_card_id,
				asset_ids,
				Pipeline.normalize_params(_cleanup_inspector.get_params())
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
				CanvasBatchCardScript.REVIEW_KEEP, Strings.text("STATUS_BATCH_MARK_KEEP")
			)
		BATCH_MENU_MARK_REJECT:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_REJECT, Strings.text("STATUS_BATCH_MARK_REJECT")
			)
		BATCH_MENU_MARK_FLAG:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_FLAG, Strings.text("STATUS_BATCH_MARK_FLAG")
			)
		BATCH_MENU_CLEAR_MARK:
			_mark_batch_review_state(
				CanvasBatchCardScript.REVIEW_NONE, Strings.text("STATUS_BATCH_MARK_CLEAR")
			)
		BATCH_MENU_FILTER_ALL:
			_set_batch_review_filter(
				CanvasBatchCardScript.FILTER_ALL, Strings.text("STATUS_BATCH_SHOW_ALL")
			)
		BATCH_MENU_FILTER_KEEP:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_KEEP, Strings.text("STATUS_BATCH_SHOW_KEEP")
			)
		BATCH_MENU_FILTER_PENDING:
			_set_batch_review_filter(
				CanvasBatchCardScript.FILTER_PENDING, Strings.text("STATUS_BATCH_SHOW_PENDING")
			)
		BATCH_MENU_FILTER_REJECT:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_REJECT, Strings.text("STATUS_BATCH_SHOW_REJECT")
			)
		BATCH_MENU_FILTER_FLAG:
			_set_batch_review_filter(
				CanvasBatchCardScript.REVIEW_FLAG, Strings.text("STATUS_BATCH_SHOW_FLAG")
			)
		BATCH_MENU_LAYOUT_CONTACT:
			_set_batch_review_layout(
				CanvasBatchCardScript.LAYOUT_CONTACT, Strings.text("STATUS_BATCH_LAYOUT_CONTACT")
			)
		BATCH_MENU_LAYOUT_FOCUS:
			_set_batch_review_layout(
				CanvasBatchCardScript.LAYOUT_FOCUS, Strings.text("STATUS_BATCH_LAYOUT_FOCUS")
			)
		BATCH_MENU_COMPARE_CURRENT:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_CURRENT, Strings.text("STATUS_BATCH_COMPARE_CURRENT")
			)
		BATCH_MENU_COMPARE_PREVIOUS:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_PREVIOUS,
				Strings.text("STATUS_BATCH_COMPARE_PREVIOUS")
			)
		BATCH_MENU_COMPARE_SPLIT:
			_set_batch_compare_mode(
				CanvasBatchCardScript.COMPARE_SPLIT, Strings.text("STATUS_BATCH_COMPARE_SPLIT")
			)
		BATCH_MENU_SPLIT_KEEP:
			var new_keep_card: Variant = _canvas._split_batch_marked(
				_batch_menu_card_id,
				CanvasBatchCardScript.REVIEW_KEEP,
				Strings.BATCH_KEEP_LABEL_SUFFIX
			)
			_status_label.text = (
				Strings.text("STATUS_BATCH_SPLIT_KEEP")
				if new_keep_card != null
				else Strings.text("STATUS_BATCH_SPLIT_KEEP_EMPTY")
			)
		BATCH_MENU_SPLIT:
			var new_card: Variant = _canvas._split_batch_selection(_batch_menu_card_id)
			_status_label.text = (
				Strings.text("STATUS_BATCH_SPLIT")
				if new_card != null
				else Strings.text("STATUS_BATCH_SPLIT_EMPTY")
			)
		BATCH_MENU_EXPORT:
			_emit_batch_export(asset_ids)


func _open_selected_in_pixel_editor() -> void:
	_pixel_editor_flow.open_selected()


func _open_pixel_editor(asset_id: String, batch_id: String) -> void:
	_pixel_editor_flow.open_asset(asset_id, batch_id)


func _mark_batch_review_state(review_state: String, status_format: String) -> void:
	_mark_batch_review_state_for_card(_batch_menu_card_id, review_state, status_format)


func _mark_batch_review_state_for_card(
	card_id: String, review_state: String, status_format: String
) -> bool:
	var selected_ids: Array = _canvas._get_batch_selected_asset_ids(card_id)
	if selected_ids.is_empty():
		_status_label.text = Strings.text("STATUS_BATCH_MARK_NEEDS_SELECTION")
		return false
	var marked_count: int = _canvas._set_batch_review_state(
		card_id, selected_ids, review_state, true
	)
	if marked_count <= 0:
		_status_label.text = Strings.text("STATUS_BATCH_MARK_NEEDS_SELECTION")
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
			status_format = Strings.text("STATUS_BATCH_MARK_KEEP")
		KEY_R:
			review_state = CanvasBatchCardScript.REVIEW_REJECT
			status_format = Strings.text("STATUS_BATCH_MARK_REJECT")
		KEY_F:
			review_state = CanvasBatchCardScript.REVIEW_FLAG
			status_format = Strings.text("STATUS_BATCH_MARK_FLAG")
		KEY_C:
			review_state = CanvasBatchCardScript.REVIEW_NONE
			status_format = Strings.text("STATUS_BATCH_MARK_CLEAR")
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
		_status_label.text = Strings.text("STATUS_BATCH_FOCUS_EMPTY")
		return true
	_status_label.text = (
		Strings.text("STATUS_BATCH_FOCUS_FORMAT") % [focus_result["index"], focus_result["total"]]
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
		_status_label.text = Strings.text("STATUS_BATCH_FILTER_FAILED")
		return
	_status_label.text = status_text


func _set_batch_review_layout(review_layout: String, status_text: String) -> void:
	if not _canvas._set_batch_review_layout(_batch_menu_card_id, review_layout, true):
		_status_label.text = Strings.text("STATUS_BATCH_LAYOUT_FAILED")
		return
	_status_label.text = status_text


func _set_batch_compare_mode(compare_mode: String, status_text: String) -> void:
	if not _canvas._set_batch_compare_mode(_batch_menu_card_id, compare_mode, true):
		_status_label.text = Strings.text("STATUS_BATCH_COMPARE_EMPTY")
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
		_status_label.text = Strings.text("STATUS_EXPORT_EMPTY")
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
		return Strings.text("STATUS_GRAPH_RUN_FAILED")
	return Strings.text("STATUS_GRAPH_RUN_FAILED_DETAIL_FORMAT") % message


func _graph_error_message(error: Dictionary) -> String:
	match String(error.get("code", "")):
		"missing_asset_reference":
			return Strings.text("ERROR_REFERENCE_REQUIRED")
		"asset_not_found":
			return Strings.text("ERROR_REFERENCE_NOT_FOUND")
		"asset_decode_failed":
			return Strings.text("ERROR_REFERENCE_DECODE_FAILED")
	return String(error.get("message", ""))


func _graph_node_add_position(binding: Dictionary) -> Vector2:
	var item_id := String(binding.get("item_id", ""))
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		if String(item_data.get("id", "")) != item_id:
			continue
		var raw_position: Variant = item_data.get("position", [0, 0])
		return Vector2(float(raw_position[0]), float(raw_position[1])) + Vector2(280, 0)
	return _canvas.screen_to_world(_canvas.size * 0.5)


func _graph_provider_id(graph: PFGraph, generate_node_id: String) -> String:
	var node: PFNode = graph.get_node(generate_node_id)
	if node != null and node.get_type() == "comfyui.run_workflow":
		return "comfyui"
	return String(graph.get_node_params(generate_node_id).get("provider_id", "mock"))


func _route_provider_graph_run(
	graph: PFGraph, generate_node_id: String, batch_node_id: String, batch_card_id: String
) -> bool:
	var provider_id := _graph_provider_id(graph, generate_node_id)
	if provider_id == "mock":
		return false
	if batch_card_id.is_empty():
		_status_label.text = _graph_run_failure_status(
			{"message": Strings.text("STATUS_GRAPH_RUN_MISSING_BATCH_CARD")}
		)
		return true
	var generate_params := graph.get_node_params(generate_node_id)
	var descriptor: Dictionary = ProviderService.get_model_descriptor(
		provider_id, String(generate_params.get("model_id", ""))
	)
	if descriptor.is_empty():
		_status_label.text = _graph_run_failure_status({"message": "Provider is unavailable"})
		return true
	var validation_state := ProviderService.get_validation_state(provider_id)
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var safe_validation := bool(capabilities.get("safe_validation", true))
	if validation_state != "verified" and (safe_validation or validation_state != "configured"):
		_status_label.text = (
			Strings.STATUS_PROVIDER_CREDENTIALS_REQUIRED_FORMAT
			% String(descriptor.get("display_name", provider_id))
		)
		_provider_settings_dialog.show_settings()
		return true
	_openai_flow.run_graph(graph, batch_node_id, batch_card_id, generate_node_id)
	return true


func _target_generate_node_id(graph: PFGraph, selected_node_id: String) -> String:
	var selected: PFNode = graph.get_node(selected_node_id)
	if selected != null and selected.get_type() == "ai_generate":
		return selected_node_id
	if selected != null and selected.get_type() == "batch":
		for edge in graph.edges:
			var from_data: Array = edge.get("from", ["", ""])
			var to_data: Array = edge.get("to", ["", ""])
			var source: PFNode = graph.get_node(String(from_data[0]))
			if (
				String(to_data[0]) == selected_node_id
				and source != null
				and source.get_type() == "ai_generate"
			):
				return String(from_data[0])
	for node_id in graph.nodes.keys():
		var node: PFNode = graph.get_node(String(node_id))
		if node != null and node.get_type() == "ai_generate":
			return String(node_id)
	return ""


func _target_batch_node_id(
	graph: PFGraph, generate_node_id: String, selected_node_id: String
) -> String:
	var selected: PFNode = graph.get_node(selected_node_id)
	if selected != null and selected.get_type() == "batch":
		return selected_node_id
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		var target: PFNode = graph.get_node(String(to_data[0]))
		if (
			String(from_data[0]) == generate_node_id
			and target != null
			and target.get_type() == "batch"
		):
			return String(to_data[0])
	return ""


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
				"message":
				Strings.text("STATUS_GRAPH_RUN_MISSING_NODE_TYPE_FORMAT") % node.get_type(),
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


func _resolve_target_graph_id(binding: Dictionary, graphs: Dictionary) -> String:
	var selected_graph_id := String(binding.get("graph_id", ""))
	if not selected_graph_id.is_empty() and graphs.has(selected_graph_id):
		_active_graph_id = selected_graph_id
		return selected_graph_id
	if not _active_graph_id.is_empty() and graphs.has(_active_graph_id):
		return _active_graph_id
	var graph_ids: Array = graphs.keys()
	graph_ids.sort()
	if not graph_ids.is_empty():
		_active_graph_id = String(graph_ids[0])
		return _active_graph_id
	_active_graph_id = "graph_main"
	return _active_graph_id


func _graph_batch_card_id(graph_id: String, batch_node_id: String) -> String:
	for item in _canvas.export_canvas_data()["items"]:
		var item_data: Dictionary = item
		if (
			String(item_data.get("graph_id", "")) == graph_id
			and String(item_data.get("node_id", "")) == batch_node_id
		):
			return String(item_data.get("id", ""))
	return ""
