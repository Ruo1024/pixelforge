class_name PFCanvasItemFrame
extends Node2D

## 显式阶段组的持久化与背景渲染。
## contract: PROJECT-FORMAT §4；成员只由 node.frame_id 表达，frame 不保存成员数组。

signal display_title_change_requested(item_id: String, display_title: String)
signal size_change_requested(item_id: String, requested_size: Vector2i)

const DEFAULT_SIZE := Vector2(320, 240)
const DEFAULT_COLOR := Color(0.31, 0.44, 0.56, 1.0)
const UIFont := preload("res://ui/widgets/ui_font.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")
const Strings := preload("res://ui/shell/strings.gd")

const MIN_SIZE := Vector2i(320, 240)
const MAX_SIZE := Vector2i(32768, 32768)

var item_id := ""
var graph_id := ""
var title := ""
var display_title := ""
var requested_size := Vector2i(DEFAULT_SIZE)
var collapsed := false
var frame_color := DEFAULT_COLOR
var locked := false
var _raw_data := {}
var _lod_camera_zoom := 1.0
var _title_button: Button = null
var _title_edit: LineEdit = null


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", ""))
	graph_id = String(data.get("graph_id", ""))
	title = CardContract.normalize_display_title(data.get("title", ""))
	display_title = title
	frame_color = Color.from_string(String(data.get("color", "4f6f8fff")), DEFAULT_COLOR)
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	var raw_size: Variant = data.get("size", [DEFAULT_SIZE.x, DEFAULT_SIZE.y])
	set_requested_size(raw_size)
	z_index = int(data.get("z_index", -1))
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_rebuild_title_control()
	queue_redraw()


func to_canvas_data() -> Dictionary:
	var result := _raw_data.duplicate(true)
	result["id"] = item_id
	result["type"] = "frame"
	result["graph_id"] = graph_id
	result["title"] = title
	result["color"] = frame_color.to_html()
	result["position"] = [int(round(position.x)), int(round(position.y))]
	result["size"] = [requested_size.x, requested_size.y]
	result["z_index"] = z_index
	result.erase("member_ids")
	return result


func get_canvas_bounds() -> Rect2:
	return Rect2(position, Vector2(requested_size))


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func set_requested_size(value: Variant) -> void:
	var values: Array = value if value is Array and value.size() == 2 else []
	if value is Vector2i:
		values = [value.x, value.y]
	elif value is Vector2:
		values = [value.x, value.y]
	if values.size() != 2:
		requested_size = MIN_SIZE
	else:
		requested_size = Vector2i(
			clampi(int(round(float(values[0]))), MIN_SIZE.x, MAX_SIZE.x),
			clampi(int(round(float(values[1]))), MIN_SIZE.y, MAX_SIZE.y)
		)
	_rebuild_title_control()
	queue_redraw()


func set_display_title(value: Variant) -> void:
	title = CardContract.normalize_display_title(value)
	display_title = title
	_rebuild_title_control()
	queue_redraw()


func set_lod_camera_zoom(value: float) -> void:
	_lod_camera_zoom = maxf(0.0, value)
	_rebuild_title_control()
	queue_redraw()


func resize_handle_contains_world(world_position: Vector2) -> bool:
	if locked or _lod_camera_zoom < 0.75:
		return false
	var hit_world := 16.0 / maxf(_lod_camera_zoom, 0.01)
	var local := world_position - position
	return (
		Rect2(Vector2(requested_size) - Vector2.ONE * hit_world, Vector2.ONE * hit_world)
		. has_point(local)
	)


func _draw() -> void:
	var local_rect := Rect2(Vector2.ZERO, Vector2(requested_size))
	draw_rect(local_rect, Color(frame_color, 0.12), true)
	draw_rect(local_rect, Color(frame_color, 0.82), false, 2.0)
	var font: Font = UIFont.get_font()
	if font != null and _lod_camera_zoom >= 0.25:
		draw_string(
			font,
			Vector2(12, 24),
			_visible_title(),
			HORIZONTAL_ALIGNMENT_LEFT,
			maxf(0.0, requested_size.x - 24.0),
			16,
			Color(frame_color, 1.0)
		)
	if not locked and _lod_camera_zoom >= 0.75:
		var end := Vector2(requested_size) - Vector2(4, 4)
		draw_line(end - Vector2(8, 0), end, AppTheme.TEXT_MUTED, 2.0)
		draw_line(end - Vector2(0, 8), end, AppTheme.TEXT_MUTED, 2.0)


func _rebuild_title_control() -> void:
	if _title_button == null:
		_title_button = Button.new()
		_title_button.name = "TitleButton"
		_title_button.flat = true
		_title_button.focus_mode = Control.FOCUS_NONE
		_title_button.gui_input.connect(_on_title_input)
		add_child(_title_button)
	_title_button.position = Vector2(8, 2)
	_title_button.size = Vector2(maxf(48.0, requested_size.x - 16.0), 34)
	_title_button.tooltip_text = _visible_title()
	_title_button.visible = not locked and _lod_camera_zoom >= 0.75


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		_begin_title_edit()


func _begin_title_edit() -> void:
	if locked or _lod_camera_zoom < 0.75:
		return
	if _title_edit == null:
		_title_edit = LineEdit.new()
		_title_edit.name = "TitleEdit"
		_title_edit.text_submitted.connect(func(_value: String) -> void: _commit_title())
		_title_edit.focus_exited.connect(_commit_title)
		_title_edit.gui_input.connect(_on_title_edit_input)
		add_child(_title_edit)
	_title_edit.position = Vector2(12, 4)
	_title_edit.size = Vector2(maxf(80.0, requested_size.x - 24.0), 30)
	_title_edit.text = _visible_title()
	_title_edit.visible = true
	_title_edit.grab_focus()
	_title_edit.select_all()


func _on_title_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_title_edit.visible = false
		get_viewport().set_input_as_handled()


func _commit_title() -> void:
	if _title_edit == null or not _title_edit.visible:
		return
	var next_title := CardContract.normalize_display_title(_title_edit.text)
	_title_edit.visible = false
	if next_title != title:
		display_title_change_requested.emit(item_id, next_title)


func _visible_title() -> String:
	return title if not title.is_empty() else Strings.text("FRAME_DEFAULT_TITLE")


func _on_language_changed(_preference: String, _locale: String) -> void:
	_rebuild_title_control()
	queue_redraw()
