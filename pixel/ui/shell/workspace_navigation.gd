class_name PFWorkspaceNavigation
extends PanelContainer

## 画布导航区；缩放仍由既有 overlay 负责，本组件只提供内容聚焦入口。

const Strings := preload("res://ui/shell/strings.gd")

const CONTROL_WIDTH := 360
const CONTROL_HEIGHT := 40
const CONTROL_MARGIN := 12
const CONTENT_GAP := 8
const OVERLAY_Z_INDEX := 4095

var _canvas: Control = null
var _buttons: Array[Button] = []
var _minimap: Control = null


func setup(canvas: Control, minimap: Control = null) -> void:
	_canvas = canvas
	_minimap = minimap
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

	_add_button(row, "FocusSelected", "ACTION_FOCUS_SELECTED", _focus_selected)
	_add_button(row, "FocusAll", "ACTION_FOCUS_ALL", _focus_all)
	_add_button(row, "ToggleMinimap", "ACTION_TOGGLE_MINIMAP", _toggle_minimap)
	LocalizationService.language_changed.connect(_refresh_text)


func _add_button(
	parent: Control, button_name: String, text_key: String, callback: Callable
) -> void:
	var button := Button.new()
	button.name = button_name
	button.text = _navigation_text(text_key)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	button.set_meta("text_key", text_key)
	parent.add_child(button)
	_buttons.append(button)


func _refresh_text(_preference: String, _locale: String) -> void:
	for button in _buttons:
		button.text = _navigation_text(String(button.get_meta("text_key", "")))


func _navigation_text(key: String) -> String:
	match key:
		"ACTION_FOCUS_SELECTED":
			return Strings.text("ACTION_FOCUS_SELECTED")
		"ACTION_FOCUS_ALL":
			return Strings.text("ACTION_FOCUS_ALL")
		_:
			return Strings.text("ACTION_TOGGLE_MINIMAP")


func _focus_selected() -> void:
	if _canvas != null:
		_focus_item_ids(_canvas.get_selected_ids())


func _focus_all() -> void:
	if _canvas != null:
		_focus_item_ids(_canvas._items_by_id.keys())


func _toggle_minimap() -> void:
	if _minimap != null:
		_minimap.visible = not _minimap.visible


func _focus_item_ids(item_ids: Array) -> bool:
	return _canvas._focus_item_ids(item_ids)
