class_name PFPluginManagerDialog
extends ConfirmationDialog

## Runtime plugin manager with explicit executable-code/permission disclosure.

const Strings := preload("res://ui/shell/strings.gd")

var _list: ItemList = null
var _details: RichTextLabel = null
var _install_dialog: FileDialog = null


func _ready() -> void:
	title = Strings.text("DIALOG_PLUGIN_MANAGER")
	ok_button_text = Strings.text("ACTION_CLOSE")
	min_size = Vector2i(860, 620)
	_build_ui()
	PluginService.plugins_changed.connect(refresh)
	if get_tree().root.has_signal("files_dropped"):
		get_tree().root.files_dropped.connect(_on_files_dropped)
	refresh()


func show_manager() -> void:
	refresh()
	popup_centered()


func refresh() -> void:
	if _list == null:
		return
	_list.clear()
	for record_value in PluginService.get_plugin_records():
		var record: Dictionary = record_value
		var marker := "✓" if String(record.get("state", "")) == "loaded" else "!"
		_list.add_item(
			"%s %s  %s" % [marker, record.get("name", "Plugin"), record.get("version", "")]
		)
		_list.set_item_metadata(_list.item_count - 1, record)
	if _list.item_count > 0:
		_list.select(0)
		_show_record(0)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var warning := Label.new()
	warning.text = Strings.text("PLUGIN_SECURITY_WARNING")
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(warning)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_show_record)
	body.add_child(_list)
	_details = RichTextLabel.new()
	_details.fit_content = false
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_details)
	var actions := HFlowContainer.new()
	root.add_child(actions)
	_add_button(actions, Strings.text("PLUGIN_ENABLE_DISABLE"), _toggle_selected)
	_add_button(
		actions,
		Strings.text("PLUGIN_INSTALL"),
		func() -> void: _install_dialog.popup_centered_ratio()
	)
	_add_button(actions, Strings.text("PLUGIN_UNINSTALL"), _uninstall_selected)
	_add_button(actions, Strings.text("PLUGIN_OPEN_FOLDER"), _open_folder)

	_install_dialog = FileDialog.new()
	_install_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_install_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_install_dialog.filters = PackedStringArray(["*.pck ; PixelForge Plugin Package"])
	_install_dialog.file_selected.connect(_install_pck)
	add_child(_install_dialog)


func _show_record(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var record: Dictionary = _list.get_item_metadata(index)
	var permissions: Array = record.get("permissions", [])
	_details.text = (
		"[b]%s[/b]\n%s\n\nState: %s\n%s\n\nPermissions: %s\n\nSource: %s"
		% [
			record.get("name", "Plugin"),
			record.get("description", ""),
			record.get("state", "unknown"),
			record.get("reason", ""),
			", ".join(permissions) if not permissions.is_empty() else "none declared",
			record.get("source", ""),
		]
	)


func _toggle_selected() -> void:
	var record := _selected_record()
	if record.is_empty() or bool(record.get("builtin", false)):
		return
	var enabled := String(record.get("state", "")) != "loaded"
	PluginService.set_plugin_enabled(String(record["id"]), enabled)
	refresh()


func _uninstall_selected() -> void:
	var record := _selected_record()
	if record.is_empty() or bool(record.get("builtin", false)):
		return
	PluginService.uninstall_plugin(String(record["id"]))
	refresh()


func _open_folder() -> void:
	OS.shell_open(PluginService.get_plugin_root_absolute())


func _install_pck(path: String) -> void:
	PluginService.install_pck(path)
	refresh()


func _on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if path.to_lower().ends_with(".pck"):
			_install_pck(path)


func _selected_record() -> Dictionary:
	var selected := _list.get_selected_items()
	return _list.get_item_metadata(selected[0]) if not selected.is_empty() else {}


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
