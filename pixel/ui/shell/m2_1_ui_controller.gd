class_name PFM21UiController
extends Node

## M2.1 UI 接线控制器。
## 主窗口保留布局和项目命令；本控制器承接导入、工具、M2 参数对话框与批次菜单。

signal export_snapshots_requested(snapshots: Array, default_file: String)

const Strings := preload("res://ui/shell/strings.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const ToolManagerScript := preload("res://ui/tools/tool_manager.gd")
const MagicWandToolScript := preload("res://ui/tools/magic_wand_tool.gd")
const RectangleToolScript := preload("res://ui/tools/rectangle_tool.gd")
const LassoToolScript := preload("res://ui/tools/lasso_tool.gd")
const MatteDialogScript := preload("res://ui/dialogs/matte_dialog.gd")
const SliceDialogScript := preload("res://ui/dialogs/slice_dialog.gd")
const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
const OnboardingScript := preload("res://ui/dialogs/onboarding.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Log := preload("res://core/util/log_util.gd")

const TOOLBAR_BUTTON_HEIGHT := 34
const TOOLBAR_FONT_SIZE := 14
const FILE_MENU_BUTTON_WIDTH := 84
const TOOL_BUTTON_SIZE := 84
const FILE_MENU_IMPORT_IMAGES := 0
const FILE_MENU_GENERATE_MOCK_BATCH := 1
const FILE_MENU_NEW := 2
const FILE_MENU_OPEN := 3
const FILE_MENU_SAVE := 4
const BATCH_MENU_CLEANUP := 0
const BATCH_MENU_MATTE := 1
const BATCH_MENU_OUTLINE := 2
const BATCH_MENU_SPLIT := 3
const BATCH_MENU_EXPORT := 4
const SELECTION_TOOLS_VISIBLE := false

var _canvas: Control = null
var _cleanup_inspector: Control = null
var _status_label: Label = null
var _m2_actions: Variant = null
var _new_project_callback: Callable
var _open_project_callback: Callable
var _save_project_callback: Callable
var _tool_manager: Variant = null
var _tool_buttons := {}
var _import_dialog: FileDialog = null
var _matte_dialog: ConfirmationDialog = null
var _slice_dialog: ConfirmationDialog = null
var _outline_dialog: ConfirmationDialog = null
var _batch_menu: PopupMenu = null
var _batch_menu_card_id := ""


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
	_create_import_dialog()
	_create_m2_dialogs()
	_create_batch_menu()
	_init_tools()
	_canvas.batch_context_requested.connect(_show_batch_menu)


func add_file_menu(parent: Control) -> void:
	var file_menu_button := MenuButton.new()
	file_menu_button.text = Strings.MENU_FILE
	file_menu_button.custom_minimum_size = Vector2(FILE_MENU_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	file_menu_button.focus_mode = Control.FOCUS_NONE
	file_menu_button.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
	var popup := file_menu_button.get_popup()
	popup.add_item(Strings.MENU_IMPORT_IMAGES, FILE_MENU_IMPORT_IMAGES)
	popup.add_item(Strings.MENU_GENERATE_MOCK_BATCH, FILE_MENU_GENERATE_MOCK_BATCH)
	popup.add_separator()
	popup.add_item(Strings.ACTION_NEW, FILE_MENU_NEW)
	popup.add_item(Strings.ACTION_OPEN, FILE_MENU_OPEN)
	popup.add_item(Strings.ACTION_SAVE, FILE_MENU_SAVE)
	popup.id_pressed.connect(_on_file_menu_pressed)
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
	if not SELECTION_TOOLS_VISIBLE:
		return false
	return _tool_manager.handle_shortcut(event.keycode)


func import_files_at_mouse(files: PackedStringArray) -> void:
	_import_image_files(files, _canvas.get_mouse_world_position())


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
	var items := _add_mock_graph_canvas_items(graph, asset_ids, _canvas.get_mouse_world_position())
	if not items.is_empty():
		_focus_canvas_on_bounds(_bounds_for_items(items))
	_status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()


func show_onboarding_if_needed() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if bool(SettingsService.get_setting("ui", "m2_1_onboarding_seen", false)):
		return
	call_deferred("_show_onboarding_dialog")


func _create_import_dialog() -> void:
	_import_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_import_dialog)
	_import_dialog.title = Strings.DIALOG_IMPORT_IMAGES
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.filters = PackedStringArray(["*.png ; PNG Image", "*.jpg,*.jpeg ; JPEG Image"])
	_import_dialog.files_selected.connect(_on_import_files_selected)
	add_child(_import_dialog)


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


func _create_batch_menu() -> void:
	_batch_menu = PopupMenu.new()
	_batch_menu.add_item(Strings.BATCH_ACTION_CLEANUP, BATCH_MENU_CLEANUP)
	_batch_menu.add_item(Strings.BATCH_ACTION_MATTE, BATCH_MENU_MATTE)
	_batch_menu.add_item(Strings.BATCH_ACTION_OUTLINE, BATCH_MENU_OUTLINE)
	_batch_menu.add_separator()
	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
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
			_import_dialog.popup_centered_ratio(0.7)
		FILE_MENU_GENERATE_MOCK_BATCH:
			generate_mock_batch()
		FILE_MENU_NEW:
			_new_project_callback.call()
		FILE_MENU_OPEN:
			_open_project_callback.call()
		FILE_MENU_SAVE:
			_save_project_callback.call()


func _on_import_files_selected(files: PackedStringArray) -> void:
	_import_image_files(files, _canvas.get_mouse_world_position())


func _import_image_files(files: PackedStringArray, world_position: Vector2) -> void:
	var supported_files := []
	for file_path in files:
		if _is_supported_image_path(file_path):
			supported_files.append(String(file_path))

	var drop_position := world_position
	var imported_asset_ids: Array[String] = []
	var make_batch := supported_files.size() > 1
	for file_path in supported_files:
		var image: Image = FileIOScript.load_png(file_path)
		if image == null:
			Log.warn("Imported image could not be loaded", {"path": file_path})
			continue
		if image.get_width() * image.get_height() > 1024 * 1024:
			Log.warn(
				"Large image imported without M1 cleanup",
				{"path": file_path, "size": [image.get_width(), image.get_height()]}
			)

		var asset_name := String(file_path).get_file().get_basename()
		var asset_id := AssetLibrary.register_image(image, asset_name, {"origin": "imported"})
		imported_asset_ids.append(asset_id)
		if not make_batch:
			_canvas.add_sprite_item(image, asset_id, drop_position)
		drop_position += Vector2(image.get_width() + 8, 0)

	if imported_asset_ids.size() > 1:
		var card: Node = _canvas._add_batch_card(
			imported_asset_ids, world_position, Strings.BATCH_DEFAULT_LABEL
		)
		if card != null:
			_focus_canvas_on_card(card)


func _is_supported_image_path(file_path: String) -> bool:
	var lower_path := file_path.to_lower()
	return (
		lower_path.ends_with(".png")
		or lower_path.ends_with(".jpg")
		or lower_path.ends_with(".jpeg")
	)


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
		BATCH_MENU_SPLIT:
			var new_card: Variant = _canvas._split_batch_selection(_batch_menu_card_id)
			_status_label.text = (
				Strings.STATUS_BATCH_SPLIT if new_card != null else Strings.STATUS_BATCH_SPLIT_EMPTY
			)
		BATCH_MENU_EXPORT:
			_emit_batch_export(asset_ids)


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


func _add_mock_graph_canvas_items(graph: PFGraph, asset_ids: Array, anchor: Vector2) -> Array:
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
		Strings.MOCK_BATCH_LABEL,
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


func _show_onboarding_dialog() -> void:
	var dialog: AcceptDialog = OnboardingScript.show_first_run_tips(self)
	if dialog == null:
		return
	var mark_seen := func() -> void: SettingsService.set_setting("ui", "m2_1_onboarding_seen", true)
	dialog.confirmed.connect(mark_seen, CONNECT_ONE_SHOT)
	dialog.close_requested.connect(mark_seen, CONNECT_ONE_SHOT)
