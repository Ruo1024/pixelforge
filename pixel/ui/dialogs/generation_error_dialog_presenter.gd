class_name PFGenerationErrorDialogPresenter
extends Node

## Renders one safe terminal generation summary per run. The run controller owns wiring only.

signal action_requested(run_id: String, action_id: String, context: Dictionary)
signal dialog_closed(run_id: String)

const PolicyScript := preload("res://services/generation_error_dialog_policy.gd")

const DIALOG_SIZE := Vector2i(560, 440)
const CONTENT_MARGIN := 16
const SECTION_GAP := 10

var _policy := PolicyScript.new()
var _dialog: Window = null
var _reason_label: Label = null
var _affected_label: Label = null
var _next_step_label: Label = null
var _primary_button: Button = null
var _close_button: Button = null
var _technical_toggle: Button = null
var _technical_body: VBoxContainer = null
var _codes_label: Label = null
var _providers_label: Label = null
var _request_ids_label: Label = null
var _active_run_id := ""
var _active_model := {}
var _presented_count := 0


func _ready() -> void:
	_ensure_built()


func present(summary: Dictionary) -> Dictionary:
	_ensure_built()
	var decision: Dictionary = _policy.evaluate(summary)
	if not bool(decision.get("show", false)):
		return decision
	_active_run_id = String(summary.get("run_id", ""))
	_active_model = Dictionary(decision.get("model", {})).duplicate(true)
	_presented_count += 1
	_technical_toggle.set_pressed_no_signal(false)
	_technical_body.visible = false
	_refresh_text()
	_dialog.popup_centered(DIALOG_SIZE)
	return decision


func dismiss() -> void:
	_close_dialog()


func get_dialog() -> Window:
	_ensure_built()
	return _dialog


func get_presented_count() -> int:
	return _presented_count


func get_active_model_for_test() -> Dictionary:
	return _active_model.duplicate(true)


func visible_text_for_test() -> String:
	_ensure_built()
	var values := PackedStringArray([_dialog.title])
	_collect_control_text(_dialog, values)
	return "\n".join(values)


func _ensure_built() -> void:
	if _dialog != null:
		return
	_dialog = Window.new()
	_dialog.name = "GenerationErrorDialog"
	_dialog.exclusive = true
	_dialog.transient = true
	_dialog.min_size = DIALOG_SIZE
	_dialog.visible = false
	_dialog.close_requested.connect(_close_dialog)
	add_child(_dialog)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_top", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_right", CONTENT_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CONTENT_MARGIN)
	_dialog.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", SECTION_GAP)
	margin.add_child(root)

	_reason_label = _paragraph("GenerationErrorReason")
	root.add_child(_reason_label)
	_affected_label = _paragraph("GenerationErrorAffectedCount")
	root.add_child(_affected_label)
	_next_step_label = _paragraph("GenerationErrorNextStep")
	root.add_child(_next_step_label)

	_technical_toggle = Button.new()
	_technical_toggle.name = "GenerationErrorTechnicalToggle"
	_technical_toggle.toggle_mode = true
	_technical_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_technical_toggle.toggled.connect(func(open: bool) -> void: _technical_body.visible = open)
	root.add_child(_technical_toggle)
	_technical_body = VBoxContainer.new()
	_technical_body.name = "GenerationErrorTechnicalBody"
	_technical_body.visible = false
	_codes_label = _paragraph("GenerationErrorTechnicalCodes")
	_providers_label = _paragraph("GenerationErrorTechnicalProviders")
	_request_ids_label = _paragraph("GenerationErrorTechnicalRequestIds")
	_technical_body.add_child(_codes_label)
	_technical_body.add_child(_providers_label)
	_technical_body.add_child(_request_ids_label)
	root.add_child(_technical_body)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	_primary_button = Button.new()
	_primary_button.name = "GenerationErrorPrimaryAction"
	_primary_button.pressed.connect(_route_primary_action)
	actions.add_child(_primary_button)
	_close_button = Button.new()
	_close_button.name = "GenerationErrorClose"
	_close_button.pressed.connect(_close_dialog)
	actions.add_child(_close_button)
	root.add_child(actions)
	LocalizationService.language_changed.connect(_on_language_changed)


func _paragraph(control_name: String) -> Label:
	var label := Label.new()
	label.name = control_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _refresh_text() -> void:
	if _active_model.is_empty():
		return
	var rendered: Dictionary = _policy.render(_active_model, LocalizationService.current_locale)
	_dialog.title = String(rendered.get("title", ""))
	_reason_label.text = String(rendered.get("reason", ""))
	_affected_label.text = LocalizationService.text(
		"GEN_ERROR_AFFECTED_COUNT_FORMAT", [int(rendered.get("affected_count", 0))]
	)
	_next_step_label.text = LocalizationService.text(
		"GEN_ERROR_NEXT_STEP_FORMAT", [String(rendered.get("next_step", ""))]
	)
	var primary: Dictionary = rendered.get("primary_action", {})
	_primary_button.text = String(primary.get("label", ""))
	_close_button.text = String(rendered.get("close", ""))
	_technical_toggle.text = LocalizationService.text("GEN_ERROR_TECHNICAL_DETAILS")
	var details: Dictionary = rendered.get("technical_details", {})
	_codes_label.text = LocalizationService.text(
		"GEN_ERROR_TECHNICAL_CODES_FORMAT", [_joined(details.get("codes", []))]
	)
	_providers_label.text = LocalizationService.text(
		"GEN_ERROR_TECHNICAL_PROVIDERS_FORMAT", [_joined(details.get("providers", []))]
	)
	_request_ids_label.text = LocalizationService.text(
		"GEN_ERROR_TECHNICAL_REQUESTS_FORMAT", [_joined(details.get("request_ids", []))]
	)


func _route_primary_action() -> void:
	if _active_run_id.is_empty() or _active_model.is_empty():
		return
	var action_id := String(_active_model.get("primary_action_id", "close"))
	var context := {
		"requires_confirmation": action_id == "regenerate_confirm",
		"retry_slot_ids": PackedStringArray(_active_model.get("retry_slot_ids", [])),
	}
	action_requested.emit(_active_run_id, action_id, context)
	_dialog.hide()


func _close_dialog() -> void:
	if _dialog == null:
		return
	_dialog.hide()
	if not _active_run_id.is_empty():
		dialog_closed.emit(_active_run_id)


func _on_language_changed(_preference: String, _locale: String) -> void:
	_refresh_text()


func _joined(value: Variant) -> String:
	var values := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for item in value:
			values.append(String(item))
	return (
		LocalizationService.text("GEN_ERROR_TECHNICAL_NONE")
		if values.is_empty()
		else ", ".join(values)
	)


func _collect_control_text(node: Node, values: PackedStringArray) -> void:
	if node is Label or node is Button:
		values.append(String(node.text))
	for child in node.get_children():
		_collect_control_text(child, values)
