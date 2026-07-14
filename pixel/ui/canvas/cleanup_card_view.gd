# gdlint: disable=max-returns
class_name PFCleanupCardView
extends Control

signal action_requested(action_id: String)
signal upstream_requested(source_id: String)
signal params_commit_requested(params: Dictionary)

const DEFAULT_SIZE := Vector2i(420, 680)
const MIN_SIZE := Vector2i(360, 480)
const MAX_SIZE := Vector2i(800, 1000)
const HEADER_HEIGHT := 40
const STATUS_HEIGHT := 32
const FOOTER_HEIGHT := 56
const GROUP_IDS := [
	"run_status", "input_summary", "preset", "grid", "resample", "quantize", "last_report", "footer"
]

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
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = STATUS_HEIGHT
	scroll.offset_bottom = -FOOTER_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "BodyGroups"
	body.custom_minimum_size.x = 0
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_build_input(body)
	_build_group(
		body, "PresetGroup", "CLEANUP_CARD_GROUP_PRESET", [_text("CLEANUP_CARD_PRESET_HINT")]
	)
	_build_group(body, "GridGroup", "CLEANUP_CARD_GROUP_GRID", [_text("CLEANUP_CARD_GRID_SUMMARY")])
	_build_group(
		body,
		"ResampleGroup",
		"CLEANUP_CARD_GROUP_RESAMPLE",
		[_text("CLEANUP_CARD_RESAMPLE_SUMMARY")]
	)
	_build_group(
		body,
		"QuantizeGroup",
		"CLEANUP_CARD_GROUP_QUANTIZE",
		[_text("CLEANUP_CARD_QUANTIZE_SUMMARY")]
	)
	_build_group(
		body, "LastReportGroup", "CLEANUP_CARD_GROUP_REPORT", [_text("CLEANUP_CARD_REPORT_EMPTY")]
	)
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


func _build_input(parent: VBoxContainer) -> void:
	var input: Dictionary = _snapshot.get("input", {})
	var text := (
		"%s · %s · %s"
		% [
			String(input.get("kind", "—")),
			_text("CLEANUP_CARD_INPUT_COUNT") % int(input.get("count", 0)),
			String(input.get("target", "—"))
		]
	)
	_build_group(parent, "InputSummaryGroup", "CLEANUP_CARD_GROUP_INPUT", [text])


func _build_group(parent: VBoxContainer, name: String, title_key: String, lines: Array) -> void:
	var group := VBoxContainer.new()
	group.name = name
	var title := Label.new()
	title.text = _text(title_key)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(title)
	for line in lines:
		var label := Label.new()
		label.text = String(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_child(label)
	parent.add_child(group)


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
			return _text("CLEANUP_CARD_ACTION_CANCEL")
		"retry_cleanup_interrupted":
			return _text("CLEANUP_CARD_ACTION_RETRY_INTERRUPTED")
		_:
			return _text("CLEANUP_CARD_ACTION_START")


func _text(key: String) -> String:
	match key:
		"CLEANUP_CARD_GROUP_PRESET":
			return LocalizationService.text("CLEANUP_CARD_GROUP_PRESET")
		"CLEANUP_CARD_PRESET_HINT":
			return LocalizationService.text("CLEANUP_CARD_PRESET_HINT")
		"CLEANUP_CARD_GROUP_GRID":
			return LocalizationService.text("CLEANUP_CARD_GROUP_GRID")
		"CLEANUP_CARD_GRID_SUMMARY":
			return LocalizationService.text("CLEANUP_CARD_GRID_SUMMARY")
		"CLEANUP_CARD_GROUP_RESAMPLE":
			return LocalizationService.text("CLEANUP_CARD_GROUP_RESAMPLE")
		"CLEANUP_CARD_RESAMPLE_SUMMARY":
			return LocalizationService.text("CLEANUP_CARD_RESAMPLE_SUMMARY")
		"CLEANUP_CARD_GROUP_QUANTIZE":
			return LocalizationService.text("CLEANUP_CARD_GROUP_QUANTIZE")
		"CLEANUP_CARD_QUANTIZE_SUMMARY":
			return LocalizationService.text("CLEANUP_CARD_QUANTIZE_SUMMARY")
		"CLEANUP_CARD_GROUP_REPORT":
			return LocalizationService.text("CLEANUP_CARD_GROUP_REPORT")
		"CLEANUP_CARD_REPORT_EMPTY":
			return LocalizationService.text("CLEANUP_CARD_REPORT_EMPTY")
		"CLEANUP_CARD_INPUT_COUNT":
			return LocalizationService.text("CLEANUP_CARD_INPUT_COUNT")
		"CLEANUP_CARD_GROUP_INPUT":
			return LocalizationService.text("CLEANUP_CARD_GROUP_INPUT")
		"CLEANUP_CARD_ACTION_CANCEL":
			return LocalizationService.text("CLEANUP_CARD_ACTION_CANCEL")
		"CLEANUP_CARD_ACTION_RETRY_INTERRUPTED":
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
