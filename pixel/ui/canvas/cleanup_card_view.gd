class_name PFCleanupCardView
extends Control

## Compact canvas surface for pixel cleanup. Parameters are edited in the
## workspace inspector; this card remains the only run/cancel entry point.

signal action_requested(action_id: String)

const DEFAULT_SIZE := Vector2i(420, 360)
const MIN_SIZE := Vector2i(360, 300)
const MAX_SIZE := Vector2i(800, 720)
const HEADER_HEIGHT := 40
const STATUS_HEIGHT := 32
const FOOTER_HEIGHT := 56
const GROUP_IDS := ["run_status", "summary", "settings", "footer"]

var _snapshot := {}


func _ready() -> void:
	custom_minimum_size = Vector2(MIN_SIZE.x, MIN_SIZE.y - HEADER_HEIGHT)
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_rebuild()


func configure(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_rebuild()


func get_group_ids() -> Array:
	return GROUP_IDS.duplicate()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if not is_inside_tree():
		return
	var status := HBoxContainer.new()
	status.name = "RunStatusGroup"
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	status.offset_bottom = STATUS_HEIGHT
	var state := Label.new()
	state.name = "RunState"
	state.text = _state_text(String(_snapshot.get("run", {}).get("state", "Ready")))
	status.add_child(state)
	add_child(status)

	var body := VBoxContainer.new()
	body.name = "SummaryGroup"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = STATUS_HEIGHT
	body.offset_bottom = -FOOTER_HEIGHT
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var params: Dictionary = _snapshot.get("params", {})
	var settings: Dictionary = params.get("settings", {})
	var preset := Label.new()
	preset.name = "PresetSummary"
	preset.text = (
		LocalizationService.text("CLEANUP_CARD_PRESET_FORMAT")
		% String(params.get("preset_id", "—"))
	)
	preset.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(preset)
	var input := Label.new()
	input.name = "InputSummary"
	var input_snapshot: Dictionary = _snapshot.get("input", {})
	input.text = (
		LocalizationService.text("CLEANUP_CARD_INPUT_COUNT") % int(input_snapshot.get("count", 0))
	)
	body.add_child(input)
	var details := Label.new()
	details.name = "SettingsSummary"
	details.text = _settings_summary(settings)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(details)
	var settings_button := Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = LocalizationService.text("CLEANUP_CARD_ACTION_SETTINGS")
	settings_button.pressed.connect(func() -> void: action_requested.emit("open_settings"))
	body.add_child(settings_button)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -FOOTER_HEIGHT
	var action := Button.new()
	action.name = "PrimaryAction"
	action.text = _footer_text()
	action.disabled = String(_snapshot.get("run", {}).get("state", "Ready")) == "Canceling"
	action.pressed.connect(func() -> void: action_requested.emit(_footer_action()))
	footer.add_child(action)
	add_child(footer)


func _settings_summary(settings: Dictionary) -> String:
	var detect: Dictionary = settings.get("detect_grid", {})
	var resample: Dictionary = settings.get("resample", {})
	var quantize: Dictionary = settings.get("quantize", {})
	return (
		LocalizationService.text("CLEANUP_CARD_SETTINGS_FORMAT")
		% [
			String(detect.get("mode", "—")),
			float(detect.get("scale", 0.0)),
			String(resample.get("mode", "—")),
			String(quantize.get("mode", "—")),
			String(quantize.get("palette_id", "—")),
		]
	)


func _footer_action() -> String:
	var state := String(_snapshot.get("run", {}).get("state", "Ready"))
	return (
		"cancel_cleanup"
		if state in ["Queued", "Running"]
		else (
			"retry_cleanup_interrupted"
			if bool(_snapshot.get("run", {}).get("has_interrupted", false))
			else "run_cleanup"
		)
	)


func _footer_text() -> String:
	match _footer_action():
		"cancel_cleanup":
			return LocalizationService.text("CLEANUP_CARD_ACTION_CANCEL")
		"retry_cleanup_interrupted":
			return LocalizationService.text("CLEANUP_CARD_ACTION_RETRY_INTERRUPTED")
		_:
			return LocalizationService.text("CLEANUP_CARD_ACTION_START")


func _state_text(state: String) -> String:
	match state:
		"Queued":
			return LocalizationService.text("CLEANUP_CARD_STATE_QUEUED")
		"Running":
			return LocalizationService.text("CLEANUP_CARD_STATE_RUNNING")
		"Canceling":
			return LocalizationService.text("CLEANUP_CARD_STATE_CANCELING")
		_:
			return LocalizationService.text("CLEANUP_CARD_STATE_READY")


func _on_language_changed(_preference: String, _locale: String) -> void:
	_rebuild()
