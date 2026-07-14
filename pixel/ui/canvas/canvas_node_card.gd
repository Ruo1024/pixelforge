# gdlint: disable=max-file-lines
class_name PFCanvasNodeCard
extends Node2D

## M3 画布轻节点卡。
## contract: 02-contracts/PROJECT-FORMAT.md §4；只保存 graph/node 引用，节点逻辑从 graphs 读取。

signal params_commit_requested(graph_id: String, node_id: String, params: Dictionary)
signal action_requested(graph_id: String, node_id: String, action_id: String)
signal collapsed_change_requested(item_id: String, collapsed: bool)
signal display_title_change_requested(item_id: String, display_title: String)
signal size_change_requested(item_id: String, requested_size: Vector2i)

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")
const AssetRefFieldScript := preload("res://ui/widgets/asset_ref_field.gd")
const ObjectListEditorScript := preload("res://ui/canvas/object_list_editor.gd")
const GenerationModelPolicyScript := preload("res://services/generation_model_policy.gd")
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
const SPIN_CONTROL_MIN_SIZE := Vector2(76, 30)
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
var _execution_detail := ""
var _font: Font = null
var _content_root: Control = null
var _text_prompt_edit: TextEdit = null
var _prompt_count_label: Label = null
var _prompt_draft_label: Label = null
var _model_option: OptionButton = null
var _model_capability_label: Label = null
var _cost_estimate_label: Label = null
var _batch_size_spin: SpinBox = null
var _seed_spin: SpinBox = null
var _run_button: Button = null
var _cancel_button: Button = null
var _execution_detail_label: Label = null
var _reference_field: Control = null
var _collapse_button: Button = null
var _title_button: Button = null
var _title_edit: LineEdit = null
var _more_button: MenuButton = null
var _params_snapshot := {}
var _raw_data := {}
var _lod_camera_zoom := 1.0


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
	_resolve_graph_node()
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func set_collapsed(value: bool) -> void:
	if collapsed == value:
		return
	collapsed = value
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func set_display_title(value: Variant) -> void:
	display_title = CardContract.normalize_display_title(value)
	_resolve_graph_node()
	_rebuild_header_controls()
	queue_redraw()


func set_requested_size(value: Variant) -> void:
	requested_size = CardContract.normalize_requested_size(_node_type, value)
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func get_requested_size() -> Vector2i:
	return requested_size


func set_lod_camera_zoom(value: float) -> void:
	_lod_camera_zoom = maxf(0.0, value)
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func get_content_control(control_name: String) -> Control:
	if _content_root == null:
		return null
	return _content_root.find_child(control_name, true, false) as Control


func set_execution_status(status_key: String, detail: String = "") -> void:
	_execution_status_key = status_key
	_execution_detail = detail
	_status_badge = Strings.text(status_key) if not status_key.is_empty() else ""
	_sync_execution_detail()
	_sync_run_controls()
	queue_redraw()


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
		_display_name = Strings.GRAPH_NODE_MISSING_DISPLAY % _node_type
		_summary = Strings.GRAPH_NODE_GHOST_SUMMARY
		_input_count = 0
		_output_count = 0
		_input_ports = []
		_output_ports = []
		_visible_input_ports = []
		_visible_output_ports = []
		_status_badge = Strings.GRAPH_NODE_BADGE_MISSING
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
		_status_badge = Strings.GRAPH_NODE_BADGE_EDGE_ERROR
	if not _execution_status_key.is_empty():
		_status_badge = Strings.text(_execution_status_key)
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
	return float(CardContract.CONTENT_RAIL_HEIGHT if _node_type == "image_input" else HEADER_HEIGHT)


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
	_model_option = null
	_model_capability_label = null
	_cost_estimate_label = null
	_batch_size_spin = null
	_seed_spin = null
	_run_button = null
	_cancel_button = null
	_execution_detail_label = null
	_reference_field = null
	if collapsed or _is_overview() or not _is_content_node() or _is_ghost:
		return

	_content_root = VBoxContainer.new()
	_content_root.name = "Content"
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
	_text_prompt_edit.text = String(_params_snapshot.get("text", ""))
	_text_prompt_edit.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, AppTheme.PROMPT_MIN_HEIGHT)
	_text_prompt_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_prompt_edit.placeholder_text = Strings.text("CONTENT_PROMPT_PLACEHOLDER")
	_text_prompt_edit.focus_exited.connect(_commit_text_prompt)
	_text_prompt_edit.text_changed.connect(_sync_prompt_draft)
	_text_prompt_edit.gui_input.connect(_on_prompt_input)
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
	var name_label := Label.new()
	name_label.name = "PresetName"
	name_label.text = String(preset.get("name", preset.get("name_key", "")))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(name_label)
	var prefix_label := Label.new()
	prefix_label.name = "PresetPrefix"
	prefix_label.text = String(preset.get("prefix", ""))
	prefix_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(prefix_label)


func _build_cleanup_shell_controls() -> void:
	var preset_label := Label.new()
	preset_label.name = "CleanupPresetId"
	preset_label.text = String(_params_snapshot.get("preset_id", ""))
	_content_root.add_child(preset_label)
	var settings_label := Label.new()
	settings_label.name = "CleanupSettingsSnapshot"
	settings_label.text = JSON.stringify(_params_snapshot.get("settings", {}))
	settings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(settings_label)


func _build_generate_controls() -> void:
	var model_row := HBoxContainer.new()
	var model_label := Label.new()
	model_label.text = Strings.text("GRAPH_PARAM_MODEL")
	model_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_row.add_child(model_label)
	_model_option = OptionButton.new()
	_model_option.name = "ProviderOption"
	_model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var descriptors := ProviderService.get_selectable_model_descriptors()
	var current_provider := String(_params_snapshot.get("provider_id", ""))
	var current_model := String(_params_snapshot.get("model_id", ""))
	var selected_index := 0
	for descriptor in descriptors:
		var index := _model_option.item_count
		_model_option.add_item(String(descriptor.get("display_name", "")))
		_model_option.set_item_metadata(index, descriptor.duplicate(true))
		var descriptor_provider := String(descriptor.get("provider_id", ""))
		var descriptor_model := String(descriptor.get("model_id", ""))
		if (
			descriptor_provider == current_provider
			and (
				current_model == descriptor_model
				or (current_model.is_empty() and bool(descriptor.get("is_default", false)))
			)
		):
			selected_index = index
	_model_option.disabled = descriptors.is_empty()
	if not descriptors.is_empty():
		_model_option.select(selected_index)
	_model_option.item_selected.connect(_on_model_selected)
	model_row.add_child(_model_option)
	_content_root.add_child(model_row)

	_model_capability_label = Label.new()
	_model_capability_label.name = "ModelCapabilities"
	_model_capability_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(_model_capability_label)
	var input_summary := Label.new()
	input_summary.name = "RequestSummary"
	input_summary.text = _generation_input_summary()
	input_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_root.add_child(input_summary)

	var target_label := Label.new()
	target_label.name = "TargetSummary"
	target_label.text = (
		"%d×%d px"
		% [
			int(_params_snapshot.get("target_width", 32)),
			int(_params_snapshot.get("target_height", 32)),
		]
	)
	_content_root.add_child(target_label)

	var settings_row := HBoxContainer.new()
	_batch_size_spin = _make_spin("BatchSize", 1, 16, int(_params_snapshot.get("batch_size", 1)))
	_seed_spin = _make_spin("Seed", -1, 2147483647, int(_params_snapshot.get("seed", -1)))
	_batch_size_spin.value_changed.connect(func(_value: float) -> void: _sync_model_controls())
	settings_row.add_child(
		_labeled_control(Strings.text("GRAPH_PARAM_BATCH_SIZE"), _batch_size_spin)
	)
	_content_root.add_child(settings_row)
	var advanced_toggle := Button.new()
	advanced_toggle.name = "AdvancedToggle"
	advanced_toggle.text = Strings.text("CONTENT_ADVANCED")
	advanced_toggle.toggle_mode = true
	_content_root.add_child(advanced_toggle)
	var advanced := VBoxContainer.new()
	advanced.name = "AdvancedSettings"
	advanced.visible = false
	advanced.add_child(_labeled_control(Strings.text("GRAPH_PARAM_SEED"), _seed_spin))
	advanced_toggle.toggled.connect(func(value: bool) -> void: advanced.visible = value)
	_content_root.add_child(advanced)

	_cost_estimate_label = Label.new()
	_cost_estimate_label.name = "CostEstimate"
	_content_root.add_child(_cost_estimate_label)
	_sync_model_controls()

	_run_button = Button.new()
	_run_button.name = "PrimaryActionButton"
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(_on_generation_primary_pressed)
	_content_root.add_child(_run_button)
	_execution_detail_label = Label.new()
	_execution_detail_label.name = "ExecutionDetail"
	_execution_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_execution_detail_label.custom_minimum_size.y = 36
	_content_root.add_child(_execution_detail_label)
	_sync_execution_detail()
	_sync_run_controls()


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
	var scroll := ScrollContainer.new()
	scroll.name = "ReferenceSetScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := GridContainer.new()
	rows.name = "ReferenceSetRows"
	rows.columns = maxi(1, int(floor(float(requested_size.x - 32) / 108.0)))
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(asset_ids.size()):
		rows.add_child(_reference_set_row(asset_ids, index))
	var add_tile := Button.new()
	add_tile.name = "ReferenceSetAddTile"
	add_tile.text = Strings.text("ACTION_ADD_REFERENCE")
	add_tile.custom_minimum_size = Vector2.ONE * AppTheme.REFERENCE_TILE_SIZE
	add_tile.pressed.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference_set")
	)
	rows.add_child(add_tile)
	scroll.add_child(rows)
	_content_root.add_child(scroll)
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


func _reference_set_row(asset_ids: Array, index: int) -> Control:
	var asset_id := String(asset_ids[index])
	var row := VBoxContainer.new()
	row.name = "ReferenceSetRow%d" % index
	row.custom_minimum_size = Vector2(
		AppTheme.REFERENCE_TILE_SIZE, AppTheme.REFERENCE_TILE_ROW_HEIGHT
	)
	var preview := TextureRect.new()
	preview.name = "ReferenceSetPreview%d" % index
	preview.custom_minimum_size = Vector2.ONE * AppTheme.REFERENCE_TILE_SIZE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var detail := Label.new()
	detail.name = "ReferenceSetDetail%d" % index
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if asset_id.is_empty():
		detail.text = Strings.text("CONTENT_REFERENCE_NONE")
	elif not AssetLibrary.has_asset(asset_id):
		detail.text = Strings.text("CONTENT_REFERENCE_MISSING_FORMAT") % asset_id.left(8)
	else:
		var image: Image = AssetLibrary.get_image(asset_id)
		var meta: Dictionary = AssetLibrary.get_asset_meta(asset_id)
		if image == null:
			detail.text = Strings.text("CONTENT_REFERENCE_DECODE_FAILED_FORMAT") % asset_id.left(8)
		else:
			preview.texture = ImageTexture.create_from_image(image)
			detail.text = "%d. %s" % [index + 1, String(meta.get("name", ""))]
	row.add_child(preview)
	row.add_child(detail)
	var field := AssetRefFieldScript.new()
	field.name = "ReferenceSetField%d" % index
	field.visible = false
	field.set_value(asset_id)
	field.value_changed.connect(_replace_reference_set_item.bind(asset_ids, index))
	row.add_child(field)
	var action_row := HBoxContainer.new()
	for action in ["up", "down", "remove"]:
		var button := Button.new()
		button.name = "ReferenceSet%s%d" % [String(action).capitalize(), index]
		button.text = Strings.text("ACTION_REFERENCE_%s" % String(action).to_upper())
		button.disabled = (
			(action == "up" and index == 0) or (action == "down" and index == asset_ids.size() - 1)
		)
		button.pressed.connect(_change_reference_set_item.bind(asset_ids, index, action))
		button.visible = false
		action_row.add_child(button)
	row.add_child(action_row)
	var menu := MenuButton.new()
	menu.name = "ReferenceSetMenu%d" % index
	menu.text = Strings.text("ACTION_MORE")
	menu.get_popup().add_item(Strings.text("ACTION_REPLACE"), 0)
	menu.get_popup().add_item(Strings.text("ACTION_REMOVE"), 1)
	menu.get_popup().id_pressed.connect(
		func(action_id: int) -> void:
			if action_id == 0:
				action_requested.emit(graph_id, node_id, "replace_reference:%d" % index)
			else:
				_change_reference_set_item(asset_ids, index, "remove")
	)
	row.add_child(menu)
	return row


func _reference_limit() -> int:
	var descriptors := ProviderService.get_selectable_model_descriptors()
	if descriptors.is_empty():
		return 0
	var capabilities: Dictionary = descriptors[0].get("capabilities", {})
	return maxi(0, int(capabilities.get("max_reference_images", 0)))


func _replace_reference_set_item(asset_id: String, asset_ids: Array, index: int) -> void:
	var updated := asset_ids.duplicate()
	updated[index] = asset_id
	params_commit_requested.emit(graph_id, node_id, {"asset_ids": updated})


func _change_reference_set_item(asset_ids: Array, index: int, action: String) -> void:
	var updated := asset_ids.duplicate()
	match action:
		"up":
			var previous: Variant = updated[index - 1]
			updated[index - 1] = updated[index]
			updated[index] = previous
		"down":
			var following: Variant = updated[index + 1]
			updated[index + 1] = updated[index]
			updated[index] = following
		"remove":
			updated.remove_at(index)
	params_commit_requested.emit(graph_id, node_id, {"asset_ids": updated})


func _make_spin(control_name: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = value
	spin.custom_minimum_size = SPIN_CONTROL_MIN_SIZE
	return spin


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	box.add_child(control)
	return box


func _commit_text_prompt() -> void:
	if _text_prompt_edit == null:
		return
	var text := _text_prompt_edit.text
	if text == String(_params_snapshot.get("text", "")):
		_sync_prompt_draft()
		return
	params_commit_requested.emit(graph_id, node_id, {"text": text})
	_params_snapshot["text"] = text
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


func _on_prompt_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		_text_prompt_edit.text = String(_params_snapshot.get("text", ""))
		_text_prompt_edit.release_focus()
		_sync_prompt_draft()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and event.is_command_or_control_pressed():
		_commit_text_prompt()
		get_viewport().set_input_as_handled()


func _commit_generate_params() -> void:
	if (
		_model_option == null
		or _model_option.item_count == 0
		or _batch_size_spin == null
		or _seed_spin == null
	):
		return
	var descriptor: Dictionary = _model_option.get_item_metadata(_model_option.selected)
	var transition: Dictionary = (
		GenerationModelPolicyScript
		. transition(
			_params_snapshot,
			String(descriptor.get("provider_id", "")),
			String(descriptor.get("model_id", "")),
			[descriptor],
		)
	)
	if not bool(transition.get("ok", false)):
		return
	var transitioned_params: Dictionary = transition["params"]
	transitioned_params["batch_size"] = int(_batch_size_spin.value)
	transitioned_params["seed"] = int(_seed_spin.value)
	_params_snapshot = transitioned_params.duplicate(true)
	params_commit_requested.emit(graph_id, node_id, transitioned_params)


func _on_model_selected(_index: int) -> void:
	_sync_model_controls()
	_commit_generate_params()


func _sync_model_controls() -> void:
	if _model_option == null or _model_option.item_count == 0:
		return
	var descriptor: Dictionary = _model_option.get_item_metadata(_model_option.selected)
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var max_batch := maxi(1, int(capabilities.get("max_batch", 1)))
	_batch_size_spin.max_value = max_batch
	_batch_size_spin.value = mini(int(_batch_size_spin.value), max_batch)
	_seed_spin.visible = bool(capabilities.get("seed", false))
	var references := int(capabilities.get("max_reference_images", 0))
	var output_summary := _model_output_summary(capabilities)
	_model_capability_label.text = (
		Strings.text("CONTENT_MODEL_CAPABILITIES_FORMAT")
		% [String(descriptor.get("provider_id", "")), output_summary, max_batch, references]
	)
	var provider_id := String(descriptor.get("provider_id", ""))
	var estimate := (
		0.0
		if provider_id == "mock"
		else (
			CostService
			. estimate_request(
				provider_id,
				{
					"model_id": String(descriptor.get("model_id", "")),
					"batch": int(_batch_size_spin.value),
				}
			)
		)
	)
	_cost_estimate_label.text = (
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % estimate
		if estimate >= 0.0
		else Strings.text("CONTENT_COST_UNKNOWN")
	)


func _model_output_summary(capabilities: Dictionary) -> String:
	var sizes: Array = capabilities.get("output_sizes", [])
	if not sizes.is_empty():
		return " / ".join(sizes)
	var constraints: Dictionary = capabilities.get("output_size_constraints", {})
	return (
		Strings.text("CONTENT_MODEL_TARGET_RANGE_FORMAT")
		% [int(constraints.get("min_side", 1)), int(constraints.get("max_side", 1))]
	)


func _generation_input_summary() -> String:
	var graph_data := ProjectService.get_graph_data(graph_id)
	var sources := {}
	for raw_edge in graph_data.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge: Dictionary = raw_edge
		var to_data: Array = edge.get("to", ["", ""])
		var from_data: Array = edge.get("from", ["", ""])
		if String(to_data[0]) == node_id:
			sources[String(to_data[1])] = String(from_data[0])
	var node_by_id := {}
	for raw_node in graph_data.get("nodes", []):
		if raw_node is Dictionary:
			node_by_id[String(raw_node.get("id", ""))] = raw_node
	var prompt := Strings.text("CONTENT_PROMPT_EMPTY")
	for input_port in ["prompt", "subjects"]:
		var source: Dictionary = node_by_id.get(String(sources.get(input_port, "")), {})
		if not source.is_empty():
			prompt = _summarize_params(source.get("params", {}))
			break
	var prefix := ""
	var prefix_source: Dictionary = node_by_id.get(String(sources.get("prefix", "")), {})
	if not prefix_source.is_empty():
		prefix = _summarize_params(prefix_source.get("params", {}))
	var target := (
		"%d×%d px"
		% [
			int(_params_snapshot.get("target_width", 32)),
			int(_params_snapshot.get("target_height", 32)),
		]
	)
	return Strings.text("CONTENT_REQUEST_SUMMARY_FORMAT") % [prompt, prefix, target]


func _localized_display_name(node: PFNode) -> String:
	var key_by_type := {
		"text_prompt": "NODE_TEXT_PROMPT",
		"object_list": "NODE_OBJECT_LIST",
		"prompt_preset": "NODE_PROMPT_PRESET",
		"image_input": "NODE_IMAGE_INPUT",
		"reference_set": "NODE_REFERENCE_SET",
		"ai_generate": "NODE_AI_GENERATE",
		"pixel_cleanup": "NODE_PIXEL_CLEANUP",
		"batch": "NODE_BATCH",
	}
	var key := String(key_by_type.get(node.get_type(), ""))
	return (
		Strings.text(key, node.get_display_name())
		if not key.is_empty()
		else node.get_display_name()
	)


func _on_language_changed(_preference: String, _locale: String) -> void:
	_resolve_graph_node()
	_rebuild_content_controls()
	_rebuild_header_controls()
	queue_redraw()


func _sync_run_controls() -> void:
	if _run_button == null:
		return
	var state := _generation_state()
	var text_key_by_state := {
		"INCOMPLETE": "CONTENT_ACTION_FIX_INPUT",
		"READY": "CONTENT_ACTION_GENERATE",
		"QUEUED": "CONTENT_ACTION_CANCEL",
		"RUNNING": "CONTENT_ACTION_CANCEL",
		"CANCELING": "CONTENT_ACTION_STOPPING",
		"COMPLETE": "CONTENT_ACTION_GENERATE_AGAIN",
		"PARTIAL": "CONTENT_ACTION_RETRY_FAILED",
		"FAILED": "CONTENT_ACTION_RETRY",
		"CANCELED": "CONTENT_ACTION_GENERATE_AGAIN",
	}
	_run_button.text = Strings.text(String(text_key_by_state.get(state, "CONTENT_ACTION_GENERATE")))
	_run_button.disabled = state == "CANCELING"


func _generation_state() -> String:
	if _execution_status_key.begins_with("CONTENT_STATUS_"):
		return _execution_status_key.trim_prefix("CONTENT_STATUS_")
	return "READY"


func _on_generation_primary_pressed() -> void:
	var state := _generation_state()
	match state:
		"INCOMPLETE":
			action_requested.emit(graph_id, node_id, "fix_input")
		"QUEUED", "RUNNING":
			action_requested.emit(graph_id, node_id, "cancel")
		"PARTIAL":
			action_requested.emit(graph_id, node_id, "retry_failed")
		"FAILED":
			action_requested.emit(graph_id, node_id, "retry")
		"CANCELING":
			return
		_:
			_commit_generate_params()
			action_requested.emit(graph_id, node_id, "run")


func _sync_execution_detail() -> void:
	if _execution_detail_label == null:
		return
	_execution_detail_label.text = _execution_detail
	_execution_detail_label.visible = not _execution_detail.is_empty()
