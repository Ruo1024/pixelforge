class_name PFOutputSelectionToolbar
extends HBoxContainer

## Ephemeral succeeded-slot selection actions. No selection is persisted to Graph or canvas data.

signal action_requested(action_id: String, slot_id: String)

const Strings := preload("res://ui/shell/strings.gd")
const ACTIONS := [
	["preview", "OUTPUT_ACTION_PREVIEW", "Preview"],
	["edit", "OUTPUT_ACTION_EDIT", "Edit"],
	["detach", "OUTPUT_ACTION_DETACH", "Detach"],
	["download", "OUTPUT_ACTION_DOWNLOAD", "Download"],
]

var selected_slot_id := ""


func _ready() -> void:
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_build()
	visible = false


func select_slot(slot: Dictionary, busy: bool = false) -> void:
	if (
		String(slot.get("status", "")) != "succeeded"
		or bool(slot.get("detached", false))
		or String(slot.get("asset_id", "")).is_empty()
	):
		clear_selection()
		return
	selected_slot_id = String(slot.get("slot_id", ""))
	visible = not selected_slot_id.is_empty()
	get_node("Edit").disabled = busy
	get_node("Detach").disabled = busy
	get_node("Edit").tooltip_text = Strings.text("OUTPUT_BUSY_HINT") if busy else ""
	get_node("Detach").tooltip_text = Strings.text("OUTPUT_BUSY_HINT") if busy else ""


func clear_selection() -> void:
	selected_slot_id = ""
	visible = false


func pointer_cancel() -> void:
	clear_selection()


func action_ids() -> Array[String]:
	var result: Array[String] = []
	for spec in ACTIONS:
		result.append(String(spec[0]))
	return result


func _build() -> void:
	for child in get_children():
		child.free()
	for spec in ACTIONS:
		var button := Button.new()
		button.name = String(spec[2])
		button.text = _action_text(String(spec[0]))
		var action_id := String(spec[0])
		button.pressed.connect(func() -> void: action_requested.emit(action_id, selected_slot_id))
		add_child(button)


func _on_language_changed(_preference: String, _locale: String) -> void:
	_build()


func _action_text(action_id: String) -> String:
	match action_id:
		"preview":
			return Strings.text("OUTPUT_ACTION_PREVIEW")
		"edit":
			return Strings.text("OUTPUT_ACTION_EDIT")
		"detach":
			return Strings.text("OUTPUT_ACTION_DETACH")
		_:
			return Strings.text("OUTPUT_ACTION_DOWNLOAD")
