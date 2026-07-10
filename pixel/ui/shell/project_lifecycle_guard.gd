class_name PFProjectLifecycleGuard
extends Node

## 破坏性项目动作的统一未保存守卫。
## New / Open / Quit 共用 Save / Discard / Cancel 状态机；Save 失败时保留待执行动作。

signal action_ready(action_id: String, payload: Variant)
signal save_requested

const Strings := preload("res://ui/shell/strings.gd")

const ACTION_NEW := "new"
const ACTION_OPEN := "open"
const ACTION_QUIT := "quit"
const ACTION_RECOVER := "recover"
const DISCARD_ACTION := &"discard"

var _project_service: Variant = null
var _dialog: ConfirmationDialog = null
var _pending_action := {}


func setup(project_service: Variant) -> void:
	_project_service = project_service
	_dialog = ConfirmationDialog.new()
	_dialog.name = "UnsavedChangesDialog"
	_dialog.title = Strings.DIALOG_UNSAVED_TITLE
	_dialog.get_ok_button().text = Strings.DIALOG_SAVE
	_dialog.get_cancel_button().text = Strings.DIALOG_CANCEL
	_dialog.add_button(Strings.DIALOG_DISCARD, true, DISCARD_ACTION)
	_dialog.confirmed.connect(choose_save)
	_dialog.canceled.connect(cancel_pending)
	_dialog.custom_action.connect(_on_custom_action)
	add_child(_dialog)


func request_action(action_id: String, payload: Variant = null) -> bool:
	if not _is_dirty():
		action_ready.emit(action_id, payload)
		return false

	_pending_action = {"id": action_id, "payload": payload}
	_dialog.dialog_text = Strings.DIALOG_UNSAVED_BODY_FORMAT % _action_display_name(action_id)
	_dialog.popup_centered()
	return true


func choose_save() -> void:
	if _pending_action.is_empty():
		return
	_dialog.hide()
	save_requested.emit()


func choose_discard() -> void:
	if _pending_action.is_empty():
		return
	var pending := _take_pending_action()
	_dialog.hide()
	action_ready.emit(String(pending["id"]), pending.get("payload", null))


func cancel_pending() -> void:
	_pending_action.clear()
	if _dialog != null:
		_dialog.hide()


func notify_save_result(error: Error) -> void:
	if _pending_action.is_empty():
		return
	if error != OK:
		_dialog.popup_centered()
		return

	var pending := _take_pending_action()
	action_ready.emit(String(pending["id"]), pending.get("payload", null))


func has_pending_action() -> bool:
	return not _pending_action.is_empty()


func get_pending_action_id() -> String:
	return String(_pending_action.get("id", ""))


func _is_dirty() -> bool:
	return (
		_project_service != null
		and _project_service.current_project != null
		and bool(_project_service.current_project.dirty)
	)


func _take_pending_action() -> Dictionary:
	var pending := _pending_action.duplicate(true)
	_pending_action.clear()
	return pending


func _on_custom_action(action: StringName) -> void:
	if action == DISCARD_ACTION:
		choose_discard()


func _action_display_name(action_id: String) -> String:
	match action_id:
		ACTION_NEW:
			return Strings.ACTION_NEW
		ACTION_OPEN:
			return Strings.ACTION_OPEN
		ACTION_QUIT:
			return Strings.ACTION_QUIT
		ACTION_RECOVER:
			return Strings.ACTION_RECOVER
		_:
			return action_id
