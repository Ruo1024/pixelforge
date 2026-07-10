class_name PFEmptyCanvasImportHint
extends PanelContainer

## 空画布上的低干扰导入入口；只提供最小旅程第一步，不承担完整欢迎页职责。

signal import_requested

const Strings := preload("res://ui/shell/strings.gd")

const HINT_WIDTH := 360
const HINT_HEIGHT := 116
const CONTENT_GAP := 10


func _ready() -> void:
	name = "EmptyCanvasImportHint"
	z_index = 100
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -HINT_WIDTH * 0.5
	offset_top = -HINT_HEIGHT * 0.5
	offset_right = HINT_WIDTH * 0.5
	offset_bottom = HINT_HEIGHT * 0.5

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(content)

	var label := Label.new()
	label.text = Strings.EMPTY_CANVAS_IMPORT_HINT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)

	var button := Button.new()
	button.text = Strings.ACTION_IMPORT_IMAGES
	button.pressed.connect(func() -> void: import_requested.emit())
	content.add_child(button)


func set_canvas_empty(is_empty: bool) -> void:
	visible = is_empty
