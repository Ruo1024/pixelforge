class_name PFWorkspaceSettingsController
extends Node

## 工作区设置入口；语言控件复用本地化服务并保持在全局动作区。

const LanguageSelectorScript := preload("res://ui/widgets/language_selector.gd")
const Strings := preload("res://ui/shell/strings.gd")

var _button: Button = null
var _dialog: ConfirmationDialog = null


func setup(button_parent: Control) -> void:
	_button = Button.new()
	_button.name = "SettingsButton"
	_button.text = Strings.text("SETTINGS_ACTION")
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_show_settings)
	button_parent.add_child(_button)

	_dialog = ConfirmationDialog.new()
	_dialog.name = "WorkspaceSettingsDialog"
	_dialog.title = Strings.text("SETTINGS_TITLE")
	_dialog.add_child(LanguageSelectorScript.new())
	add_child(_dialog)
	LocalizationService.language_changed.connect(_refresh_text)


func _show_settings() -> void:
	_dialog.popup_centered(Vector2i(520, 260))


func _refresh_text(_preference: String, _locale: String) -> void:
	_button.text = Strings.text("SETTINGS_ACTION")
	_dialog.title = Strings.text("SETTINGS_TITLE")
