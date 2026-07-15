class_name PFProviderSettingsDialog
extends ConfirmationDialog

## Provider configuration UI generated exclusively from PROVIDER-API config_schema/capabilities.
## contract: 02-contracts/PROVIDER-API.md §1, §3。

const Strings := preload("res://ui/shell/strings.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")

const DIALOG_WIDTH := 560
const DIALOG_HEIGHT := 560
const CONTROL_HEIGHT := 30
const ROOT_SEPARATION := 8

var _provider_options: OptionButton = null
var _provider_label: Label = null
var _capabilities_label: Label = null
var _form: VBoxContainer = null
var _status_label: Label = null
var _validate_button: Button = null
var _save_button: Button = null
var _fields := {}
var _provider_id := ""
var _provider_service: Node = null
var _task_queue: Node = null
var _rendering := false


func _ready() -> void:
	_build()
	_provider_api().provider_validation_changed.connect(_on_provider_validation_changed)
	LocalizationService.language_changed.connect(_on_language_changed)
	_refresh_provider_list()


func set_services(provider_service: Node, task_queue: Node) -> void:
	_provider_service = provider_service
	_task_queue = task_queue


func show_settings(provider_id: String = "") -> void:
	_refresh_provider_list()
	if not provider_id.is_empty():
		_select_provider(provider_id)
	popup_centered()


func get_field_control(key: String) -> Control:
	return _fields.get(key)


func get_current_provider_id() -> String:
	return _provider_id


func is_validation_available() -> bool:
	return _validate_button != null and _validate_button.visible


func save_current_config() -> Dictionary:
	var result: Dictionary = _provider_api().save_provider_config(_provider_id, _draft_config())
	_status_label.text = (
		Strings.text("PROVIDER_SETTINGS_SAVED")
		if bool(result.get("ok", false))
		else Strings.text("PROVIDER_SETTINGS_SAVE_FAILED")
	)
	if bool(result.get("ok", false)):
		_render_provider(_provider_id)
	return result


func validate_current_provider() -> bool:
	var task: Variant = _provider_api().validate_provider(_provider_id, _draft_config())
	if task == null:
		if _status_label.text.is_empty():
			_status_label.text = Strings.text("PROVIDER_SETTINGS_VALIDATE_UNAVAILABLE")
		return false
	_validate_button.disabled = true
	task.finished.connect(func(_result: Variant) -> void: _validate_button.disabled = false)
	task.failed.connect(func(_error: Dictionary) -> void: _validate_button.disabled = false)
	task.canceled.connect(func() -> void: _validate_button.disabled = false)
	_task_queue_api().submit(task)
	return true


func _build() -> void:
	title = Strings.text("DIALOG_PROVIDER_SETTINGS_TITLE")
	ok_button_text = Strings.text("ACTION_SAVE_PROVIDER")
	cancel_button_text = Strings.text("ACTION_CANCEL")
	_save_button = get_ok_button()
	confirmed.connect(save_current_config)
	canceled.connect(_on_cancel_requested)
	min_size = Vector2i(DIALOG_WIDTH, DIALOG_HEIGHT)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(root)

	_provider_label = Label.new()
	_provider_label.text = Strings.text("PROVIDER_SETTINGS_PROVIDER")
	root.add_child(_provider_label)
	_provider_options = OptionButton.new()
	_provider_options.custom_minimum_size.y = CONTROL_HEIGHT
	_provider_options.item_selected.connect(_on_provider_selected)
	root.add_child(_provider_options)
	_capabilities_label = Label.new()
	_capabilities_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_capabilities_label)
	root.add_child(HSeparator.new())

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", ROOT_SEPARATION)
	root.add_child(_form)

	var actions := HBoxContainer.new()
	_validate_button = Button.new()
	_validate_button.text = Strings.text("ACTION_VALIDATE_PROVIDER")
	_validate_button.pressed.connect(validate_current_provider)
	actions.add_child(_validate_button)
	root.add_child(actions)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)


func _refresh_provider_list() -> void:
	if _provider_options == null:
		return
	var previous := _provider_id
	_provider_options.clear()
	for provider_id in _provider_api().get_provider_ids():
		var descriptor: Dictionary = _provider_api().get_model_descriptor(String(provider_id))
		_provider_options.add_item(String(descriptor.get("display_name", provider_id)))
		_provider_options.set_item_metadata(_provider_options.item_count - 1, provider_id)
	if _provider_options.item_count == 0:
		_provider_id = ""
		return
	_select_provider("openai_image" if previous.is_empty() else previous)


func _select_provider(provider_id: String) -> void:
	var selected := 0
	for index in range(_provider_options.item_count):
		if String(_provider_options.get_item_metadata(index)) == provider_id:
			selected = index
			break
	_provider_options.select(selected)
	_on_provider_selected(selected)


func _on_provider_selected(index: int) -> void:
	if index < 0 or index >= _provider_options.item_count:
		return
	var next_provider_id := String(_provider_options.get_item_metadata(index))
	if not _provider_id.is_empty() and _provider_id != next_provider_id:
		_provider_api().restore_provider_config(_provider_id)
	_provider_id = next_provider_id
	_render_provider(_provider_id)


func _render_provider(provider_id: String) -> void:
	_fields.clear()
	for child in _form.get_children():
		child.queue_free()
	var provider: PFProvider = _provider_api().get_provider(provider_id)
	if provider == null:
		return
	_rendering = true
	var descriptor: Dictionary = _provider_api().get_model_descriptor(provider_id)
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	_capabilities_label.text = _capabilities_text(capabilities)
	_validate_button.visible = bool(capabilities.get("safe_validation", true))
	var values: Dictionary = _provider_api().get_provider_config(provider_id)
	for field in provider.get_config_schema():
		_add_field(field, values)
	_status_label.text = _provider_api().get_validation_message(provider_id)
	_rendering = false


func _add_field(schema: Dictionary, values: Dictionary) -> void:
	var key := String(schema.get("key", ""))
	if key.is_empty():
		return
	var label := Label.new()
	label.text = SchemaTextResolverScript.resolve(schema, "label_key")
	_form.add_child(label)
	var control := _make_control(schema, values.get(key, schema.get("default")))
	_form.add_child(control)
	_fields[key] = control
	_connect_draft_signal(control)
	if String(schema.get("kind", "")) == "password" and bool(values.get("%s_saved" % key, false)):
		(control as LineEdit).placeholder_text = Strings.text("PROVIDER_SETTINGS_SECRET_SAVED")


func _make_control(schema: Dictionary, value: Variant) -> Control:
	var kind := String(schema.get("kind", "text"))
	if kind == "password":
		var password := LineEdit.new()
		password.secret = true
		password.custom_minimum_size.y = CONTROL_HEIGHT
		return password
	if kind == "bool":
		var check := CheckBox.new()
		check.button_pressed = bool(value)
		return check
	if kind == "enum":
		var options := OptionButton.new()
		for option in schema.get("values", []):
			options.add_item(String(option))
			if option == value:
				options.select(options.item_count - 1)
		return options
	var edit := LineEdit.new()
	edit.text = String(value) if value != null else ""
	edit.custom_minimum_size.y = CONTROL_HEIGHT
	return edit


func _control_value(control: Control) -> Variant:
	if control is CheckBox:
		return control.button_pressed
	if control is OptionButton:
		return control.get_item_text(control.selected)
	if control is LineEdit:
		return control.text
	return null


func _capabilities_text(capabilities: Dictionary) -> String:
	return (
		Strings.text("PROVIDER_SETTINGS_CAPABILITIES_FORMAT")
		% [
			_yes_no(bool(capabilities.get("txt2img", false))),
			_yes_no(bool(capabilities.get("img2img", false))),
			_yes_no(bool(capabilities.get("transparent_bg", false))),
			_yes_no(bool(capabilities.get("native_pixel", false))),
			int(capabilities.get("max_batch", 1)),
		]
	)


func _yes_no(value: bool) -> String:
	return Strings.text("VALUE_YES") if value else Strings.text("VALUE_NO")


func _draft_config() -> Dictionary:
	var config := {}
	for key in _fields.keys():
		config[String(key)] = _control_value(_fields[key])
	return config


func _connect_draft_signal(control: Control) -> void:
	if control is LineEdit:
		control.text_changed.connect(func(_value: String) -> void: _mark_untested())
	elif control is CheckBox:
		control.toggled.connect(func(_value: bool) -> void: _mark_untested())
	elif control is OptionButton:
		control.item_selected.connect(func(_index: int) -> void: _mark_untested())


func _mark_untested() -> void:
	if _rendering:
		return
	_status_label.text = Strings.text("PROVIDER_PING_UNTESTED")


func _provider_api() -> Node:
	return _provider_service if _provider_service != null else ProviderService


func _task_queue_api() -> Node:
	return _task_queue if _task_queue != null else TaskQueue


func _on_cancel_requested() -> void:
	if not _provider_id.is_empty():
		_provider_api().restore_provider_config(_provider_id)


func _on_provider_validation_changed(provider_id: String, _state: String, message: String) -> void:
	if provider_id == _provider_id:
		_status_label.text = message


func _on_language_changed(_preference: String, _locale: String) -> void:
	title = Strings.text("DIALOG_PROVIDER_SETTINGS_TITLE")
	ok_button_text = Strings.text("ACTION_SAVE_PROVIDER")
	cancel_button_text = Strings.text("ACTION_CANCEL")
	_provider_label.text = Strings.text("PROVIDER_SETTINGS_PROVIDER")
	_save_button.text = Strings.text("ACTION_SAVE_PROVIDER")
	_validate_button.text = Strings.text("ACTION_VALIDATE_PROVIDER")
	if not _provider_id.is_empty():
		_render_provider(_provider_id)
