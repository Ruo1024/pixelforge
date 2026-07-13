class_name PFWorkspaceSettingsController
extends Node

## 工作区设置入口；语言控件复用本地化服务并保持在全局动作区。

const LanguageSelectorScript := preload("res://ui/widgets/language_selector.gd")
const Strings := preload("res://ui/shell/strings.gd")

var _button: Button = null
var _dialog: ConfirmationDialog = null


func setup(button_parent: Control, action_id: String = "") -> void:
	_button = Button.new()
	_button.name = "SettingsButton"
	_button.text = (
		Strings.text("ACTION_MORE") if not action_id.is_empty() else Strings.text("SETTINGS_ACTION")
	)
	_button.focus_mode = Control.FOCUS_NONE
	if not action_id.is_empty():
		_button.set_meta("action_id", action_id)
	_button.pressed.connect(_show_settings)
	button_parent.add_child(_button)

	_dialog = ConfirmationDialog.new()
	_dialog.name = "WorkspaceSettingsDialog"
	_dialog.title = Strings.text("SETTINGS_TITLE")
	var selector := LanguageSelectorScript.new()
	selector.name = "LanguageSelector"
	_dialog.add_child(selector)
	add_child(_dialog)
	LocalizationService.language_changed.connect(_refresh_text)
	_refresh_text("", "")


func _show_settings() -> void:
	_dialog.reset_size()
	_dialog.popup_centered()


func _refresh_text(_preference: String, _locale: String) -> void:
	_button.text = (
		Strings.text("ACTION_MORE")
		if not String(_button.get_meta("action_id", "")).is_empty()
		else Strings.text("SETTINGS_ACTION")
	)
	_dialog.title = Strings.text("SETTINGS_TITLE")
	_dialog.ok_button_text = Strings.text("ACTION_OK")
	_dialog.cancel_button_text = Strings.text("ACTION_CANCEL")
