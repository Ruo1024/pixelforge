class_name PFCanvasZoomControl
extends PanelContainer

## 画布缩放控件。
## 本组件只负责显示百分比和收集滑条输入；真正的相机缩放仍由 PFInfiniteCanvas 执行。

signal zoom_index_requested(index: int)

const Strings := preload("res://ui/shell/strings.gd")

const CONTROL_WIDTH := 244
const CONTROL_HEIGHT := 36
const LABEL_WIDTH := 54
const SLIDER_WIDTH := 156
const PANEL_RADIUS := 6
const PANEL_PADDING_X := 10
const PANEL_PADDING_Y := 6
const OVERLAY_Z_INDEX := 4095
const ROW_SEPARATION := 8

var _bottom_left_margin := 12
var _level_count := 1
var _slider: HSlider = null
var _label: Label = null
var _syncing := false


func _ready() -> void:
	_build_ui()
	_apply_bottom_left_offsets()
	set_zoom_state(0, 1.0)


func configure_levels(level_count: int) -> void:
	_level_count = maxi(1, level_count)
	if _slider != null:
		_slider.max_value = _level_count - 1
		_slider.tick_count = _level_count


func set_bottom_left_margin(margin: int) -> void:
	_bottom_left_margin = margin
	_apply_bottom_left_offsets()


func get_logical_size() -> Vector2:
	return Vector2(CONTROL_WIDTH, CONTROL_HEIGHT)


func set_zoom_state(index: int, zoom: float) -> void:
	if _label != null:
		_label.text = "%d%%" % int(round(zoom * 100.0))
	if _slider == null:
		return
	_syncing = true
	_slider.value = clampi(index, 0, _level_count - 1)
	_syncing = false


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_as_relative = false
	z_index = OVERLAY_Z_INDEX
	tooltip_text = Strings.ZOOM_CONTROL_TOOLTIP
	custom_minimum_size = get_logical_size()

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.075, 0.08, 0.88)
	background.border_color = Color(0.32, 0.38, 0.38, 0.85)
	background.set_border_width_all(1)
	background.set_corner_radius_all(PANEL_RADIUS)
	background.content_margin_left = PANEL_PADDING_X
	background.content_margin_right = PANEL_PADDING_X
	background.content_margin_top = PANEL_PADDING_Y
	background.content_margin_bottom = PANEL_PADDING_Y
	add_theme_stylebox_override("panel", background)

	var row := HBoxContainer.new()
	row.name = "ZoomRow"
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	add_child(row)

	_label = Label.new()
	_label.name = "ZoomLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	row.add_child(_label)

	_slider = HSlider.new()
	_slider.name = "ZoomSlider"
	_slider.min_value = 0
	_slider.max_value = _level_count - 1
	_slider.step = 1
	_slider.rounded = true
	_slider.tick_count = _level_count
	_slider.ticks_on_borders = true
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 0)
	_slider.tooltip_text = Strings.ZOOM_CONTROL_TOOLTIP
	_slider.value_changed.connect(_on_slider_value_changed)
	row.add_child(_slider)


func _on_slider_value_changed(value: float) -> void:
	if _syncing:
		return
	zoom_index_requested.emit(clampi(int(round(value)), 0, _level_count - 1))


func _apply_bottom_left_offsets() -> void:
	var margin := _bottom_left_margin
	var control_size := get_logical_size()
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = margin
	offset_top = -control_size.y - margin
	offset_right = margin + control_size.x
	offset_bottom = -margin
