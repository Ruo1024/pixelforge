class_name PFPromptPresetCardView
extends Control

signal preset_commit_requested(preset: Dictionary)
signal text_copy_requested(text: String)
signal inspector_requested(intent: String)

const Library := preload("res://services/prompt_preset_library.gd")
const Strings := preload("res://ui/shell/strings.gd")
const FLEXIBLE_WIDTH := 0.0
const PREFIX_MIN_HEIGHT := 72.0

var _current_preset := {}
var _entries: Array[Dictionary] = []
var _editing := false
var _dirty := false
var _draft_name := ""
var _draft_prefix := ""
var _pending_preset := {}
var _status_key := ""
var _suppress_changes := false
var _last_editor_focus := &""
var _compact_mode := false

var _option: OptionButton = null
var _source_label: Label = null
var _prefix_label: Label = null
var _name_edit: LineEdit = null
var _prefix_edit: TextEdit = null
var _status_label: Label = null
var _new_button: Button = null
var _copy_button: Button = null
var _edit_button: Button = null
var _rename_button: Button = null
var _save_button: Button = null
var _delete_button: Button = null
var _copy_text_button: Button = null
var _unsaved_dialog: ConfirmationDialog = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	_rebuild_entries()
	_sync_controls()


func configure(preset: Dictionary) -> void:
	_current_preset = preset.duplicate(true)
	_editing = false
	_dirty = false
	_draft_name = Library.display_name(_current_preset)
	_draft_prefix = String(_current_preset.get("prefix", ""))
	_pending_preset = {}
	if is_inside_tree():
		_rebuild_entries()
		_sync_controls()


func set_compact_mode(enabled: bool) -> void:
	_compact_mode = enabled
	if is_inside_tree():
		_sync_controls()


func begin_action(intent: String) -> bool:
	match intent:
		"new":
			_create_new()
		"edit":
			_edit_current()
		"rename":
			_rename_current()
		_:
			return false
	return true


func get_current_preset() -> Dictionary:
	return _current_preset.duplicate(true)


func has_unsaved_changes() -> bool:
	return _dirty


func request_selection_by_id(preset_id: String) -> bool:
	for entry in _entries:
		if String(entry.get("id", "")) == preset_id:
			_request_selection(Dictionary(entry["preset"]).duplicate(true))
			return true
	return false


func resolve_unsaved_switch(decision: String) -> void:
	if _pending_preset.is_empty():
		return
	if decision == "save" and not _save_edits(false):
		return
	if decision in ["save", "discard"]:
		var target := _pending_preset.duplicate(true)
		_pending_preset = {}
		_unsaved_dialog.hide()
		_apply_selection(target)
	else:
		_pending_preset = {}
		_unsaved_dialog.hide()
		_sync_option_selection()
		_restore_editor_focus.call_deferred()


func export_interaction_state() -> Dictionary:
	return {
		"current_preset": _current_preset.duplicate(true),
		"editing": _editing,
		"dirty": _dirty,
		"draft_name": _draft_name,
		"draft_prefix": _draft_prefix,
		"pending_preset": _pending_preset.duplicate(true),
		"status_key": _status_key,
		"last_editor_focus": _last_editor_focus,
	}


func import_interaction_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var restore_draft := bool(state.get("editing", false)) or bool(state.get("dirty", false))
	if restore_draft:
		_current_preset = Dictionary(state.get("current_preset", _current_preset)).duplicate(true)
	_editing = bool(state.get("editing", false))
	_dirty = bool(state.get("dirty", false))
	_draft_name = String(
		(
			state.get("draft_name", Library.display_name(_current_preset))
			if restore_draft
			else Library.display_name(_current_preset)
		)
	)
	_draft_prefix = String(
		(
			state.get("draft_prefix", _current_preset.get("prefix", ""))
			if restore_draft
			else _current_preset.get("prefix", "")
		)
	)
	_pending_preset = Dictionary(state.get("pending_preset", {})).duplicate(true)
	_status_key = String(state.get("status_key", ""))
	_last_editor_focus = StringName(state.get("last_editor_focus", &""))
	_rebuild_entries()
	_sync_controls()


func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "PromptPresetScroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "PromptPresetBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_option = OptionButton.new()
	_option.name = "PresetOption"
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option.tooltip_text = Strings.text("STYLE_PROMPT_SELECT_HINT")
	_option.item_selected.connect(_on_option_selected)
	body.add_child(_option)
	_source_label = Label.new()
	_source_label.name = "PresetSource"
	body.add_child(_source_label)
	_name_edit = LineEdit.new()
	_name_edit.name = "PresetNameEdit"
	_name_edit.placeholder_text = Strings.text("STYLE_PROMPT_NAME_PLACEHOLDER")
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.gui_input.connect(_on_editor_input)
	_name_edit.focus_entered.connect(func() -> void: _last_editor_focus = &"name")
	body.add_child(_name_edit)
	_prefix_label = Label.new()
	_prefix_label.text = Strings.text("STYLE_PROMPT_PREFIX")
	body.add_child(_prefix_label)
	_prefix_edit = TextEdit.new()
	_prefix_edit.name = "PresetPrefixEdit"
	_prefix_edit.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, PREFIX_MIN_HEIGHT)
	_prefix_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prefix_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_prefix_edit.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_prefix_edit.scroll_horizontal = 0
	_prefix_edit.text_changed.connect(_on_prefix_changed)
	_prefix_edit.gui_input.connect(_on_editor_input)
	_prefix_edit.focus_entered.connect(func() -> void: _last_editor_focus = &"prefix")
	body.add_child(_prefix_edit)
	var actions := HFlowContainer.new()
	actions.name = "PresetActions"
	_new_button = _action_button(
		actions, "PresetNew", Strings.text("STYLE_PROMPT_ACTION_NEW"), _request_new
	)
	_copy_button = _action_button(
		actions, "PresetCopy", Strings.text("STYLE_PROMPT_ACTION_COPY"), _copy_current
	)
	_edit_button = _action_button(
		actions, "PresetEdit", Strings.text("STYLE_PROMPT_ACTION_EDIT"), _request_edit
	)
	_rename_button = _action_button(
		actions, "PresetRename", Strings.text("ACTION_RENAME"), _request_rename
	)
	_save_button = _action_button(
		actions, "PresetSave", Strings.text("ACTION_SAVE"), _save_button_pressed
	)
	_delete_button = _action_button(
		actions, "PresetDelete", Strings.text("ACTION_DELETE"), _delete_current
	)
	_copy_text_button = _action_button(
		actions, "PresetCopyText", Strings.text("STYLE_PROMPT_ACTION_COPY_TEXT"), _copy_text
	)
	body.add_child(actions)
	_status_label = Label.new()
	_status_label.name = "PresetStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status_label)
	_build_unsaved_dialog()


func _action_button(
	parent: Control, control_name: String, button_text: String, callback: Callable
) -> Button:
	var button := Button.new()
	button.name = control_name
	button.text = button_text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_unsaved_dialog() -> void:
	_unsaved_dialog = ConfirmationDialog.new()
	_unsaved_dialog.name = "PresetUnsavedDialog"
	_unsaved_dialog.title = Strings.text("STYLE_PROMPT_UNSAVED_TITLE")
	_unsaved_dialog.dialog_text = Strings.text("STYLE_PROMPT_UNSAVED_BODY")
	_unsaved_dialog.ok_button_text = Strings.text("ACTION_SAVE")
	_unsaved_dialog.cancel_button_text = Strings.text("ACTION_CANCEL")
	_unsaved_dialog.add_button(Strings.text("ACTION_DISCARD"), true, "discard")
	_unsaved_dialog.confirmed.connect(func() -> void: resolve_unsaved_switch("save"))
	_unsaved_dialog.canceled.connect(func() -> void: resolve_unsaved_switch("cancel"))
	_unsaved_dialog.custom_action.connect(
		func(action: StringName) -> void:
			if action == &"discard":
				resolve_unsaved_switch("discard")
	)
	add_child(_unsaved_dialog)


func _rebuild_entries() -> void:
	_entries = Library.list_entries()
	var has_exact_snapshot := false
	for entry in _entries:
		if Dictionary(entry.get("preset", {})) == _current_preset:
			has_exact_snapshot = true
			break
	if not has_exact_snapshot and not _current_preset.is_empty():
		(
			_entries
			. append(
				{
					"id": String(_current_preset.get("id", "")),
					"name": Library.display_name(_current_preset),
					"source": "snapshot",
					"read_only": true,
					"preset": _current_preset.duplicate(true),
				}
			)
		)


func _sync_controls() -> void:
	if _option == null:
		return
	_suppress_changes = true
	_option.clear()
	for entry in _entries:
		_option.add_item(String(entry.get("name", entry.get("id", ""))))
	_sync_option_selection()
	var entry := _current_entry()
	var source := String(entry.get("source", "snapshot"))
	_source_label.text = (Strings.text("STYLE_PROMPT_SOURCE_FORMAT") % _source_text(source))
	_name_edit.visible = _editing and not _compact_mode
	_name_edit.text = _draft_name
	_prefix_label.visible = not _compact_mode
	_prefix_edit.visible = not _compact_mode
	_prefix_edit.editable = _editing
	_prefix_edit.text = _draft_prefix if _editing else String(_current_preset.get("prefix", ""))
	_new_button.visible = not _editing
	_copy_button.visible = not _editing
	_edit_button.visible = not _editing
	_rename_button.visible = not _editing and source == "user"
	_save_button.visible = _editing and not _compact_mode
	_save_button.disabled = _draft_name.strip_edges().is_empty()
	_delete_button.visible = not _editing and source == "user"
	_copy_text_button.visible = not _editing
	_status_label.text = _status_text()
	_suppress_changes = false


func _request_new() -> void:
	if _compact_mode:
		inspector_requested.emit("new")
	else:
		_create_new()


func _request_edit() -> void:
	if _compact_mode:
		inspector_requested.emit("edit")
	else:
		_edit_current()


func _request_rename() -> void:
	if _compact_mode:
		inspector_requested.emit("rename")
	else:
		_rename_current()


func _sync_option_selection() -> void:
	for index in range(_entries.size()):
		if Dictionary(_entries[index].get("preset", {})) == _current_preset:
			_option.select(index)
			return


func _current_entry() -> Dictionary:
	for entry in _entries:
		if Dictionary(entry.get("preset", {})) == _current_preset:
			return entry
	return {"source": "snapshot", "read_only": true, "preset": _current_preset}


func _on_option_selected(index: int) -> void:
	if _suppress_changes or index < 0 or index >= _entries.size():
		return
	_request_selection(Dictionary(_entries[index]["preset"]).duplicate(true))


func _request_selection(preset: Dictionary) -> void:
	if preset == _current_preset:
		return
	if _dirty:
		_pending_preset = preset.duplicate(true)
		_sync_option_selection()
		_unsaved_dialog.popup_centered(Vector2i(420, 220))
		return
	_apply_selection(preset)


func _apply_selection(
	preset: Dictionary, edit_after_selection: bool = false, status_key: String = ""
) -> void:
	_current_preset = preset.duplicate(true)
	_editing = edit_after_selection
	_dirty = false
	_draft_name = Library.display_name(_current_preset)
	_draft_prefix = String(_current_preset.get("prefix", ""))
	_status_key = status_key
	_rebuild_entries()
	_sync_controls()
	if edit_after_selection:
		_prefix_edit.grab_focus()
	preset_commit_requested.emit(_current_preset.duplicate(true))


func _create_new() -> void:
	var created := Library.create_user_preset(Strings.text("STYLE_PROMPT_NEW_NAME"), "")
	if not bool(created.get("ok", false)):
		return
	_apply_selection(created["preset"], true)


func _copy_current() -> void:
	var copy_name := (
		Strings.text("STYLE_PROMPT_COPY_NAME_FORMAT") % Library.display_name(_current_preset)
	)
	var copied := Library.duplicate_as_user(_current_preset, copy_name)
	if not bool(copied.get("ok", false)):
		return
	_apply_selection(copied["preset"], false, "STYLE_PROMPT_STATUS_COPIED")


func _edit_current() -> void:
	if bool(_current_entry().get("read_only", true)):
		var copy_name := (
			Strings.text("STYLE_PROMPT_COPY_NAME_FORMAT") % Library.display_name(_current_preset)
		)
		var copied := Library.duplicate_as_user(_current_preset, copy_name)
		if not bool(copied.get("ok", false)):
			return
		_apply_selection(copied["preset"], true)
		return
	_begin_edit()


func _rename_current() -> void:
	if String(_current_entry().get("source", "")) != "user":
		return
	_begin_edit()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _begin_edit() -> void:
	_editing = true
	_dirty = false
	_draft_name = Library.display_name(_current_preset)
	_draft_prefix = String(_current_preset.get("prefix", ""))
	_status_key = ""
	_sync_controls()
	_prefix_edit.grab_focus()


func _save_button_pressed() -> void:
	_save_edits(true)


func _save_edits(commit_node: bool) -> bool:
	var updated := {
		"prompt_preset_version": 1,
		"id": String(_current_preset.get("id", "")),
		"name": _draft_name.strip_edges(),
		"prefix": _draft_prefix,
	}
	var saved := Library.save_user_preset(updated)
	if not bool(saved.get("ok", false)):
		return false
	_current_preset = Dictionary(saved["preset"]).duplicate(true)
	_editing = false
	_dirty = false
	_status_key = "STYLE_PROMPT_STATUS_SAVED"
	_rebuild_entries()
	_sync_controls()
	if commit_node:
		preset_commit_requested.emit(_current_preset.duplicate(true))
	return true


func _delete_current() -> void:
	if String(_current_entry().get("source", "")) != "user":
		return
	if not Library.delete_user_preset(String(_current_preset.get("id", ""))):
		return
	_status_key = "STYLE_PROMPT_STATUS_DELETED"
	_rebuild_entries()
	_sync_controls()


func _copy_text() -> void:
	var text := String(_current_preset.get("prefix", ""))
	text_copy_requested.emit(text)
	DisplayServer.clipboard_set(text)
	_status_key = "STYLE_PROMPT_STATUS_TEXT_COPIED"
	_sync_controls()


func _on_name_changed(value: String) -> void:
	if _suppress_changes:
		return
	_draft_name = value
	_dirty = true
	_status_key = ""
	_sync_dirty_controls()


func _on_prefix_changed() -> void:
	if _suppress_changes:
		return
	_draft_prefix = _prefix_edit.text
	_dirty = true
	_status_key = ""
	_sync_dirty_controls()


func _sync_dirty_controls() -> void:
	_save_button.disabled = _draft_name.strip_edges().is_empty()
	_status_label.text = _status_text()


func _restore_editor_focus() -> void:
	if not _editing:
		return
	if _last_editor_focus == &"name":
		_name_edit.grab_focus()
	else:
		_prefix_edit.grab_focus()


func _on_editor_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		_editing = false
		_dirty = false
		_draft_name = Library.display_name(_current_preset)
		_draft_prefix = String(_current_preset.get("prefix", ""))
		_sync_controls()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER and event.is_command_or_control_pressed():
		_save_edits(true)
		get_viewport().set_input_as_handled()


func _status_text() -> String:
	if _dirty:
		return Strings.text("STYLE_PROMPT_STATUS_UNSAVED")
	match _status_key:
		"STYLE_PROMPT_STATUS_COPIED":
			return Strings.text("STYLE_PROMPT_STATUS_COPIED")
		"STYLE_PROMPT_STATUS_DELETED":
			return Strings.text("STYLE_PROMPT_STATUS_DELETED")
		"STYLE_PROMPT_STATUS_SAVED":
			return Strings.text("STYLE_PROMPT_STATUS_SAVED")
		"STYLE_PROMPT_STATUS_TEXT_COPIED":
			return Strings.text("STYLE_PROMPT_STATUS_TEXT_COPIED")
		_:
			return ""


func _source_text(source: String) -> String:
	match source:
		"builtin":
			return Strings.text("STYLE_PROMPT_SOURCE_BUILTIN")
		"plugin":
			return Strings.text("STYLE_PROMPT_SOURCE_PLUGIN")
		"user":
			return Strings.text("STYLE_PROMPT_SOURCE_USER")
		_:
			return Strings.text("STYLE_PROMPT_SOURCE_SNAPSHOT")
