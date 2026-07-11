class_name PFWorkspaceNavigation
extends PanelContainer

## 画布导航区；缩放仍由既有 overlay 负责，本组件只提供内容聚焦入口。

const Strings := preload("res://ui/shell/strings.gd")

const CONTROL_WIDTH := 258
const CONTROL_HEIGHT := 40
const CONTROL_MARGIN := 12
const CONTENT_GAP := 8
const OVERLAY_Z_INDEX := 4095

var _canvas: Control = null


func setup(canvas: Control) -> void:
	_canvas = canvas
	name = "WorkspaceNavigation"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = OVERLAY_Z_INDEX
	custom_minimum_size = Vector2(CONTROL_WIDTH, CONTROL_HEIGHT)
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -CONTROL_WIDTH - CONTROL_MARGIN
	offset_top = -CONTROL_HEIGHT - CONTROL_MARGIN
	offset_right = -CONTROL_MARGIN
	offset_bottom = -CONTROL_MARGIN

	var row := HBoxContainer.new()
	row.name = "NavigationRow"
	row.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(row)

	_add_button(row, "FocusSelected", Strings.ACTION_FOCUS_SELECTED, _focus_selected)
	_add_button(row, "FocusAll", Strings.ACTION_FOCUS_ALL, _focus_all)


func _add_button(parent: Control, button_name: String, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _focus_selected() -> void:
	if _canvas != null:
		_focus_item_ids(_canvas.get_selected_ids())


func _focus_all() -> void:
	if _canvas != null:
		_focus_item_ids(_canvas._items_by_id.keys())


func _focus_item_ids(item_ids: Array) -> bool:
	var bounds := Rect2()
	var has_bounds := false
	for raw_id in item_ids:
		var item: Node = _canvas._items_by_id.get(String(raw_id), null)
		if item == null or not item.has_method("get_canvas_bounds"):
			continue
		var item_bounds: Rect2 = item.get_canvas_bounds()
		bounds = item_bounds if not has_bounds else bounds.merge(item_bounds)
		has_bounds = true
	if (
		not has_bounds
		or bounds.size.x <= 0.0
		or bounds.size.y <= 0.0
		or _canvas.size.is_zero_approx()
	):
		return false
	var target_zoom := minf(
		_canvas.size.x * 0.72 / bounds.size.x, _canvas.size.y * 0.72 / bounds.size.y
	)
	_canvas.set_camera_zoom(target_zoom, _canvas.size * 0.5)
	_canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)
	return true
