# gdlint: disable=max-returns
class_name PFGenerationCardView
extends Control

## Fixed generation surface. API configuration lives in the top application bar.

signal action_requested(action_id: String, route: String)
signal upstream_requested(source_id: String)
signal params_commit_requested(params: Dictionary)

const Strings := preload("res://ui/shell/strings.gd")
const PolicyScript := preload("res://ui/canvas/generation_card_policy.gd")
const DeliveryPolicy := preload("res://services/generation_delivery_policy.gd")
const PromptBuilder := preload("res://services/generation_prompt_builder.gd")

const DEFAULT_SIZE := Vector2i(420, 520)
const MIN_SIZE := Vector2i(380, 460)
const MAX_SIZE := Vector2i(900, 900)
const HEADER_HEIGHT := 40
const STATUS_HEIGHT := 40
const FOOTER_HEIGHT := 56
const GROUP_IDS := [
	"run_status", "model", "resolution", "orientation", "count", "developer_prompt", "footer"
]

var _snapshot := {}
var _run_context := {"state": "Ready", "errors": []}
var _developer_mode := false
var _policy := PolicyScript.new()


func _ready() -> void:
	custom_minimum_size = Vector2(MIN_SIZE.x, MIN_SIZE.y - HEADER_HEIGHT)
	if not LocalizationService.language_changed.is_connected(_on_language_changed):
		LocalizationService.language_changed.connect(_on_language_changed)
	_rebuild()


func configure(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_run_context = Dictionary(_snapshot.get("run", {"state": "Ready", "errors": []})).duplicate(
		true
	)
	_developer_mode = bool(_snapshot.get("developer_mode", false))
	_rebuild()


func set_run_context(context: Dictionary) -> void:
	_run_context = context.duplicate(true)
	_snapshot["run"] = _run_context.duplicate(true)
	_rebuild()


func set_developer_mode(enabled: bool) -> void:
	if _developer_mode == enabled:
		return
	_developer_mode = enabled
	_rebuild()


func get_group_ids() -> Array:
	return GROUP_IDS.duplicate()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if not is_inside_tree():
		return
	_build_status()
	var body := VBoxContainer.new()
	body.name = "BodyGroups"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_top = STATUS_HEIGHT
	body.offset_bottom = -FOOTER_HEIGHT
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	_build_model(body)
	_build_resolution(body)
	_build_orientation(body)
	_build_count(body)
	_build_developer_preview(body)
	_build_footer()


func _build_status() -> void:
	var group := HBoxContainer.new()
	group.name = "RunStatusGroup"
	group.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	group.offset_bottom = STATUS_HEIGHT
	add_child(group)
	var state := Label.new()
	state.name = "RunState"
	state.text = _state_text(String(_run_context.get("state", "Ready")))
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(state)
	var progress := Label.new()
	progress.name = "RunProgress"
	progress.text = _progress_text(_run_context.get("progress", {}))
	group.add_child(progress)


func _build_model(parent: VBoxContainer) -> void:
	var group := _group(parent, "ModelGroup", "GEN_CARD_MODEL")
	var descriptor: Dictionary = _snapshot.get("descriptor", {})
	var model := Label.new()
	model.name = "ModelValue"
	model.text = String(descriptor.get("display_name", "GPT Image 2"))
	model.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(model)
	var host := Label.new()
	host.name = "ApiHost"
	host.text = String(_snapshot.get("api_host", "api.openai.com"))
	host.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	group.add_child(host)


func _build_resolution(parent: VBoxContainer) -> void:
	var group := _group(parent, "ResolutionGroup", "GEN_CARD_RESOLUTION")
	var params: Dictionary = _snapshot.get("params", {})
	var option := OptionButton.new()
	option.name = "ResolutionPreset"
	for value in DeliveryPolicy.RESOLUTION_PRESETS:
		option.add_item(value)
		option.set_item_metadata(option.item_count - 1, value)
		if value == String(params.get("resolution_preset", "1080p")):
			option.select(option.item_count - 1)
	option.item_selected.connect(
		func(index: int) -> void:
			_commit_param("resolution_preset", String(option.get_item_metadata(index)))
	)
	group.add_child(option)


func _build_orientation(parent: VBoxContainer) -> void:
	var group := _group(parent, "OrientationGroup", "GEN_CARD_ORIENTATION")
	var params: Dictionary = _snapshot.get("params", {})
	var option := OptionButton.new()
	option.name = "Orientation"
	for value in DeliveryPolicy.ORIENTATIONS:
		option.add_item(_orientation_text(value))
		option.set_item_metadata(option.item_count - 1, value)
		if value == String(params.get("orientation", "square")):
			option.select(option.item_count - 1)
	option.item_selected.connect(
		func(index: int) -> void: _commit_param("orientation", option.get_item_metadata(index))
	)
	group.add_child(option)


func _build_count(parent: VBoxContainer) -> void:
	var group := _group(parent, "CountGroup", "GEN_CARD_COUNT")
	var params: Dictionary = _snapshot.get("params", {})
	var count := SpinBox.new()
	count.name = "BatchSize"
	count.min_value = 1
	count.max_value = 16
	count.step = 1
	count.value = float(params.get("batch_size", 1))
	count.value_changed.connect(func(value: float) -> void: _commit_param("batch_size", int(value)))
	group.add_child(count)


func _build_developer_preview(parent: VBoxContainer) -> void:
	if not _developer_mode:
		return
	var group := _group(parent, "DeveloperPromptGroup", "GEN_CARD_DEVELOPER_PROMPT")
	var preview := Label.new()
	preview.name = "DeveloperPromptPreview"
	preview.text = _final_prompt_preview()
	preview.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	group.add_child(preview)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -FOOTER_HEIGHT
	add_child(footer)
	var action: Dictionary = _policy.footer_action(_run_context)
	var button := Button.new()
	button.name = "PrimaryAction"
	button.text = _footer_action_text(action)
	button.disabled = bool(action["disabled"])
	button.set_meta("action_id", action["action_id"])
	button.set_meta("route", action["route"])
	button.pressed.connect(
		func() -> void: action_requested.emit(String(action["action_id"]), String(action["route"]))
	)
	footer.add_child(button)


func _group(parent: VBoxContainer, group_name: String, title_key: String) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.name = group_name
	var title := Label.new()
	title.text = _group_title(title_key)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(title)
	parent.add_child(group)
	return group


func _commit_param(key: String, value: Variant) -> void:
	var params: Dictionary = Dictionary(_snapshot.get("params", {})).duplicate(true)
	params[key] = value
	params["seed"] = -1
	params["extra"] = {}
	_snapshot["params"] = params
	params_commit_requested.emit(params.duplicate(true))


func _final_prompt_preview() -> String:
	var subject := ""
	for value in _snapshot.get("rows", []):
		if value is Dictionary and bool(value.get("enabled", true)):
			subject = String(value.get("text", ""))
			break
	return PromptBuilder.build(
		String(_snapshot.get("prefix", "")), String(_snapshot.get("prompt", "")), subject
	)


func _state_text(state: String) -> String:
	match state:
		"Queued":
			return Strings.text("CONTENT_STATUS_QUEUED")
		"Running":
			return Strings.text("CONTENT_STATUS_RUNNING")
		"Canceling":
			return Strings.text("CONTENT_STATUS_CANCELING")
		"Partial":
			return Strings.text("CONTENT_STATUS_PARTIAL")
		"Failed":
			return Strings.text("CONTENT_STATUS_FAILED")
		"Complete":
			return Strings.text("CONTENT_STATUS_COMPLETE")
		"Canceled":
			return Strings.text("CONTENT_STATUS_CANCELED")
		_:
			return Strings.text("CONTENT_STATUS_READY")


func _progress_text(value: Variant) -> String:
	if not (value is Dictionary) or value.is_empty():
		return ""
	var completed := int(value.get("completed_items", 0))
	var total := int(value.get("total_items", 0))
	var elapsed := float(value.get("elapsed_ms", 0)) / 1000.0
	return LocalizationService.text("GEN_CARD_PROGRESS_INDETERMINATE", [completed, total, elapsed])


func _footer_action_text(action: Dictionary) -> String:
	var action_id := String(action.get("action_id", ""))
	if action_id == "retry_wait":
		return LocalizationService.text("GEN_CARD_ACTION_RETRY_WAIT", action.get("args", []))
	match action_id:
		"generate":
			return Strings.text("GEN_CARD_ACTION_GENERATE")
		"cancel":
			return Strings.text("GEN_CARD_ACTION_CANCEL")
		"regenerate":
			return Strings.text("GEN_CARD_ACTION_REGENERATE")
		"cancel_failed":
			return Strings.text("GEN_CARD_ACTION_CANCEL_FAILED")
		"retry_failed":
			return Strings.text("GEN_CARD_ACTION_RETRY_FAILED")
		"provider_settings":
			return Strings.text("GEN_CARD_ACTION_PROVIDER_SETTINGS")
		"edit_prompt":
			return Strings.text("GEN_CARD_ACTION_EDIT_PROMPT")
		"focus_generation":
			return Strings.text("GEN_CARD_ACTION_RETURN_GENERATION")
		"regenerate_confirm":
			return Strings.text("GEN_CARD_ACTION_REGENERATE_CONFIRM")
		_:
			return Strings.text("GEN_CARD_ACTION_CANCELING")


func _orientation_text(value: String) -> String:
	match value:
		"landscape":
			return Strings.text("GEN_CARD_ORIENTATION_LANDSCAPE")
		"portrait":
			return Strings.text("GEN_CARD_ORIENTATION_PORTRAIT")
		_:
			return Strings.text("GEN_CARD_ORIENTATION_SQUARE")


func _group_title(key: String) -> String:
	match key:
		"GEN_CARD_MODEL":
			return Strings.text("GEN_CARD_MODEL")
		"GEN_CARD_RESOLUTION":
			return Strings.text("GEN_CARD_RESOLUTION")
		"GEN_CARD_ORIENTATION":
			return Strings.text("GEN_CARD_ORIENTATION")
		"GEN_CARD_COUNT":
			return Strings.text("GEN_CARD_COUNT")
		_:
			return Strings.text("GEN_CARD_DEVELOPER_PROMPT")


func _on_language_changed(_preference: String, _locale: String) -> void:
	_rebuild()
