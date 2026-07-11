class_name PFEmptyCanvasImportHint
extends PanelContainer

## 空画布上的首步入口；实际动作由 shell controller 接入真实服务。

signal import_requested
signal add_input_requested
signal import_reference_requested
signal open_example_requested

const Strings := preload("res://ui/shell/strings.gd")

const HINT_WIDTH := 560
const HINT_HEIGHT := 144
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
	content.name = "EmptyContent"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(content)

	var label := Label.new()
	label.name = "HintLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)

	var actions := HBoxContainer.new()
	actions.name = "EmptyActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", CONTENT_GAP)
	content.add_child(actions)

	_add_action(actions, "AddInput", "ACTION_ADD_INPUT", add_input_requested.emit)
	_add_action(
		actions,
		"ImportReference",
		"ACTION_IMPORT_REFERENCE",
		func() -> void:
			import_reference_requested.emit()
			import_requested.emit()
	)
	_add_action(actions, "OpenExample", "ACTION_OPEN_EXAMPLE", open_example_requested.emit)
	LocalizationService.language_changed.connect(_refresh_text)
	_refresh_text("", "")


func set_canvas_empty(is_empty: bool) -> void:
	visible = is_empty


func _add_action(
	parent: Control, button_name: String, text_key: String, callback: Callable
) -> void:
	var button := Button.new()
	button.name = button_name
	button.set_meta("text_key", text_key)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _refresh_text(_preference: String, _locale: String) -> void:
	get_node("EmptyContent/HintLabel").text = Strings.text("EMPTY_CANVAS_IMPORT_HINT")
	for button in get_node("EmptyContent/EmptyActions").get_children():
		button.text = Strings.text(String(button.get_meta("text_key", "")))
