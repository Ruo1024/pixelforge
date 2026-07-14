class_name PFGenerationCardView
extends Control

## B7-4 generation card surface. Run/Output state remains owned by GenerationRunCoordinator.

signal action_requested(action_id: String, route: String)
signal upstream_requested(source_id: String)
signal params_commit_requested(params: Dictionary)

const Strings := preload("res://ui/shell/strings.gd")
const PolicyScript := preload("res://ui/canvas/generation_card_policy.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const GenerationModelPolicyScript := preload("res://services/generation_model_policy.gd")

const DEFAULT_SIZE := Vector2i(400, 520)
const MIN_SIZE := Vector2i(360, 400)
const MAX_SIZE := Vector2i(1600, 1200)
const HEADER_HEIGHT := 40
const STATUS_HEIGHT := 32
const FOOTER_HEIGHT := 56

var _snapshot := {}
var _run_context := {"state": "Ready", "errors": []}
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
	_rebuild()


func set_run_context(context: Dictionary) -> void:
	_run_context = context.duplicate(true)
	_snapshot["run"] = _run_context.duplicate(true)
	_rebuild()


func get_group_ids() -> Array:
	return PolicyScript.GROUP_IDS.duplicate()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if not is_inside_tree():
		return
	_build_status_group()
	_build_body()
	_build_footer()


func _build_status_group() -> void:
	var group := HBoxContainer.new()
	group.name = "RunStatusGroup"
	group.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	group.offset_bottom = STATUS_HEIGHT
	group.add_theme_constant_override("separation", 8)
	add_child(group)
	var state := Label.new()
	state.name = "RunState"
	state.text = Strings.text(_state_key(String(_run_context.get("state", "Ready"))))
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(state)
	var progress := Label.new()
	progress.name = "RunProgress"
	progress.text = _progress_text(_run_context.get("progress", {}))
	group.add_child(progress)
	var progress_value: Variant = _run_context.get("progress", {})
	if progress_value is Dictionary and not progress_value.is_empty():
		var indicator := ProgressBar.new()
		indicator.name = "RunProgressIndicator"
		indicator.show_percentage = false
		indicator.custom_minimum_size.x = 56
		indicator.indeterminate = not bool(progress_value.get("determinate", false))
		if not indicator.indeterminate and progress_value.get("ratio") != null:
			indicator.value = float(progress_value["ratio"]) * 100.0
		group.add_child(indicator)
	var errors: Array = _run_context.get("errors", [])
	if not errors.is_empty():
		var error_count := Label.new()
		error_count.name = "RunErrorSummary"
		error_count.text = LocalizationService.text("GEN_CARD_ERROR_COUNT", [errors.size()])
		group.add_child(error_count)


func _build_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "BodyScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = STATUS_HEIGHT
	scroll.offset_bottom = -FOOTER_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var groups := VBoxContainer.new()
	groups.name = "BodyGroups"
	groups.custom_minimum_size.x = 320
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups.add_theme_constant_override("separation", 12)
	scroll.add_child(groups)
	_build_provider_group(groups)
	_build_input_group(groups)
	_build_core_group(groups)
	_build_dynamic_group(groups)


func _build_provider_group(parent: VBoxContainer) -> void:
	var group := _group(parent, "ProviderGroup", "GEN_CARD_GROUP_PROVIDER")
	var descriptor: Dictionary = _snapshot.get("descriptor", {})
	var params: Dictionary = _snapshot.get("params", {})
	var descriptors: Array = _snapshot.get("descriptors", [])
	if descriptors.is_empty() and not descriptor.is_empty():
		descriptors = [descriptor]
	var provider_row := HBoxContainer.new()
	var provider_label := Label.new()
	provider_label.text = Strings.text("GRAPH_PARAM_PROVIDER")
	provider_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_row.add_child(provider_label)
	var provider_option := OptionButton.new()
	provider_option.name = "ProviderOption"
	var provider_ids := []
	for value in descriptors:
		if not (value is Dictionary):
			continue
		var provider_id := String(value.get("provider_id", ""))
		if provider_id.is_empty() or provider_id in provider_ids:
			continue
		provider_ids.append(provider_id)
		provider_option.add_item(String(value.get("display_name", provider_id)))
		provider_option.set_item_metadata(provider_option.item_count - 1, provider_id)
		if provider_id == String(params.get("provider_id", "")):
			provider_option.select(provider_option.item_count - 1)
	provider_option.item_selected.connect(
		func(index: int) -> void:
			var provider_id := String(provider_option.get_item_metadata(index))
			for value in descriptors:
				if (
					value is Dictionary
					and String(value.get("provider_id", "")) == provider_id
					and bool(value.get("is_default", false))
				):
					_commit_model(value, descriptors)
					return
	)
	provider_row.add_child(provider_option)
	group.add_child(provider_row)
	var model_row := HBoxContainer.new()
	var model_label := Label.new()
	model_label.text = Strings.text("GRAPH_PARAM_MODEL")
	model_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_row.add_child(model_label)
	var model_option := OptionButton.new()
	model_option.name = "ModelOption"
	for value in descriptors:
		if (
			not (value is Dictionary)
			or String(value.get("provider_id", "")) != String(params.get("provider_id", ""))
		):
			continue
		model_option.add_item(String(value.get("display_name", value.get("model_id", ""))))
		model_option.set_item_metadata(model_option.item_count - 1, value.duplicate(true))
		if String(value.get("model_id", "")) == String(params.get("model_id", "")):
			model_option.select(model_option.item_count - 1)
	model_option.item_selected.connect(
		func(index: int) -> void: _commit_model(model_option.get_item_metadata(index), descriptors)
	)
	model_row.add_child(model_option)
	group.add_child(model_row)
	var available := bool(_run_context.get("provider_available", not descriptor.is_empty()))
	var availability := Label.new()
	availability.name = "ProviderAvailability"
	availability.text = Strings.text(
		"GEN_CARD_PROVIDER_AVAILABLE" if available else "GEN_CARD_PROVIDER_UNAVAILABLE"
	)
	group.add_child(availability)
	var settings := Button.new()
	settings.name = "ProviderSettings"
	settings.text = Strings.text("GEN_CARD_ACTION_PROVIDER_SETTINGS")
	settings.pressed.connect(
		func() -> void: action_requested.emit("provider_settings", "provider_settings")
	)
	group.add_child(settings)


func _build_input_group(parent: VBoxContainer) -> void:
	var group := _group(parent, "InputSummaryGroup", "GEN_CARD_GROUP_INPUT")
	var sources: Array = _snapshot.get("input_sources", [])
	if sources.is_empty():
		var empty := Label.new()
		empty.name = "InputSummaryEmpty"
		empty.text = Strings.text("GEN_CARD_INPUT_EMPTY")
		group.add_child(empty)
		return
	for index in range(sources.size()):
		if not (sources[index] is Dictionary):
			continue
		var source: Dictionary = sources[index]
		var button := Button.new()
		button.name = "InputSource%d" % index
		button.text = String(source.get("summary", ""))
		button.tooltip_text = Strings.text("GEN_CARD_INPUT_JUMP_HINT")
		var source_id := String(source.get("id", ""))
		button.pressed.connect(func() -> void: upstream_requested.emit(source_id))
		group.add_child(button)


func _build_core_group(parent: VBoxContainer) -> void:
	var group := _group(parent, "CoreParamsGroup", "GEN_CARD_GROUP_CORE")
	var preview: Dictionary = _policy.prompt_preview(_snapshot)
	var preview_title := Label.new()
	preview_title.text = Strings.text("GEN_CARD_PROMPT_PREVIEW")
	group.add_child(preview_title)
	var prompt := Label.new()
	prompt.name = "PromptPreview"
	prompt.text = String(preview.get("first", ""))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(prompt)
	if bool(preview.get("uses_rows", false)):
		var rows_count := Label.new()
		rows_count.name = "RowsCount"
		rows_count.text = LocalizationService.text(
			"GEN_CARD_ROWS_COUNT_FORMAT",
			[int(preview.get("row_count", 0)), int(preview.get("total_count", 0))]
		)
		group.add_child(rows_count)
		var toggle := Button.new()
		toggle.name = "PromptListToggle"
		toggle.text = Strings.text("GEN_CARD_PROMPT_LIST_SHOW")
		toggle.toggle_mode = true
		group.add_child(toggle)
		var list := VBoxContainer.new()
		list.name = "PromptList"
		list.visible = false
		for entry_value in preview.get("entries", []):
			var entry: Dictionary = entry_value
			var row := Label.new()
			row.text = LocalizationService.text(
				"GEN_CARD_PROMPT_ROW_FORMAT",
				[entry.get("label", ""), entry.get("count", 0), entry.get("prompt", "")]
			)
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(row)
		toggle.toggled.connect(
			func(value: bool) -> void:
				list.visible = value
				toggle.text = Strings.text(
					"GEN_CARD_PROMPT_LIST_HIDE" if value else "GEN_CARD_PROMPT_LIST_SHOW"
				)
		)
		group.add_child(list)
	var params: Dictionary = _snapshot.get("params", {})
	group.add_child(
		_number_field(
			"TargetWidth",
			"GEN_CARD_TARGET_WIDTH",
			params.get("target_width", 32),
			1,
			4096,
			"target_width"
		)
	)
	group.add_child(
		_number_field(
			"TargetHeight",
			"GEN_CARD_TARGET_HEIGHT",
			params.get("target_height", 32),
			1,
			4096,
			"target_height"
		)
	)
	var ratio_lock := CheckButton.new()
	ratio_lock.name = "RatioLock"
	ratio_lock.text = Strings.text("GEN_CARD_RATIO_LOCK")
	ratio_lock.button_pressed = bool(_snapshot.get("ratio_locked", false))
	group.add_child(ratio_lock)
	if not bool(preview.get("uses_rows", false)):
		group.add_child(
			_number_field(
				"BatchSize",
				"GEN_CARD_BATCH_SIZE",
				params.get("batch_size", 1),
				1,
				999,
				"batch_size"
			)
		)
	var capabilities: Dictionary = Dictionary(_snapshot.get("descriptor", {})).get(
		"capabilities", {}
	)
	if not bool(capabilities.get("native_pixel", false)):
		var output_size := _policy.provider_output_size(_snapshot)
		var output := Label.new()
		output.name = "ProviderOutputSize"
		output.text = LocalizationService.text(
			"GEN_CARD_PROVIDER_OUTPUT_FORMAT", [output_size.x, output_size.y]
		)
		output.tooltip_text = Strings.text("GEN_CARD_PROVIDER_OUTPUT_HINT")
		group.add_child(output)


func _build_dynamic_group(parent: VBoxContainer) -> void:
	var group := _group(parent, "DynamicParamsGroup", "GEN_CARD_GROUP_DYNAMIC")
	var visible: Dictionary = _policy.visible_dynamic_params(_snapshot)
	for spec in visible.get("basic", []):
		group.add_child(_dynamic_field(spec))
	if bool(visible.get("show_seed", false)):
		var params: Dictionary = _snapshot.get("params", {})
		group.add_child(
			_number_field(
				"Seed", "GRAPH_PARAM_SEED", params.get("seed", -1), -1, 2147483647, "seed"
			)
		)
	var toggle := Button.new()
	toggle.name = "AdvancedToggle"
	toggle.text = Strings.text("GEN_CARD_ADVANCED")
	toggle.toggle_mode = true
	group.add_child(toggle)
	var advanced := VBoxContainer.new()
	advanced.name = "AdvancedParams"
	advanced.visible = false
	for spec in visible.get("advanced", []):
		advanced.add_child(_dynamic_field(spec))
	toggle.toggled.connect(func(value: bool) -> void: advanced.visible = value)
	group.add_child(advanced)


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -FOOTER_HEIGHT
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)
	var cost := Label.new()
	cost.name = "Cost"
	cost.text = _cost_text(_run_context.get("cost", {}))
	cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(cost)
	var action: Dictionary = _policy.footer_action(_run_context)
	var button := Button.new()
	button.name = "PrimaryAction"
	button.text = LocalizationService.text(String(action["text_key"]), action["args"])
	button.disabled = bool(action["disabled"])
	button.set_meta("action_id", action["action_id"])
	button.set_meta("route", action["route"])
	button.pressed.connect(
		func() -> void: action_requested.emit(String(action["action_id"]), String(action["route"]))
	)
	footer.add_child(button)


func _group(parent: VBoxContainer, group_name: String, title_key: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = group_name
	var title := Label.new()
	title.name = "GroupTitle"
	title.text = Strings.text(title_key)
	group.add_child(title)
	parent.add_child(group)
	return group


func _number_field(
	control_name: String,
	label_key: String,
	value: Variant,
	minimum: float,
	maximum: float,
	param_key: String
) -> Control:
	var row := HBoxContainer.new()
	row.name = "%sRow" % control_name
	var label := Label.new()
	label.text = Strings.text(label_key)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = control_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = float(value)
	spin.value_changed.connect(func(changed: float) -> void: _commit_param(param_key, int(changed)))
	row.add_child(spin)
	return row


func _dynamic_field(spec: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var key := String(spec.get("key", ""))
	row.name = "DynamicParam_%s" % key
	var label := Label.new()
	label.text = SchemaTextResolverScript.resolve(spec, "label_key")
	label.tooltip_text = SchemaTextResolverScript.resolve(spec, "help_key")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var extra: Dictionary = Dictionary(_snapshot.get("params", {})).get("extra", {})
	var value: Variant = extra.get(key, spec.get("default"))
	var control: Control
	match String(spec.get("kind", "")):
		"bool":
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(changed: bool) -> void: _commit_extra(key, changed))
			control = check
		"enum":
			var option := OptionButton.new()
			for item in spec.get("values", []):
				option.add_item(String(item))
				if item == value:
					option.select(option.item_count - 1)
			option.item_selected.connect(
				func(index: int) -> void: _commit_extra(key, option.get_item_text(index))
			)
			control = option
		"int", "float":
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", -1000000))
			spin.max_value = float(spec.get("max", 1000000))
			spin.step = float(spec.get("step", 1))
			spin.value = float(value)
			var is_int := String(spec.get("kind", "")) == "int"
			spin.value_changed.connect(
				func(changed: float) -> void:
					_commit_extra(key, int(changed) if is_int else changed)
			)
			control = spin
		_:
			var line := LineEdit.new()
			line.text = String(value)
			line.text_submitted.connect(func(changed: String) -> void: _commit_extra(key, changed))
			control = line
	control.name = "Value"
	row.add_child(control)
	return row


func _commit_param(key: String, value: Variant) -> void:
	var params: Dictionary = Dictionary(_snapshot.get("params", {})).duplicate(true)
	params[key] = value
	_snapshot["params"] = params
	params_commit_requested.emit(params.duplicate(true))


func _commit_model(descriptor: Dictionary, descriptors: Array) -> void:
	var params: Dictionary = _snapshot.get("params", {})
	var transition: Dictionary = (
		GenerationModelPolicyScript
		. transition(
			params,
			String(descriptor.get("provider_id", "")),
			String(descriptor.get("model_id", "")),
			descriptors,
		)
	)
	if not bool(transition.get("ok", false)):
		return
	_snapshot["params"] = Dictionary(transition["params"]).duplicate(true)
	params_commit_requested.emit(Dictionary(transition["params"]).duplicate(true))


func _commit_extra(key: String, value: Variant) -> void:
	var params: Dictionary = Dictionary(_snapshot.get("params", {})).duplicate(true)
	var extra: Dictionary = Dictionary(params.get("extra", {})).duplicate(true)
	extra[key] = value
	params["extra"] = extra
	_snapshot["params"] = params
	params_commit_requested.emit(params.duplicate(true))


func _state_key(state: String) -> String:
	var keys := {
		"Ready": "CONTENT_STATUS_READY",
		"Queued": "CONTENT_STATUS_QUEUED",
		"Running": "CONTENT_STATUS_RUNNING",
		"Canceling": "CONTENT_STATUS_CANCELING",
		"Partial": "CONTENT_STATUS_PARTIAL",
		"Failed": "CONTENT_STATUS_FAILED",
		"Complete": "CONTENT_STATUS_COMPLETE",
		"Canceled": "CONTENT_STATUS_CANCELED",
	}
	return String(keys.get(state, "CONTENT_STATUS_READY"))


func _progress_text(value: Variant) -> String:
	if not (value is Dictionary) or value.is_empty():
		return ""
	var progress: Dictionary = value
	var completed := int(progress.get("completed_items", 0))
	var total := int(progress.get("total_items", 0))
	var elapsed := float(progress.get("elapsed_ms", 0)) / 1000.0
	if bool(progress.get("determinate", false)) and progress.get("ratio") != null:
		return LocalizationService.text(
			"GEN_CARD_PROGRESS_DETERMINATE",
			[completed, total, float(progress["ratio"]) * 100.0, elapsed]
		)
	return LocalizationService.text("GEN_CARD_PROGRESS_INDETERMINATE", [completed, total, elapsed])


func _cost_text(value: Variant) -> String:
	if not (value is Dictionary) or value.is_empty():
		return Strings.text("GEN_CARD_COST_UNKNOWN")
	var cost: Dictionary = value
	var kind := String(cost.get("kind", "unknown"))
	if kind not in ["estimate", "actual"] or not (cost.get("micro_usd") is int):
		return Strings.text("GEN_CARD_COST_UNKNOWN")
	var key := "GEN_CARD_COST_ACTUAL" if kind == "actual" else "GEN_CARD_COST_ESTIMATE"
	return LocalizationService.text(key, [float(int(cost["micro_usd"])) / 1000000.0])


func _on_language_changed(_preference: String, _locale: String) -> void:
	_rebuild()
