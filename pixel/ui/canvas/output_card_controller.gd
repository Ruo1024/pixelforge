class_name PFOutputCardController
extends Control

## Output-only UI coordinator. It consumes slots/history and emits commands without domain writes.

signal action_requested(action_id: String, slot_id: String)

const Strings := preload("res://ui/shell/strings.gd")
const GridScript := preload("res://ui/canvas/output_slot_grid.gd")
const ToolbarScript := preload("res://ui/canvas/output_selection_toolbar.gd")
const LayoutScript := preload("res://ui/canvas/output_layout_calculator.gd")

const TOP_RAIL_IDS: Array[String] = ["title", "count", "state", "download", "detach_all", "port"]
const BUSY_STATES := ["Queued", "Running", "Canceling"]

var _output := {}
var _grid: Control = null
var _toolbar: Control = null


func _ready() -> void:
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_rebuild()


func configure(output: Dictionary) -> void:
	_output = output.duplicate(true)
	_rebuild()


func selected_slot_id() -> String:
	return "" if _toolbar == null else String(_toolbar.selected_slot_id)


func selected_asset_id() -> String:
	return String(_slot(selected_slot_id()).get("asset_id", ""))


func select_slot(slot_id: String) -> void:
	if _toolbar == null:
		return
	_toolbar.select_slot(_slot(slot_id), _is_busy())


func visible_slots() -> Array[Dictionary]:
	return _visible_slots()


func tile_states() -> Array[String]:
	var result: Array[String] = []
	for slot in _visible_slots():
		result.append(String(slot.get("status", "")))
	return result


func empty_reason() -> String:
	var slots: Array = _output.get("result_slots", [])
	if slots.is_empty():
		return "not_run" if not String(_output.get("source_node_id", "")).is_empty() else "empty"
	if _visible_slots().is_empty():
		return "detached"
	return ""


func top_rail_ids() -> Array[String]:
	return TOP_RAIL_IDS.duplicate()


func is_action_allowed(action_id: String, slot_id: String) -> bool:
	var slot := _slot(slot_id)
	if slot.is_empty() or String(slot.get("status", "")) != "succeeded":
		return false
	if action_id in ["preview", "download"]:
		return true
	if action_id in ["edit", "detach"]:
		return String(_output.get("state", "Ready")) not in BUSY_STATES
	return false


static func retry_visible(context: Dictionary) -> bool:
	var error: Dictionary = context.get("error", {})
	return (
		bool(error.get("retryable", false))
		and int(context.get("wait_seconds", 0)) <= 0
		and String(context.get("role", "")) in ["current", "history"]
		and not String(context.get("source_node_id", "")).is_empty()
		and bool(context.get("source_exists", false))
		and bool(context.get("source_type_matches", false))
		and bool(context.get("snapshot_valid", false))
	)


func _rebuild() -> void:
	for child in get_children():
		child.free()
	if not is_inside_tree():
		return
	_build_top_rail()
	_grid = GridScript.new()
	_grid.name = "SlotGrid"
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.offset_top = 48
	_grid.offset_bottom = -16
	add_child(_grid)
	_grid.configure(_output.get("result_slots", []))
	_grid.slot_pressed.connect(select_slot)
	_toolbar = ToolbarScript.new()
	_toolbar.name = "SelectionToolbar"
	_toolbar.position = Vector2(16, -40)
	_toolbar.action_requested.connect(
		func(action_id: String, slot_id: String) -> void: action_requested.emit(action_id, slot_id)
	)
	add_child(_toolbar)
	if not empty_reason().is_empty():
		var empty := Label.new()
		empty.name = "EmptyState"
		empty.text = Strings.text(_empty_key(empty_reason()))
		empty.position = Vector2(16, 72)
		add_child(empty)


func _build_top_rail() -> void:
	var rail := HBoxContainer.new()
	rail.name = "TopRail"
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rail.offset_bottom = 32
	add_child(rail)
	var title := Label.new()
	title.name = "Title"
	title.text = String(_output.get("title", Strings.text("OUTPUT_TITLE")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(title)
	var slots: Array = _output.get("result_slots", [])
	var succeeded := 0
	for slot in slots:
		if slot is Dictionary and String(slot.get("status", "")) == "succeeded":
			succeeded += 1
	var count := Label.new()
	count.name = "Count"
	count.text = "%d / %d" % [succeeded, slots.size()]
	rail.add_child(count)
	var state := Label.new()
	state.name = "State"
	var state_text := Strings.text(_state_key(String(_output.get("state", "Ready"))))
	if String(_output.get("role", "current")) == "history":
		state_text = "%s · %s" % [Strings.text("OUTPUT_HISTORY"), state_text]
	state.text = state_text
	rail.add_child(state)
	for spec in [
		["Download", "OUTPUT_ACTION_DOWNLOAD_ALL", "download"],
		["DetachAll", "OUTPUT_ACTION_DETACH_ALL", "detach_all"],
	]:
		var button := Button.new()
		button.name = String(spec[0])
		button.text = Strings.text(String(spec[1]))
		button.disabled = String(spec[2]) == "detach_all" and _is_busy()
		var action_id := String(spec[2])
		button.pressed.connect(func() -> void: action_requested.emit(action_id, ""))
		rail.add_child(button)
	var port := Control.new()
	port.name = "Port"
	port.custom_minimum_size = Vector2.ONE * LayoutScript.HORIZONTAL_PADDING
	rail.add_child(port)


func _visible_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_value in _output.get("result_slots", []):
		if slot_value is Dictionary and not bool(slot_value.get("detached", false)):
			result.append(Dictionary(slot_value).duplicate(true))
	return result


func _slot(slot_id: String) -> Dictionary:
	for slot in _output.get("result_slots", []):
		if slot is Dictionary and String(slot.get("slot_id", "")) == slot_id:
			return slot
	return {}


func _is_busy() -> bool:
	return String(_output.get("state", "Ready")) in BUSY_STATES


func _state_key(state: String) -> String:
	return "OUTPUT_STATE_%s" % state.to_upper()


func _empty_key(reason: String) -> String:
	return (
		{
			"not_run": "OUTPUT_EMPTY_NOT_RUN",
			"empty": "OUTPUT_EMPTY_NONE",
			"detached": "OUTPUT_EMPTY_DETACHED",
		}
		. get(reason, "OUTPUT_EMPTY_NONE")
	)


func _on_language_changed(_preference: String, _locale: String) -> void:
	_rebuild()
