# gdlint: disable=max-file-lines,max-returns
class_name PFCanvasNodeCard
extends Node2D

## M3 画布轻节点卡。
## contract: 02-contracts/PROJECT-FORMAT.md §4；只保存 graph/node 引用，节点逻辑从 graphs 读取。

signal params_commit_requested(graph_id: String, node_id: String, params: Dictionary)
signal action_requested(graph_id: String, node_id: String, action_id: String)
signal collapsed_change_requested(item_id: String, collapsed: bool)
signal display_title_change_requested(item_id: String, display_title: String)
signal size_change_requested(item_id: String, requested_size: Vector2i)
signal reference_reorder_requested(graph_id: String, node_id: String, asset_ids: Array)

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")
const AssetRefFieldScript := preload("res://ui/widgets/asset_ref_field.gd")
const ObjectListEditorScript := preload("res://ui/canvas/object_list_editor.gd")
const PromptPresetCardViewScript := preload("res://ui/canvas/prompt_preset_card_view.gd")
const GenerationCardViewScript := preload("res://ui/canvas/generation_card_view.gd")
const CleanupCardViewScript := preload("res://ui/canvas/cleanup_card_view.gd")
const MediaTileGridScript := preload("res://ui/canvas/media_tile_grid.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")

const REFERENCE_SET_PREVIEW_SIZE := Vector2(52, 52)
const HEADER_HEIGHT := CardContract.HEADER_HEIGHT
const PADDING := CardContract.PADDING
const BACKGROUND := AppTheme.CARD
const HEADER := AppTheme.ELEVATED
const BORDER := AppTheme.BORDER
const GHOST_BORDER := AppTheme.ERROR
const EDGE_ERROR_BORDER := AppTheme.ERROR
const BADGE_BACKGROUND := AppTheme.SECTION
const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
const PORT_VISIBLE_SCREEN_RADIUS := 6.0
const PORT_HIT_SCREEN_RADIUS := 20.0
const OBJECT_EDITOR_MIN_SIZE := Vector2(0, 116)
const FLEXIBLE_WIDTH := 0

var item_id := ""
var graph_id := ""
var node_id := ""
var locked := false
var collapsed := false
var frame_id: Variant = null
var display_title := ""
var requested_size := Vector2i.ZERO

var _node_type := ""
var _display_name := "Missing Node"
var _summary := ""
var _input_count := 0
var _output_count := 0
var _input_ports: Array[String] = []
var _output_ports: Array[String] = []
var _visible_input_ports: Array[String] = []
var _visible_output_ports: Array[String] = []
var _is_ghost := false
var _has_edge_error := false
var _status_badge := ""
var _execution_status_key := ""
var _font: Font = null
var _content_root: Control = null
var _text_prompt_edit: TextEdit = null
var _prompt_count_label: Label = null
var _prompt_draft_label: Label = null
var _prompt_preset_view: Control = null
var _generation_view: Control = null
var _cleanup_view: Control = null
var _reference_field: Control = null
var _collapse_button: Button = null
var _title_button: Button = null
var _title_edit: LineEdit = null
var _more_button: MenuButton = null
var _params_snapshot := {}
var _raw_data := {}
var _lod_camera_zoom := 1.0
var _prompt_draft_cache := ""
var _prompt_draft_cached := false
var _suppress_prompt_draft_tracking := false


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	locked = bool(data.get("locked", false))
	collapsed = bool(data.get("collapsed", false))
	frame_id = data.get("frame_id", null)
	display_title = CardContract.normalize_display_title(data.get("display_title", ""))
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	if not SettingsService.developer_mode_changed.is_connected(_on_developer_mode_changed):
		SettingsService.developer_mode_changed.connect(_on_developer_mode_changed)
	_prompt_draft_cache = ""
	_prompt_draft_cached = false
	_resolve_graph_node()
	requested_size = CardContract.normalize_requested_size(_node_type, data.get("size", null))
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func to_canvas_data() -> Dictionary:
	var result := _raw_data.duplicate(true)
	result["id"] = item_id
	result["type"] = "node"
	result["graph_id"] = graph_id
	result["node_id"] = node_id
	result["position"] = [int(round(position.x)), int(round(position.y))]
	result["z_index"] = z_index
	result["collapsed"] = collapsed
	result["locked"] = locked
	result["frame_id"] = frame_id
	result["size"] = CardContract.size_array(requested_size)
	if display_title.is_empty():
		result.erase("display_title")
	else:
		result["display_title"] = display_title
	return result


func get_canvas_bounds() -> Rect2:
	return Rect2(position, _card_size())


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func is_graph_node() -> bool:
	return not graph_id.is_empty() and not node_id.is_empty()


func refresh_from_graph() -> void:
	var interaction_state := _capture_content_interaction_state()
	_resolve_graph_node()
	_rebuild_content_controls()
	_restore_content_interaction_state(interaction_state)
	_rebuild_header_controls()
	queue_redraw()


func set_collapsed(value: bool) -> void:
	if collapsed == value:
		return
	var interaction_state := _capture_content_interaction_state()
	collapsed = value
	_rebuild_content_controls()
	_restore_content_interaction_state(interaction_state)
	_rebuild_header_controls()
	queue_redraw()


func set_display_title(value: Variant) -> void:
	display_title = CardContract.normalize_display_title(value)
	_resolve_graph_node()
	_rebuild_header_controls()
	queue_redraw()


func set_requested_size(value: Variant) -> void:
	var interaction_state := _capture_content_interaction_state()
	requested_size = CardContract.normalize_requested_size(_node_type, value)
	_rebuild_content_controls()
	_restore_content_interaction_state(interaction_state)
	_rebuild_header_controls()
	queue_redraw()


func get_requested_size() -> Vector2i:
	return requested_size


func set_lod_camera_zoom(value: float) -> void:
	var was_overview := _is_overview()
	_lod_camera_zoom = maxf(0.0, value)
	if was_overview != _is_overview():
		_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func get_content_control(control_name: String) -> Control:
	if _content_root == null:
		return null
	return _content_root.find_child(control_name, true, false) as Control


func set_execution_status(status_key: String, _detail: String = "") -> void:
	_execution_status_key = status_key
	_status_badge = _execution_status_text(status_key) if not status_key.is_empty() else ""
	_sync_run_controls()
	queue_redraw()


func set_generation_run_context(context: Dictionary) -> void:
	if _generation_view != null:
		_generation_view.set_run_context(context)


func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
	var count := _input_count if is_input else _output_count
	if count <= 0:
		return position + Vector2(0.0 if is_input else _card_size().x, _card_size().y * 0.5)
	var index := _port_index(port_name, is_input)
	if index < 0:
		index = 0
	return position + _port_position(index, count, is_input)


func _graph_port_at_world(world_position: Vector2) -> Dictionary:
	if _lod_camera_zoom < 0.75:
		return {}
	var input_hit := _port_hit_at_world(world_position, true)
	if not input_hit.is_empty():
		return input_hit
	return _port_hit_at_world(world_position, false)


func _draw() -> void:
	_font = UIFont.get_font() if _font == null else _font
	var card_size := _card_size()
	var rect := Rect2(Vector2.ZERO, card_size)
	draw_rect(rect, BACKGROUND, true)
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(card_size.x, _header_height())),
		AppTheme.MEDIA_RAIL if _node_type == "image_input" else HEADER,
		true
	)
	draw_rect(rect, _border_color(), false, 1.4)
	_draw_ports()
	if _font == null:
		return
	if _lod_camera_zoom >= 0.25:
		draw_string(
			_font,
			Vector2(PADDING, 22),
			_display_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			card_size.x - PADDING * 2,
			16,
			AppTheme.MEDIA_RAIL_TEXT if _node_type == "image_input" else AppTheme.TEXT_PRIMARY
		)
	_draw_status_badge()
	_draw_resize_handle()
	if collapsed or not _is_content_node() or _is_overview():
		if _lod_camera_zoom < 0.25:
			return
		draw_string(
			_font,
			Vector2(PADDING, 54),
			_node_type,
			HORIZONTAL_ALIGNMENT_LEFT,
			card_size.x - PADDING * 2,
			13,
			Color(0.66, 0.72, 0.74, 1.0)
		)
		if _lod_camera_zoom >= 0.5:
			draw_string(
				_font,
				Vector2(PADDING, 82),
				_summary,
				HORIZONTAL_ALIGNMENT_LEFT,
				card_size.x - PADDING * 2,
				13,
				Color(0.82, 0.84, 0.82, 1.0)
			)


func _draw_ports() -> void:
	if _lod_camera_zoom < 0.75:
		return
	var visible_radius := PORT_VISIBLE_SCREEN_RADIUS / maxf(_lod_camera_zoom, 0.01)
	for index in range(_input_count):
		draw_circle(_port_position(index, _input_count, true), visible_radius, PORT_IN)
	for index in range(_output_count):
		draw_circle(_port_position(index, _output_count, false), visible_radius, PORT_OUT)


func _port_position(index: int, count: int, is_input: bool) -> Vector2:
	var usable_height := _card_size().y - _header_height() - PADDING * 2
	var y := _header_height() + PADDING + usable_height * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else _card_size().x, y)


func _port_index(port_name: String, is_input: bool) -> int:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	return ports.find(port_name)


func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	var count := ports.size()
	var hit_radius := PORT_HIT_SCREEN_RADIUS / maxf(_lod_camera_zoom, 0.01)
	for index in range(count):
		var anchor := position + _port_position(index, count, is_input)
		if anchor.distance_to(world_position) <= hit_radius:
			return {"port_name": ports[index], "is_input": is_input, "port_index": index}
	return {}


func _resolve_graph_node() -> void:
	var node_data := _find_node_data()
	_node_type = String(node_data.get("type", "missing"))
	_params_snapshot = node_data.get("params", {}).duplicate(true)
	_summary = _summarize_params(node_data.get("params", {}))
	_has_edge_error = _graph_has_edge_error()
	_status_badge = ""

	var registry := NodeRegistryScript.new()
	var node: PFNode = registry.create(_node_type)
	if node == null:
		_is_ghost = true
		_display_name = Strings.text("GRAPH_NODE_MISSING_DISPLAY") % _node_type
		_summary = Strings.text("GRAPH_NODE_GHOST_SUMMARY")
		_input_count = 0
		_output_count = 0
		_input_ports = []
		_output_ports = []
		_visible_input_ports = []
		_visible_output_ports = []
		_status_badge = Strings.text("GRAPH_NODE_BADGE_MISSING")
		return

	_display_name = _localized_display_name(node)
	if _node_type == "image_input":
		var asset_id := String(_params_snapshot.get("asset_id", ""))
		var asset_name := String(AssetLibrary.get_asset_meta(asset_id).get("name", ""))
		if not asset_name.is_empty():
			_display_name = asset_name
	if not display_title.is_empty():
		_display_name = display_title
	_input_ports = _port_names(node.get_input_ports())
	_output_ports = _port_names(node.get_output_ports())
	_visible_input_ports = _visible_input_ports_for_node(_node_type, _input_ports)
	_visible_output_ports = _output_ports.duplicate()
	_input_count = _visible_input_ports.size()
	_output_count = _visible_output_ports.size()
	_is_ghost = false
	if _has_edge_error:
		_status_badge = Strings.text("GRAPH_NODE_BADGE_EDGE_ERROR")
	if not _execution_status_key.is_empty():
		_status_badge = _execution_status_text(_execution_status_key)
	elif _node_type == "ai_generate" and not _has_edge_error:
		_status_badge = Strings.text("CONTENT_STATUS_READY")


func _visible_input_ports_for_node(node_type: String, port_names: Array[String]) -> Array[String]:
	# M3 画布 MVP 只折叠视觉入口；graph edge 仍保留原始命名端口。
	if node_type == "ai_generate" and not port_names.is_empty():
		return ["in"]
	return port_names.duplicate()


func _port_names(port_specs: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for port_spec in port_specs:
		result.append(String(port_spec.get("name", "")))
	return result


func _find_node_data() -> Dictionary:
	var graph_data := ProjectService.get_graph_data(graph_id)
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node_data: Dictionary = raw_node
		if String(node_data.get("id", "")) == node_id:
			return node_data
	return {"id": node_id, "type": "missing", "params": {}}


func _graph_has_edge_error() -> bool:
	if graph_id.is_empty() or node_id.is_empty():
		return false
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		return false
	var graph: PFGraph = GraphScript.from_json(graph_data)
	return not graph.validate_edges_for_node(node_id).is_empty()


func _border_color() -> Color:
	if _is_ghost:
		return GHOST_BORDER
	if _has_edge_error:
		return EDGE_ERROR_BORDER
	return BORDER


func _draw_status_badge() -> void:
	if _status_badge.is_empty() or _font == null:
		return
	var badge_size := Vector2(72, 18)
	var disclosure_space := 28.0 if _collapse_button != null else 0.0
	var badge_rect := Rect2(
		Vector2(_card_size().x - PADDING - disclosure_space - badge_size.x, 8), badge_size
	)
	draw_rect(badge_rect, BADGE_BACKGROUND, true)
	draw_rect(badge_rect, _border_color(), false, 1.0)
	draw_string(
		_font,
		badge_rect.position + Vector2(5, 13),
		_status_badge,
		HORIZONTAL_ALIGNMENT_LEFT,
		badge_rect.size.x - 10,
		11,
		_border_color()
	)


func _summarize_params(params: Variant) -> String:
	if not (params is Dictionary):
		return ""
	var source: Dictionary = params
	var result := ""
	if source.has("text"):
		var prompt := String(source["text"]).strip_edges()
		result = Strings.text("CONTENT_PROMPT_EMPTY") if prompt.is_empty() else prompt.left(56)
	elif source.has("rows"):
		var enabled_count := 0
		for row in source.get("rows", []):
			if row is Dictionary and bool(row.get("enabled", true)):
				enabled_count += 1
		result = (
			Strings.text("CONTENT_OBJECT_SELECTED_FORMAT")
			% [enabled_count, source.get("rows", []).size()]
		)
	elif source.has("items"):
		var lines := String(source["items"]).split("\n", false)
		result = Strings.text("CONTENT_OBJECT_COUNT_FORMAT") % lines.size()
	elif source.has("preset"):
		var preset_value: Variant = source.get("preset", {})
		var preset: Dictionary = preset_value if preset_value is Dictionary else {}
		result = String(preset.get("name", preset.get("name_key", preset.get("prefix", ""))))
	elif source.has("provider_id"):
		var model_label := String(source.get("model_id", ""))
		if model_label.is_empty():
			model_label = String(source["provider_id"])
		result = (
			Strings.text("CONTENT_GENERATE_MODEL_SUMMARY_FORMAT")
			% [model_label, int(source.get("batch_size", 1))]
		)
	elif source.has("asset_ids"):
		result = Strings.text("CONTENT_REFERENCE_SET_COUNT_FORMAT") % source["asset_ids"].size()
	return result


func _card_size() -> Vector2:
	var safe_requested := requested_size
	if safe_requested == Vector2i.ZERO:
		safe_requested = CardContract.default_size_for_type(_node_type)
	return Vector2(CardContract.effective_size(_node_type, safe_requested, collapsed))


func _header_height() -> float:
	if _node_type == "image_input":
		return float(CardContract.CONTENT_RAIL_HEIGHT)
	if _node_type == "ai_generate":
		return float(GenerationCardViewScript.HEADER_HEIGHT)
	return float(HEADER_HEIGHT)


func _is_content_node() -> bool:
	return (
		_node_type
		in [
			"text_prompt",
			"object_list",
			"prompt_preset",
			"ai_generate",
			"pixel_cleanup",
			"image_input",
			"reference_set",
		]
	)


func _is_overview() -> bool:
	return _lod_camera_zoom < 0.75


func _rebuild_content_controls() -> void:
	if _content_root != null:
		# Keep emitting descendants tree-owned until frame end and release the Content name.
		_content_root.name = "RetiredContent"
		_content_root.queue_free()
		_content_root = null
	_text_prompt_edit = null
	_prompt_count_label = null
	_prompt_draft_label = null
	_prompt_preset_view = null
	_generation_view = null
	_cleanup_view = null
	_reference_field = null
	if collapsed or _is_overview() or not _is_content_node() or _is_ghost:
		return

	_content_root = VBoxContainer.new()
	_content_root.name = "Content"
	if _node_type in ["ai_generate", "pixel_cleanup"]:
		_content_root.position = Vector2(0, _header_height())
		_content_root.size = _card_size() - Vector2(0, _header_height())
	else:
		_content_root.position = Vector2(PADDING, _header_height() + PADDING)
		_content_root.size = _card_size() - Vector2(PADDING * 2, _header_height() + PADDING * 2)
	_content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_root.add_theme_constant_override("separation", 8)
	add_child(_content_root)
	match _node_type:
		"text_prompt":
			_build_text_prompt_controls()
		"object_list":
			_build_object_list_controls()
		"ai_generate":
			_build_generate_controls()
		"image_input":
			_build_reference_controls()
		"reference_set":
			_build_reference_set_controls()
		"prompt_preset":
			_build_prompt_preset_controls()
		"pixel_cleanup":
			_build_cleanup_shell_controls()
	_configure_internal_scroll_ownership()
	call_deferred("_configure_internal_scroll_ownership")


func _rebuild_header_controls() -> void:
	if not _is_content_node() or _is_ghost or _is_overview():
		for control in [_collapse_button, _title_button, _more_button, _title_edit]:
			if control != null:
				control.visible = false
		return
	if _collapse_button == null:
		_collapse_button = Button.new()
		_collapse_button.name = "CollapseButton"
		_collapse_button.focus_mode = Control.FOCUS_NONE
		_collapse_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_collapse_button.pressed.connect(
			func() -> void: collapsed_change_requested.emit(item_id, not collapsed)
		)
		add_child(_collapse_button)
	_collapse_button.visible = true
	_collapse_button.text = "+" if collapsed else "−"
	_collapse_button.tooltip_text = Strings.text(
		"ACTION_EXPAND_MODULE" if collapsed else "ACTION_COLLAPSE_MODULE"
	)
	_collapse_button.position = Vector2(_card_size().x - 68, 10)
	_collapse_button.size = Vector2(24, 24)
	if _title_button == null:
		_title_button = Button.new()
		_title_button.name = "TitleButton"
		_title_button.flat = true
		_title_button.focus_mode = Control.FOCUS_NONE
		_title_button.mouse_filter = Control.MOUSE_FILTER_PASS
		_title_button.gui_input.connect(_on_title_button_input)
		add_child(_title_button)
	_title_button.position = Vector2(8, 4)
	_title_button.size = Vector2(maxf(32.0, _card_size().x - 84.0), 36)
	_title_button.tooltip_text = _display_name
	_title_button.visible = not locked
	if _more_button == null:
		_more_button = MenuButton.new()
		_more_button.name = "MoreButton"
		_more_button.text = "..."
		_more_button.tooltip_text = Strings.text("ACTION_MORE")
		_more_button.get_popup().add_item(Strings.text("ACTION_RENAME"), 1)
		_more_button.get_popup().add_item(Strings.text("ACTION_RESET_CARD_SIZE"), 2)
		_more_button.get_popup().id_pressed.connect(_on_more_action)
		add_child(_more_button)
	_more_button.position = Vector2(_card_size().x - 36, 10)
	_more_button.size = Vector2(28, 24)
	_more_button.visible = not locked


func begin_title_edit() -> void:
	if locked or _is_overview():
		return
	if _title_edit == null:
		_title_edit = LineEdit.new()
		_title_edit.name = "TitleEdit"
		_title_edit.text_submitted.connect(func(_value: String) -> void: _commit_title_edit())
		_title_edit.focus_exited.connect(_commit_title_edit)
		_title_edit.gui_input.connect(_on_title_edit_input)
		add_child(_title_edit)
	_title_edit.position = Vector2(36, 7)
	_title_edit.size = Vector2(maxf(64.0, _card_size().x - 116.0), 30)
	_title_edit.text = display_title if not display_title.is_empty() else _display_name
	_title_edit.visible = true
	_title_edit.grab_focus()
	_title_edit.select_all()


func resize_handle_contains_world(world_position: Vector2) -> bool:
	if locked or _lod_camera_zoom < 0.75:
		return false
	var hit_world := 16.0 / maxf(_lod_camera_zoom, 0.01)
	var local := world_position - position
	return Rect2(_card_size() - Vector2.ONE * hit_world, Vector2.ONE * hit_world).has_point(local)


func default_requested_size() -> Vector2i:
	return CardContract.default_size_for_type(_node_type)


func _draw_resize_handle() -> void:
	if locked or _lod_camera_zoom < 0.75:
		return
	var end := _card_size() - Vector2(4, 4)
	draw_line(end - Vector2(8, 0), end, AppTheme.TEXT_MUTED, 2.0)
	draw_line(end - Vector2(0, 8), end, AppTheme.TEXT_MUTED, 2.0)


func _on_title_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		begin_title_edit()
		_title_button.accept_event()


func _on_title_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_title_edit.visible = false
		get_viewport().set_input_as_handled()


func _commit_title_edit() -> void:
	if _title_edit == null or not _title_edit.visible:
		return
	var normalized := CardContract.normalize_display_title(_title_edit.text)
	_title_edit.visible = false
	if normalized != display_title:
		display_title_change_requested.emit(item_id, normalized)


func _on_more_action(action_id: int) -> void:
	match action_id:
		1:
			begin_title_edit()
		2:
			size_change_requested.emit(item_id, default_requested_size())


func _build_object_list_controls() -> void:
	var editor := ObjectListEditorScript.new()
	editor.name = "ObjectListEditor"
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.params_commit_requested.connect(
		func(params: Dictionary) -> void: params_commit_requested.emit(graph_id, node_id, params)
	)
	editor.setup(_params_snapshot)
	_content_root.add_child(editor)


func _build_text_prompt_controls() -> void:
	_text_prompt_edit = TextEdit.new()
	_text_prompt_edit.name = "PromptEdit"
	_text_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_prompt_edit.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_text_prompt_edit.scroll_horizontal = 0
	_text_prompt_edit.text = (
		_prompt_draft_cache if _prompt_draft_cached else String(_params_snapshot.get("text", ""))
	)
	_text_prompt_edit.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, AppTheme.PROMPT_MIN_HEIGHT)
	_text_prompt_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_prompt_edit.placeholder_text = Strings.text("CONTENT_PROMPT_PLACEHOLDER")
	_text_prompt_edit.focus_exited.connect(_commit_text_prompt.bind(_text_prompt_edit))
	_text_prompt_edit.text_changed.connect(_on_prompt_text_changed.bind(_text_prompt_edit))
	_text_prompt_edit.gui_input.connect(_on_prompt_input.bind(_text_prompt_edit))
	_content_root.add_child(_text_prompt_edit)
	var footer := HBoxContainer.new()
	_prompt_draft_label = Label.new()
	_prompt_draft_label.name = "PromptDraft"
	_prompt_draft_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_prompt_draft_label)
	_prompt_count_label = Label.new()
	_prompt_count_label.name = "PromptCharacterCount"
	footer.add_child(_prompt_count_label)
	_content_root.add_child(footer)
	_sync_prompt_draft()


func _build_prompt_preset_controls() -> void:
	var preset_value: Variant = _params_snapshot.get("preset", {})
	var preset: Dictionary = preset_value if preset_value is Dictionary else {}
	_prompt_preset_view = PromptPresetCardViewScript.new()
	_prompt_preset_view.name = "PromptPresetCardView"
	_prompt_preset_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prompt_preset_view.preset_commit_requested.connect(_commit_prompt_preset)
	_prompt_preset_view.configure(preset)
	_content_root.add_child(_prompt_preset_view)


func _commit_prompt_preset(preset: Dictionary) -> void:
	_params_snapshot = {"preset": preset.duplicate(true)}
	params_commit_requested.emit(graph_id, node_id, _params_snapshot.duplicate(true))


func _build_cleanup_shell_controls() -> void:
	_cleanup_view = CleanupCardViewScript.new()
	_cleanup_view.name = "CleanupCardView"
	_cleanup_view.action_requested.connect(
		func(action_id: String) -> void: action_requested.emit(graph_id, node_id, action_id)
	)
	_cleanup_view.params_commit_requested.connect(
		func(params: Dictionary) -> void: params_commit_requested.emit(graph_id, node_id, params)
	)
	_content_root.add_child(_cleanup_view)
	_cleanup_view.configure(
		{
			"params": _params_snapshot.duplicate(true),
			"run": {"state": _generation_state().capitalize()},
			"input": {}
		}
	)


func _build_generate_controls() -> void:
	_generation_view = GenerationCardViewScript.new()
	_generation_view.name = "GenerationCardView"
	_generation_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_generation_view.params_commit_requested.connect(
		func(params: Dictionary) -> void:
			_params_snapshot = params.duplicate(true)
			params_commit_requested.emit(graph_id, node_id, params)
	)
	_generation_view.upstream_requested.connect(
		func(source_id: String) -> void:
			action_requested.emit(graph_id, node_id, "focus_upstream:%s" % source_id)
	)
	_generation_view.action_requested.connect(_on_generation_card_action)
	_content_root.add_child(_generation_view)
	_generation_view.configure(_generation_card_snapshot())


func _build_reference_controls() -> void:
	var asset_id := String(_params_snapshot.get("asset_id", ""))
	var preview := TextureRect.new()
	preview.name = "ReferencePreview"
	preview.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, 220)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var detail := Label.new()
	detail.name = "ReferenceDetail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if asset_id.is_empty():
		detail.text = Strings.text("CONTENT_REFERENCE_NONE")
	elif not AssetLibrary.has_asset(asset_id):
		detail.text = Strings.text("CONTENT_REFERENCE_MISSING_FORMAT") % asset_id.left(8)
	else:
		var meta: Dictionary = AssetLibrary.get_asset_meta(asset_id)
		var image: Image = AssetLibrary.get_image(asset_id)
		if image == null:
			detail.text = Strings.text("CONTENT_REFERENCE_DECODE_FAILED_FORMAT") % asset_id.left(8)
		else:
			preview.texture = ImageTexture.create_from_image(image)
			detail.text = (
				"%d×%d · %s"
				% [
					image.get_width(),
					image.get_height(),
					(
						Strings.text("CONTENT_REFERENCE_ORIGIN_FORMAT")
						% String(meta.get("origin", "imported"))
					),
				]
			)
	_content_root.add_child(preview)
	_content_root.add_child(detail)
	_reference_field = AssetRefFieldScript.new()
	_reference_field.name = "ReferenceField"
	_reference_field.set_value(asset_id)
	_reference_field.visible = false
	_reference_field.value_changed.connect(
		func(value: String) -> void:
			params_commit_requested.emit(graph_id, node_id, {"asset_id": value})
	)
	_reference_field.import_requested.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference")
	)
	_content_root.add_child(_reference_field)
	var actions := HBoxContainer.new()
	var replace := Button.new()
	replace.name = "ReferenceReplace"
	replace.text = Strings.text("ACTION_REPLACE")
	replace.pressed.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference")
	)
	actions.add_child(replace)
	var remove := Button.new()
	remove.name = "ReferenceRemove"
	remove.text = Strings.text("ACTION_REMOVE")
	remove.pressed.connect(
		func() -> void: params_commit_requested.emit(graph_id, node_id, {"asset_id": ""})
	)
	actions.add_child(remove)
	_content_root.add_child(actions)


func _build_reference_set_controls() -> void:
	var asset_ids: Array = _params_snapshot.get("asset_ids", []).duplicate()
	var summary := Label.new()
	summary.name = "ReferenceSetSummary"
	summary.text = Strings.text("CONTENT_REFERENCE_SET_ORDER_SUMMARY") % asset_ids.size()
	_content_root.add_child(summary)
	var grid: Control = MediaTileGridScript.new()
	grid.name = "ReferenceMediaGrid"
	grid.custom_minimum_size = Vector2(0, 224)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var media_items: Array[Dictionary] = []
	for index in range(asset_ids.size()):
		(
			media_items
			. append(
				{
					"id": String(asset_ids[index]),
					"asset_id": String(asset_ids[index]),
					"status": "reference",
					"order_label": str(index + 1),
				}
			)
		)
	grid.configure_items(media_items, false, true, true)
	grid.reorder_requested.connect(_reorder_reference_set_item.bind(asset_ids))
	grid.replace_requested.connect(_replace_reference_set_asset.bind(asset_ids))
	grid.remove_requested.connect(_remove_reference_set_asset.bind(asset_ids))
	_content_root.add_child(grid)
	var add_tile := Button.new()
	add_tile.name = "ReferenceSetAddTile"
	add_tile.text = Strings.text("ACTION_ADD_REFERENCE")
	add_tile.pressed.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference_set")
	)
	_content_root.add_child(add_tile)
	var limit := _reference_limit()
	var limit_label := Label.new()
	limit_label.name = "ReferenceSetLimit"
	limit_label.text = Strings.text("CONTENT_REFERENCE_SET_LIMIT") % limit
	_content_root.add_child(limit_label)
	var add_field := AssetRefFieldScript.new()
	add_field.name = "ReferenceSetAddField"
	add_field.visible = false
	add_field.set_value("")
	add_field.value_changed.connect(
		func(asset_id: String) -> void:
			if asset_id.is_empty():
				return
			var updated := asset_ids.duplicate()
			updated.append(asset_id)
			params_commit_requested.emit(graph_id, node_id, {"asset_ids": updated})
	)
	add_field.import_requested.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference_set")
	)
	_content_root.add_child(add_field)


func _reorder_reference_set_item(
	dragged_asset_id: String, before_asset_id: String, asset_ids: Array
) -> void:
	var updated := asset_ids.duplicate()
	var source_index := updated.find(dragged_asset_id)
	if source_index < 0:
		return
	updated.remove_at(source_index)
	var insert_index := updated.find(before_asset_id) if not before_asset_id.is_empty() else -1
	updated.insert(updated.size() if insert_index < 0 else insert_index, dragged_asset_id)
	if updated == asset_ids:
		return
	reference_reorder_requested.emit(graph_id, node_id, updated.duplicate())
	params_commit_requested.emit(graph_id, node_id, {"asset_ids": updated})


func _replace_reference_set_asset(asset_id: String, asset_ids: Array) -> void:
	var index := asset_ids.find(asset_id)
	if index >= 0:
		action_requested.emit(graph_id, node_id, "replace_reference:%d" % index)


func _remove_reference_set_asset(asset_id: String, asset_ids: Array) -> void:
	var updated := asset_ids.duplicate()
	updated.erase(asset_id)
	params_commit_requested.emit(graph_id, node_id, {"asset_ids": updated})


func _reference_limit() -> int:
	var descriptors := ProviderService.get_selectable_model_descriptors()
	if descriptors.is_empty():
		return 0
	var capabilities: Dictionary = descriptors[0].get("capabilities", {})
	return maxi(0, int(capabilities.get("max_reference_images", 0)))


func _commit_text_prompt(editor: TextEdit = null) -> void:
	var target := editor if editor != null else _text_prompt_edit
	if target == null or target != _text_prompt_edit:
		return
	var text := target.text
	if text == String(_params_snapshot.get("text", "")):
		_prompt_draft_cached = false
		_sync_prompt_draft()
		return
	_params_snapshot["text"] = text
	_prompt_draft_cache = text
	_prompt_draft_cached = false
	_sync_prompt_draft()
	params_commit_requested.emit(graph_id, node_id, {"text": text})


func _on_prompt_text_changed(editor: TextEdit) -> void:
	if editor != _text_prompt_edit or _suppress_prompt_draft_tracking:
		return
	_prompt_draft_cache = editor.text
	_prompt_draft_cached = editor.text != String(_params_snapshot.get("text", ""))
	_sync_prompt_draft()


func _sync_prompt_draft() -> void:
	if _text_prompt_edit == null:
		return
	var changed := _text_prompt_edit.text != String(_params_snapshot.get("text", ""))
	if _prompt_draft_label != null:
		_prompt_draft_label.text = Strings.text("CONTENT_PROMPT_DRAFT") if changed else ""
	if _prompt_count_label != null:
		_prompt_count_label.text = (
			Strings.text("CONTENT_PROMPT_CHARACTER_COUNT") % _text_prompt_edit.text.length()
		)


func _on_prompt_input(event: InputEvent, editor: TextEdit = null) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var target := editor if editor != null else _text_prompt_edit
	if target == null or target != _text_prompt_edit:
		return
	if event.keycode == KEY_ESCAPE:
		_suppress_prompt_draft_tracking = true
		target.text = String(_params_snapshot.get("text", ""))
		_suppress_prompt_draft_tracking = false
		_prompt_draft_cache = target.text
		_prompt_draft_cached = false
		target.release_focus()
		_sync_prompt_draft()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and event.is_command_or_control_pressed():
		_commit_text_prompt(target)
		get_viewport().set_input_as_handled()


func _configure_internal_scroll_ownership() -> void:
	if _content_root == null:
		return
	var controls: Array[Control] = []
	_collect_internal_scroll_controls(_content_root, controls)
	for control in controls:
		if control.has_meta("_pf_scroll_owner_wired"):
			continue
		control.set_meta("_pf_scroll_owner_wired", true)
		control.gui_input.connect(_on_internal_scroll_input.bind(control))


func _collect_internal_scroll_controls(node: Node, result: Array[Control]) -> void:
	for child in node.get_children():
		if child is ScrollContainer or child is TextEdit:
			result.append(child)
		_collect_internal_scroll_controls(child, result)


func _on_internal_scroll_input(event: InputEvent, control: Control) -> void:
	if not _is_plain_internal_scroll_event(event):
		return
	# A card-owned scroll gesture never falls through at its boundary to canvas zoom/pan.
	control.accept_event()


func _is_plain_internal_scroll_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return (
			event.pressed
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
			and not event.ctrl_pressed
			and not event.meta_pressed
		)
	if event is InputEventPanGesture:
		return not event.ctrl_pressed and not event.meta_pressed
	return false


func _capture_content_interaction_state() -> Dictionary:
	if _content_root == null:
		return {}
	var state := {"scrolls": {}}
	var focus_owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus_owner != null and _content_root.is_ancestor_of(focus_owner):
		state["focus_path"] = _content_root.get_path_to(focus_owner)
		if focus_owner is LineEdit:
			state["focus_text"] = focus_owner.text
			state["caret_column"] = focus_owner.caret_column
		elif focus_owner is TextEdit:
			state["focus_text"] = focus_owner.text
			state["caret_line"] = focus_owner.get_caret_line()
			state["caret_column"] = focus_owner.get_caret_column()
			state["text_scroll"] = [focus_owner.scroll_horizontal, focus_owner.scroll_vertical]
	var scrolls: Dictionary = state["scrolls"]
	_capture_scroll_offsets(_content_root, scrolls)
	if _prompt_preset_view != null:
		state["prompt_preset_view"] = _prompt_preset_view.export_interaction_state()
	if _text_prompt_edit != null:
		_prompt_draft_cache = _text_prompt_edit.text
		_prompt_draft_cached = (_prompt_draft_cache != String(_params_snapshot.get("text", "")))
	return state


func _capture_scroll_offsets(node: Node, result: Dictionary) -> void:
	for child in node.get_children():
		if child is ScrollContainer:
			result[_content_root.get_path_to(child)] = [
				child.scroll_horizontal, child.scroll_vertical
			]
		_capture_scroll_offsets(child, result)


func _restore_content_interaction_state(state: Dictionary) -> void:
	if state.is_empty() or _content_root == null:
		return
	if _prompt_preset_view != null and state.has("prompt_preset_view"):
		_prompt_preset_view.import_interaction_state(state["prompt_preset_view"])
	var focus_path: NodePath = state.get("focus_path", NodePath(""))
	if not focus_path.is_empty():
		var focus_owner := _content_root.get_node_or_null(focus_path) as Control
		if focus_owner is LineEdit:
			focus_owner.text = String(state.get("focus_text", focus_owner.text))
			focus_owner.caret_column = int(state.get("caret_column", focus_owner.text.length()))
			focus_owner.grab_focus()
		elif focus_owner is TextEdit:
			_suppress_prompt_draft_tracking = true
			focus_owner.text = String(state.get("focus_text", focus_owner.text))
			_suppress_prompt_draft_tracking = false
			focus_owner.set_caret_line(int(state.get("caret_line", 0)))
			focus_owner.set_caret_column(int(state.get("caret_column", 0)))
			var text_scroll: Array = state.get("text_scroll", [0, 0])
			focus_owner.scroll_horizontal = int(text_scroll[0])
			focus_owner.scroll_vertical = float(text_scroll[1])
			focus_owner.grab_focus()
	_restore_scroll_offsets(state.get("scrolls", {}))
	call_deferred("_restore_scroll_offsets", state.get("scrolls", {}))


func _restore_scroll_offsets(scrolls: Dictionary) -> void:
	if _content_root == null:
		return
	for path_value in scrolls:
		var scroll := _content_root.get_node_or_null(NodePath(path_value)) as ScrollContainer
		if scroll == null:
			continue
		var offsets: Array = scrolls[path_value]
		scroll.scroll_horizontal = int(offsets[0])
		scroll.scroll_vertical = int(offsets[1])


func _generation_card_snapshot() -> Dictionary:
	var graph_data := ProjectService.get_graph_data(graph_id)
	var source_ids := {}
	for edge_value in graph_data.get("edges", []):
		if not (edge_value is Dictionary):
			continue
		var edge: Dictionary = edge_value
		var target: Array = edge.get("to", ["", ""])
		var source: Array = edge.get("from", ["", ""])
		if String(target[0]) == node_id:
			source_ids[String(target[1])] = String(source[0])
	var nodes := {}
	for node_value in graph_data.get("nodes", []):
		if node_value is Dictionary:
			nodes[String(node_value.get("id", ""))] = node_value
	var prefix := ""
	var prompt := ""
	var rows: Array = []
	var reference_count := 0
	var input_sources := []
	for port in ["prefix", "prompt", "subjects", "references"]:
		var source_id := String(source_ids.get(port, ""))
		var source: Dictionary = nodes.get(source_id, {})
		if source.is_empty():
			continue
		var params: Dictionary = source.get("params", {})
		input_sources.append({"id": source_id, "kind": port, "summary": _summarize_params(params)})
		match port:
			"prefix":
				var preset: Dictionary = params.get("preset", {})
				prefix = String(preset.get("prefix", params.get("prefix", "")))
			"prompt":
				prompt = String(params.get("text", ""))
			"subjects":
				rows = Array(params.get("rows", [])).duplicate(true)
			"references":
				if params.has("asset_ids"):
					reference_count = Array(params.get("asset_ids", [])).size()
				elif not String(params.get("asset_id", "")).is_empty():
					reference_count = 1
	var descriptor := ProviderService.get_model_descriptor(
		String(_params_snapshot.get("provider_id", "")),
		String(_params_snapshot.get("model_id", ""))
	)
	return {
		"params": _params_snapshot.duplicate(true),
		"descriptor": descriptor,
		"descriptors": ProviderService.get_selectable_model_descriptors(),
		"developer_mode": SettingsService.is_developer_mode_enabled(),
		"api_host": _provider_api_host(String(_params_snapshot.get("provider_id", ""))),
		"prefix": prefix,
		"prompt": prompt,
		"rows": rows,
		"reference_count": reference_count,
		"input_sources": input_sources,
		"run": {"state": _generation_state().capitalize(), "errors": []},
	}


func _provider_api_host(provider_id: String) -> String:
	var provider: Variant = ProviderService.get_provider(provider_id)
	if provider == null or not provider.has_method("get_base_url"):
		return ""
	var base_url := String(provider.get_base_url())
	var without_scheme := base_url.get_slice("://", 1) if "://" in base_url else base_url
	return without_scheme.get_slice("/", 0)


func _on_developer_mode_changed(enabled: bool) -> void:
	if _generation_view != null and _generation_view.has_method("set_developer_mode"):
		_generation_view.set_developer_mode(enabled)


func _on_generation_card_action(action_id: String, _route: String) -> void:
	var canvas_action := action_id
	if action_id in ["generate", "regenerate", "regenerate_confirm"]:
		canvas_action = "run"
	action_requested.emit(graph_id, node_id, canvas_action)


func _localized_display_name(node: PFNode) -> String:
	match node.get_type():
		"text_prompt":
			return Strings.text("NODE_TEXT_PROMPT")
		"object_list":
			return Strings.text("NODE_OBJECT_LIST")
		"prompt_preset":
			return Strings.text("NODE_PROMPT_PRESET")
		"image_input":
			return Strings.text("NODE_IMAGE_INPUT")
		"reference_set":
			return Strings.text("NODE_REFERENCE_SET")
		"ai_generate":
			return Strings.text("NODE_AI_GENERATE")
		"pixel_cleanup":
			return Strings.text("NODE_PIXEL_CLEANUP")
		"batch":
			return Strings.text("NODE_BATCH")
		_:
			return node.get_display_name()


func _execution_status_text(key: String) -> String:
	match key:
		"CONTENT_STATUS_QUEUED":
			return Strings.text("CONTENT_STATUS_QUEUED")
		"CONTENT_STATUS_RUNNING":
			return Strings.text("CONTENT_STATUS_RUNNING")
		"CONTENT_STATUS_CANCELING":
			return Strings.text("CONTENT_STATUS_CANCELING")
		"CONTENT_STATUS_PARTIAL":
			return Strings.text("CONTENT_STATUS_PARTIAL")
		"CONTENT_STATUS_FAILED":
			return Strings.text("CONTENT_STATUS_FAILED")
		"CONTENT_STATUS_COMPLETE":
			return Strings.text("CONTENT_STATUS_COMPLETE")
		"CONTENT_STATUS_CANCELED":
			return Strings.text("CONTENT_STATUS_CANCELED")
		_:
			return Strings.text("CONTENT_STATUS_READY")


func _reference_action_text(action: String) -> String:
	match action:
		"up":
			return Strings.text("ACTION_REFERENCE_UP")
		"down":
			return Strings.text("ACTION_REFERENCE_DOWN")
		_:
			return Strings.text("ACTION_REFERENCE_REMOVE")


func _on_language_changed(_preference: String, _locale: String) -> void:
	var interaction_state := _capture_content_interaction_state()
	_resolve_graph_node()
	_rebuild_content_controls()
	_restore_content_interaction_state(interaction_state)
	_rebuild_header_controls()
	queue_redraw()


func _sync_run_controls() -> void:
	if _generation_view != null:
		_generation_view.set_run_context({"state": _generation_state().capitalize(), "errors": []})


func _generation_state() -> String:
	if _execution_status_key.begins_with("CONTENT_STATUS_"):
		return _execution_status_key.trim_prefix("CONTENT_STATUS_")
	return "READY"
