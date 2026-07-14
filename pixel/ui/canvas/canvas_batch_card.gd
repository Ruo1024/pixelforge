class_name PFCanvasBatchCard
extends Node2D

## Graph-bound Output card host. Output truth stays in the batch node result_slots.

signal collapsed_change_requested(item_id: String, collapsed: bool)
signal run_action_requested(graph_id: String, node_id: String, action_id: String)
signal display_title_change_requested(item_id: String, display_title: String)
signal size_change_requested(item_id: String, requested_size: Vector2i)
signal output_action_requested(item_id: String, action_id: String, slot_id: String)

const IdUtil := preload("res://core/util/id_util.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const OutputCardControllerScript := preload("res://ui/canvas/output_card_controller.gd")
const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")

const INPUT_PORTS: Array[String] = ["in"]
const OUTPUT_PORTS: Array[String] = ["assets"]
const PORT_HIT_SCREEN_RADIUS := 20.0

var item_id := ""
var graph_id := ""
var node_id := ""
var asset_ids: Array[String] = []
var label := "Output"
var locked := false
var collapsed := false
var frame_id: Variant = null
var display_title := ""
var requested_size := Vector2i(600, 240)

var _raw_data := {}
var _params := {}
var _lod_camera_zoom := 1.0
var _controller: PFOutputCardController = null
var _collapse_button: Button = null
var _title_button: Button = null
var _title_edit: LineEdit = null
var _more_button: MenuButton = null


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	locked = bool(data.get("locked", false))
	collapsed = bool(data.get("collapsed", false))
	frame_id = data.get("frame_id", null)
	display_title = CardContract.normalize_display_title(data.get("display_title", ""))
	requested_size = CardContract.normalize_requested_size("batch", data.get("size", null))
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh_from_graph()


func _refresh_from_graph() -> void:
	_params = _resolve_params()
	label = String(_params.get("label", "Output"))
	asset_ids = BatchNodeScript.get_visible_asset_ids(_params)
	_rebuild_controller()
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
	for key in ["asset_ids", "selected_asset_ids", "label", "run_state"]:
		result.erase(key)
	return result


func has_graph_binding() -> bool:
	return not graph_id.is_empty() and not node_id.is_empty()


func get_canvas_bounds() -> Rect2:
	return Rect2(position, Vector2(requested_size.x, _card_height()))


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func get_requested_size() -> Vector2i:
	return requested_size


func set_requested_size(value: Variant) -> void:
	requested_size = CardContract.normalize_requested_size("batch", value)
	requested_size.x = LayoutScript.clamp_output_width(requested_size.x)
	_rebuild_controller()
	_rebuild_header_controls()
	queue_redraw()


func default_requested_size() -> Vector2i:
	return Vector2i(600, LayoutScript.natural_height(600, asset_ids.size()))


func set_display_title(value: Variant) -> void:
	display_title = CardContract.normalize_display_title(value)
	_rebuild_controller()
	queue_redraw()


func set_lod_camera_zoom(value: float) -> void:
	_lod_camera_zoom = maxf(0.0, value)
	if _controller != null:
		_controller.visible = not collapsed and _lod_camera_zoom >= 0.25
	_rebuild_header_controls()
	queue_redraw()


func _set_collapsed(value: bool) -> void:
	collapsed = value
	_rebuild_controller()
	_rebuild_header_controls()
	queue_redraw()


func get_visible_asset_ids() -> Array[String]:
	return asset_ids.duplicate()


func get_selected_asset_ids() -> Array[String]:
	if _controller == null:
		var empty: Array[String] = []
		return empty
	var asset_id := _controller.selected_asset_id()
	var result: Array[String] = []
	if not asset_id.is_empty():
		result.append(asset_id)
	return result


func get_selected_slot_id() -> String:
	return "" if _controller == null else _controller.selected_slot_id()


func _set_selected_asset_ids(values: Array) -> void:
	if _controller == null:
		return
	_controller.select_slot("")
	if values.is_empty():
		return
	for slot in _controller.visible_slots():
		if String(slot.get("asset_id", "")) == String(values[0]):
			_controller.select_slot(String(slot.get("slot_id", "")))
			return


func get_selected_or_all_asset_ids() -> Array[String]:
	var selected := get_selected_asset_ids()
	return asset_ids.duplicate() if selected.is_empty() else selected


func asset_index_at_world(world_position: Vector2) -> int:
	if _controller == null or collapsed:
		return -1
	var grid := _controller.get_node_or_null("SlotGrid") as Control
	if grid == null:
		return -1
	var slot_id: String = grid.slot_id_at(world_position - position - grid.position)
	for index in range(_controller.visible_slots().size()):
		if String(_controller.visible_slots()[index].get("slot_id", "")) == slot_id:
			return index
	return -1


func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
	var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
	var index := maxi(0, ports.find(port_name))
	return position + _graph_port_position(index, ports.size(), is_input)


func _graph_port_at_world(world_position: Vector2) -> Dictionary:
	if _lod_camera_zoom < 0.75:
		return {}
	for is_input in [true, false]:
		var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
		for index in range(ports.size()):
			var anchor := position + _graph_port_position(index, ports.size(), is_input)
			if anchor.distance_to(world_position) <= PORT_HIT_SCREEN_RADIUS / _lod_camera_zoom:
				return {"port_name": ports[index], "is_input": is_input, "port_index": index}
	return {}


func resize_handle_contains_world(world_position: Vector2) -> bool:
	if locked or _lod_camera_zoom < 0.75:
		return false
	var hit_world := 16.0 / maxf(_lod_camera_zoom, 0.01)
	return Rect2(
		Vector2(requested_size.x, _card_height()) - Vector2.ONE * hit_world,
		Vector2.ONE * hit_world
	).has_point(world_position - position)


func begin_title_edit() -> void:
	if locked or _lod_camera_zoom < 0.75:
		return
	if _title_edit == null:
		_title_edit = LineEdit.new()
		_title_edit.name = "TitleEdit"
		_title_edit.text_submitted.connect(func(_value: String) -> void: _commit_title_edit())
		_title_edit.focus_exited.connect(_commit_title_edit)
		add_child(_title_edit)
	_title_edit.position = Vector2(16, 2)
	_title_edit.size = Vector2(maxf(64.0, requested_size.x - 120.0), 28)
	_title_edit.text = display_title if not display_title.is_empty() else String(_params.get("label", "Output"))
	_title_edit.visible = true
	_title_edit.grab_focus()
	_title_edit.select_all()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(requested_size.x, _card_height()))
	draw_rect(rect, AppTheme.CARD, true)
	draw_rect(rect, AppTheme.BORDER, false, 1.0)
	if locked or _lod_camera_zoom < 0.75:
		return
	var end := Vector2(requested_size.x, _card_height()) - Vector2(4, 4)
	draw_line(end - Vector2(8, 0), end, AppTheme.TEXT_MUTED, 2.0)
	draw_line(end - Vector2(0, 8), end, AppTheme.TEXT_MUTED, 2.0)


func _rebuild_controller() -> void:
	if _controller == null:
		_controller = OutputCardControllerScript.new()
		_controller.name = "OutputCardController"
		_controller.action_requested.connect(_on_output_action)
		add_child(_controller)
	_controller.position = Vector2.ZERO
	_controller.size = Vector2(requested_size.x, _card_height())
	_controller.visible = not collapsed and _lod_camera_zoom >= 0.25
	_controller.configure(
		{
			"title": display_title if not display_title.is_empty() else String(_params.get("label", "Output")),
			"role": String(_params.get("role", "current")),
			"state": _display_state(),
			"source_node_id": String(_params.get("source_node_id", "")),
			"result_slots": _params.get("result_slots", []),
		}
	)


func _rebuild_header_controls() -> void:
	if _collapse_button == null:
		_collapse_button = Button.new()
		_collapse_button.name = "CollapseButton"
		_collapse_button.pressed.connect(
			func() -> void: collapsed_change_requested.emit(item_id, not collapsed)
		)
		add_child(_collapse_button)
	_collapse_button.text = "+" if collapsed else "−"
	_collapse_button.position = Vector2(requested_size.x - 64, 4)
	_collapse_button.size = Vector2(24, 24)
	_collapse_button.visible = _lod_camera_zoom >= 0.75
	if _title_button == null:
		_title_button = Button.new()
		_title_button.name = "TitleButton"
		_title_button.flat = true
		_title_button.gui_input.connect(_on_title_input)
		add_child(_title_button)
	_title_button.position = Vector2(8, 2)
	_title_button.size = Vector2(maxf(48, requested_size.x - 116), 28)
	_title_button.visible = not locked and _lod_camera_zoom >= 0.75
	if _more_button == null:
		_more_button = MenuButton.new()
		_more_button.name = "MoreButton"
		_more_button.text = "..."
		_more_button.get_popup().add_item("Rename", 1)
		_more_button.get_popup().add_item("Reset size", 2)
		_more_button.get_popup().id_pressed.connect(_on_more_action)
		add_child(_more_button)
	_more_button.position = Vector2(requested_size.x - 36, 4)
	_more_button.size = Vector2(28, 24)
	_more_button.visible = not locked and _lod_camera_zoom >= 0.75


func _on_output_action(action_id: String, slot_id: String) -> void:
	output_action_requested.emit(item_id, action_id, slot_id)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		begin_title_edit()


func _commit_title_edit() -> void:
	if _title_edit == null or not _title_edit.visible:
		return
	var value := CardContract.normalize_display_title(_title_edit.text)
	_title_edit.visible = false
	if value != display_title:
		display_title_change_requested.emit(item_id, value)


func _on_more_action(action_id: int) -> void:
	if action_id == 1:
		begin_title_edit()
	elif action_id == 2:
		size_change_requested.emit(item_id, default_requested_size())


func _resolve_params() -> Dictionary:
	if not has_graph_binding():
		return {}
	for value in ProjectService.get_graph_data(graph_id).get("nodes", []):
		if value is Dictionary and String(value.get("id", "")) == node_id:
			return Dictionary(value.get("params", {})).duplicate(true)
	return {}


func _display_state() -> String:
	var statuses := []
	for value in _params.get("result_slots", []):
		if value is Dictionary:
			statuses.append(String(value.get("status", "")))
	if statuses.any(func(status: String) -> bool: return status == "running"):
		return "Running"
	if statuses.any(func(status: String) -> bool: return status == "queued"):
		return "Queued"
	return "Ready" if statuses.is_empty() else "Complete"


func _card_height() -> int:
	if collapsed:
		return CardContract.COLLAPSED_HEIGHT
	return maxi(requested_size.y, LayoutScript.natural_height(requested_size.x, asset_ids.size()))


func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
	var y := float(_card_height()) * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else requested_size.x, y)
