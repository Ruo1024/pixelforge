class_name PFCanvasNodeCard
extends Node2D

## M3 画布轻节点卡。
## contract: 02-contracts/PROJECT-FORMAT.md §4；只保存 graph/node 引用，节点逻辑从 graphs 读取。

signal params_commit_requested(graph_id: String, node_id: String, params: Dictionary)
signal action_requested(graph_id: String, node_id: String, action_id: String)
signal collapsed_change_requested(item_id: String, collapsed: bool)

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")
const AssetRefFieldScript := preload("res://ui/widgets/asset_ref_field.gd")

const SUMMARY_CARD_SIZE := Vector2(220, 116)
const CONTENT_CARD_SIZE := Vector2(240, 238)
const GENERATE_CARD_SIZE := Vector2(240, 282)
const REFERENCE_CARD_SIZE := Vector2(260, 330)
const HEADER_HEIGHT := 32
const PADDING := 12
const BACKGROUND := Color(0.13, 0.145, 0.155, 0.98)
const HEADER := Color(0.22, 0.27, 0.3, 1.0)
const BORDER := Color(0.56, 0.64, 0.66, 1.0)
const GHOST_BORDER := Color(0.8, 0.36, 0.36, 1.0)
const EDGE_ERROR_BORDER := Color(0.94, 0.5, 0.22, 1.0)
const BADGE_BACKGROUND := Color(0.12, 0.08, 0.06, 0.92)
const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
const PORT_HIT_RADIUS := 10.0
const OBJECT_EDITOR_MIN_SIZE := Vector2(0, 116)
const SPIN_CONTROL_MIN_SIZE := Vector2(76, 30)
const FLEXIBLE_WIDTH := 0

var item_id := ""
var graph_id := ""
var node_id := ""
var locked := false
var collapsed := false
var frame_id: Variant = null

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
var _object_edit: TextEdit = null
var _provider_option: OptionButton = null
var _batch_size_spin: SpinBox = null
var _seed_spin: SpinBox = null
var _run_button: Button = null
var _cancel_button: Button = null
var _execution_detail_label: Label = null
var _reference_field: Control = null
var _collapse_button: Button = null
var _params_snapshot := {}
var _raw_data := {}


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	locked = bool(data.get("locked", false))
	collapsed = bool(data.get("collapsed", false))
	frame_id = data.get("frame_id", null)
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_resolve_graph_node()
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
	var input_hit := _port_hit_at_world(world_position, true)
	if not input_hit.is_empty():
		return input_hit
	return _port_hit_at_world(world_position, false)


func _draw() -> void:
	_font = UIFont.get_font() if _font == null else _font
	var card_size := _card_size()
	var rect := Rect2(Vector2.ZERO, card_size)
	draw_rect(rect, BACKGROUND, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(card_size.x, HEADER_HEIGHT)), HEADER, true)
	draw_rect(rect, _border_color(), false, 1.4)
	_draw_ports()
	if _font == null:
		return
	draw_string(
		_font,
		Vector2(PADDING, 22),
		_display_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		card_size.x - PADDING * 2,
		16,
		Color(0.92, 0.94, 0.94, 1.0)
	)
	_draw_status_badge()
	if collapsed or not _is_content_node():
		draw_string(
			_font,
			Vector2(PADDING, 54),
			_node_type,
			HORIZONTAL_ALIGNMENT_LEFT,
			card_size.x - PADDING * 2,
			13,
			Color(0.66, 0.72, 0.74, 1.0)
		)
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
	for index in range(_input_count):
		draw_circle(_port_position(index, _input_count, true), 5.0, PORT_IN)
	for index in range(_output_count):
		draw_circle(_port_position(index, _output_count, false), 5.0, PORT_OUT)


func _port_position(index: int, count: int, is_input: bool) -> Vector2:
	var usable_height := _card_size().y - HEADER_HEIGHT - PADDING * 2
	var y := HEADER_HEIGHT + PADDING + usable_height * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else _card_size().x, y)


func _port_index(port_name: String, is_input: bool) -> int:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	return ports.find(port_name)


func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
	var ports := _visible_input_ports if is_input else _visible_output_ports
	var count := ports.size()
	for index in range(count):
		var anchor := position + _port_position(index, count, is_input)
		if anchor.distance_to(world_position) <= PORT_HIT_RADIUS:
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
	if source.has("items"):
		var lines := String(source["items"]).split("\n", false)
		return "%d objects" % lines.size()
	if source.has("width") and source.has("height"):
		return "%dx%d px" % [int(source["width"]), int(source["height"])]
	if source.has("provider_id"):
		return "%s seed %d" % [String(source["provider_id"]), int(source.get("seed", 0))]
	return ""


func _card_size() -> Vector2:
	if collapsed or not _is_content_node():
		return SUMMARY_CARD_SIZE
	match _node_type:
		"ai_generate":
			return GENERATE_CARD_SIZE
		"image_input":
			return REFERENCE_CARD_SIZE
	return CONTENT_CARD_SIZE


func _is_content_node() -> bool:
	return _node_type in ["object_list", "ai_generate", "size_spec", "image_input"]


func _rebuild_content_controls() -> void:
	if _content_root != null:
		remove_child(_content_root)
		_content_root.free()
		_content_root = null
	_object_edit = null
	_provider_option = null
	_batch_size_spin = null
	_seed_spin = null
	_run_button = null
	_cancel_button = null
	_execution_detail_label = null
	_reference_field = null
	if collapsed or not _is_content_node() or _is_ghost:
		return

	_content_root = VBoxContainer.new()
	_content_root.name = "Content"
	_content_root.position = Vector2(PADDING, HEADER_HEIGHT + PADDING)
	_content_root.size = _card_size() - Vector2(PADDING * 2, HEADER_HEIGHT + PADDING * 2)
	_content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_root.add_theme_constant_override("separation", 8)
	add_child(_content_root)
	match _node_type:
		"object_list":
			_build_object_list_controls()
		"ai_generate":
			_build_generate_controls()
		"size_spec":
			_build_size_controls()
		"image_input":
			_build_reference_controls()


func _rebuild_header_controls() -> void:
	if not _is_content_node() or _is_ghost:
		if _collapse_button != null:
			_collapse_button.visible = false
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
	_collapse_button.position = Vector2(_card_size().x - 28, 4)
	_collapse_button.size = Vector2(24, 24)


func _build_object_list_controls() -> void:
	var count_label := Label.new()
	count_label.name = "ItemCount"
	count_label.text = Strings.text("CONTENT_OBJECT_COUNT_FORMAT") % _object_count()
	_content_root.add_child(count_label)
	_object_edit = TextEdit.new()
	_object_edit.name = "ObjectEdit"
	_object_edit.text = String(_params_snapshot.get("items", ""))
	_object_edit.custom_minimum_size = OBJECT_EDITOR_MIN_SIZE
	_object_edit.placeholder_text = Strings.text("CONTENT_OBJECT_PLACEHOLDER")
	_object_edit.focus_exited.connect(_commit_object_items)
	_content_root.add_child(_object_edit)
	var apply_button := Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = Strings.text("ACTION_APPLY")
	apply_button.pressed.connect(_commit_object_items)
	_content_root.add_child(apply_button)


func _build_generate_controls() -> void:
	var provider_row := HBoxContainer.new()
	var provider_label := Label.new()
	provider_label.text = Strings.text("GRAPH_PARAM_PROVIDER")
	provider_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_row.add_child(provider_label)
	_provider_option = OptionButton.new()
	_provider_option.name = "ProviderOption"
	var providers: Array = ProviderService.get_selectable_provider_ids()
	if not providers.has("mock"):
		providers.push_front("mock")
	for provider_id in providers:
		_provider_option.add_item(String(provider_id))
	var provider_index := providers.find(String(_params_snapshot.get("provider_id", "mock")))
	_provider_option.select(maxi(0, provider_index))
	_provider_option.item_selected.connect(func(_index: int) -> void: _commit_generate_params())
	provider_row.add_child(_provider_option)
	_content_root.add_child(provider_row)

	var style_label := Label.new()
	style_label.name = "StyleSummary"
	style_label.text = _project_style_summary()
	style_label.tooltip_text = Strings.text("CONTENT_STYLE_SOURCE_HINT")
	_content_root.add_child(style_label)

	var settings_row := HBoxContainer.new()
	_batch_size_spin = _make_spin("BatchSize", 1, 16, int(_params_snapshot.get("batch_size", 1)))
	_seed_spin = _make_spin("Seed", 0, 2147483647, int(_params_snapshot.get("seed", 1)))
	settings_row.add_child(
		_labeled_control(Strings.text("GRAPH_PARAM_BATCH_SIZE"), _batch_size_spin)
	)
	settings_row.add_child(_labeled_control(Strings.text("GRAPH_PARAM_SEED"), _seed_spin))
	_content_root.add_child(settings_row)

	var action_row := HBoxContainer.new()
	_run_button = Button.new()
	_run_button.name = "RunButton"
	_run_button.text = Strings.text("CONTENT_RUN_GENERATION")
	_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run_button.pressed.connect(
		func() -> void:
			_commit_generate_params()
			action_requested.emit(graph_id, node_id, "run")
	)
	action_row.add_child(_run_button)
	_cancel_button = Button.new()
	_cancel_button.name = "CancelButton"
	_cancel_button.text = Strings.text("CONTENT_CANCEL_GENERATION")
	_cancel_button.pressed.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "cancel")
	)
	action_row.add_child(_cancel_button)
	_content_root.add_child(action_row)
	_execution_detail_label = Label.new()
	_execution_detail_label.name = "ExecutionDetail"
	_execution_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_execution_detail_label.custom_minimum_size.y = 36
	_content_root.add_child(_execution_detail_label)
	_sync_execution_detail()
	_sync_run_controls()


func _build_size_controls() -> void:
	var row := HBoxContainer.new()
	var width := _make_spin("Width", 1, 512, int(_params_snapshot.get("width", 32)))
	var height := _make_spin("Height", 1, 512, int(_params_snapshot.get("height", 32)))
	var count := _make_spin("PerSubject", 1, 16, int(_params_snapshot.get("per_subject", 1)))
	row.add_child(_labeled_control(Strings.text("GRAPH_PARAM_WIDTH"), width))
	row.add_child(_labeled_control(Strings.text("GRAPH_PARAM_HEIGHT"), height))
	row.add_child(_labeled_control(Strings.text("GRAPH_PARAM_PER_SUBJECT"), count))
	_content_root.add_child(row)
	var apply_button := Button.new()
	apply_button.name = "ApplyButton"
	apply_button.text = Strings.text("ACTION_APPLY")
	apply_button.pressed.connect(
		func() -> void:
			params_commit_requested.emit(
				graph_id,
				node_id,
				{
					"width": int(width.value),
					"height": int(height.value),
					"per_subject": int(count.value)
				}
			)
	)
	_content_root.add_child(apply_button)


func _build_reference_controls() -> void:
	var asset_id := String(_params_snapshot.get("asset_id", ""))
	var preview := TextureRect.new()
	preview.name = "ReferencePreview"
	preview.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, 92)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
				"%s · %s"
				% [
					String(meta.get("name", asset_id.left(8))),
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
	_reference_field.value_changed.connect(
		func(value: String) -> void:
			params_commit_requested.emit(graph_id, node_id, {"asset_id": value})
	)
	_reference_field.import_requested.connect(
		func() -> void: action_requested.emit(graph_id, node_id, "import_reference")
	)
	_content_root.add_child(_reference_field)


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


func _commit_object_items() -> void:
	if _object_edit == null:
		return
	var items := _object_edit.text
	if items == String(_params_snapshot.get("items", "")):
		return
	params_commit_requested.emit(graph_id, node_id, {"items": items})


func _commit_generate_params() -> void:
	if _provider_option == null or _batch_size_spin == null or _seed_spin == null:
		return
	(
		params_commit_requested
		. emit(
			graph_id,
			node_id,
			{
				"provider_id": _provider_option.get_item_text(_provider_option.selected),
				"batch_size": int(_batch_size_spin.value),
				"seed": int(_seed_spin.value),
			}
		)
	)


func _object_count() -> int:
	var count := 0
	for raw_line in String(_params_snapshot.get("items", "")).split("\n", false):
		if not String(raw_line).strip_edges().is_empty():
			count += 1
	return count


func _project_style_summary() -> String:
	var style_value: Variant = ProjectService.current_project.manifest.get("style_preset", {})
	if not (style_value is Dictionary) or Dictionary(style_value).is_empty():
		return Strings.text("CONTENT_STYLE_DEFAULT")
	var style: Dictionary = style_value
	var base_size := int(style.get("base_size", 0))
	var palette_value: Variant = style.get("palette", {})
	var palette_ref := ""
	if palette_value is Dictionary:
		palette_ref = String(Dictionary(palette_value).get("ref", ""))
	var detail_parts: Array[String] = []
	if base_size > 0:
		detail_parts.append("%d px" % base_size)
	if not palette_ref.is_empty():
		detail_parts.append(palette_ref)
	if detail_parts.is_empty():
		detail_parts.append(String(style.get("name", Strings.text("CONTENT_STYLE_PROJECT"))))
	return Strings.text("CONTENT_STYLE_SUMMARY_FORMAT") % " · ".join(detail_parts)


func _localized_display_name(node: PFNode) -> String:
	var key_by_type := {
		"object_list": "NODE_OBJECT_LIST",
		"image_input": "NODE_IMAGE_INPUT",
		"size_spec": "NODE_SIZE_SPEC",
		"ai_generate": "NODE_AI_GENERATE",
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
	if _run_button == null or _cancel_button == null:
		return
	var is_running := _execution_status_key == "CONTENT_STATUS_RUNNING"
	_run_button.disabled = is_running
	_cancel_button.visible = is_running


func _sync_execution_detail() -> void:
	if _execution_detail_label == null:
		return
	_execution_detail_label.text = _execution_detail
	_execution_detail_label.visible = not _execution_detail.is_empty()
