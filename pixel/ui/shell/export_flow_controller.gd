class_name PFExportFlowController
extends Node

## PNG / spritesheet 导出交互：覆盖确认、结果摘要、失败产物说明与打开目录入口。

const Strings := preload("res://ui/shell/strings.gd")
const Exporter := preload("res://services/exporter.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")

var _status_label: Label = null
var _file_dialog: FileDialog = null
var _overwrite_dialog: ConfirmationDialog = null
var _notice_dialog: AcceptDialog = null
var _open_folder_button: Button = null
var _pending_snapshots: Array = []
var _pending_path := ""
var _last_output_path := ""


func setup(dialog_parent: Node, bottom_bar: Control, status_label: Label) -> void:
	_status_label = status_label
	_file_dialog = FileDialog.new()
	_file_dialog.name = "ExportDialog"
	DialogScalePolicy.configure_file_dialog(_file_dialog)
	_file_dialog.title = Strings.DIALOG_EXPORT_PNG
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.filters = PackedStringArray(["*.png ; PNG Image"])
	_file_dialog.overwrite_warning_enabled = false
	_file_dialog.file_selected.connect(choose_path)
	dialog_parent.add_child(_file_dialog)

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.name = "ExportOverwriteDialog"
	_overwrite_dialog.title = Strings.DIALOG_EXPORT_OVERWRITE_TITLE
	_overwrite_dialog.get_ok_button().text = Strings.ACTION_OVERWRITE
	_overwrite_dialog.confirmed.connect(_perform_pending_export)
	_overwrite_dialog.canceled.connect(cancel_overwrite)
	dialog_parent.add_child(_overwrite_dialog)

	_notice_dialog = AcceptDialog.new()
	_notice_dialog.name = "ExportNoticeDialog"
	_notice_dialog.title = Strings.DIALOG_EXPORT_RESULT_TITLE
	dialog_parent.add_child(_notice_dialog)

	_open_folder_button = Button.new()
	_open_folder_button.name = "OpenExportFolderButton"
	_open_folder_button.text = Strings.ACTION_OPEN_EXPORT_FOLDER
	_open_folder_button.visible = false
	_open_folder_button.pressed.connect(open_output_folder)
	bottom_bar.add_child(_open_folder_button)


func request_export(snapshots: Array, default_file: String) -> void:
	_pending_snapshots = snapshots.duplicate()
	if _pending_snapshots.is_empty():
		_status_label.text = Strings.STATUS_EXPORT_EMPTY
		return
	_file_dialog.current_file = default_file
	_file_dialog.popup_centered_ratio(0.7)


func choose_path(path: String) -> void:
	if _pending_snapshots.is_empty():
		return
	_file_dialog.hide()
	_pending_path = path if path.to_lower().ends_with(".png") else path + ".png"
	var conflicts := _existing_output_paths(_pending_path, _pending_snapshots.size())
	if not conflicts.is_empty():
		_overwrite_dialog.dialog_text = (
			Strings.DIALOG_EXPORT_OVERWRITE_BODY_FORMAT % "\n".join(conflicts)
		)
		_overwrite_dialog.popup_centered()
		return
	_perform_pending_export()


func cancel_overwrite() -> void:
	_pending_path = ""
	_overwrite_dialog.hide()
	_status_label.text = Strings.STATUS_EXPORT_CANCELED


func open_output_folder() -> void:
	if _last_output_path.is_empty():
		return
	OS.shell_show_in_file_manager(_global_path(_last_output_path), true)


func _perform_pending_export() -> void:
	if _pending_path.is_empty() or _pending_snapshots.is_empty():
		return
	var target_path := _pending_path
	var result := _export_to_path(target_path)
	if bool(result.get("ok", false)):
		_show_success(result)
	else:
		_show_failure(result)
	_pending_snapshots.clear()
	_pending_path = ""


func _export_to_path(target_path: String) -> Dictionary:
	if _pending_snapshots.size() == 1:
		var error := Exporter.export_png(_pending_snapshots[0]["image"], target_path)
		return {
			"ok": error == OK,
			"error": error,
			"expected": [target_path],
			"created": [target_path] if error == OK else [],
		}

	var export_items := []
	for index in range(_pending_snapshots.size()):
		var snapshot: Dictionary = _pending_snapshots[index]
		var data: Dictionary = snapshot["data"]
		(
			export_items
			. append(
				{
					"name": String(data.get("asset_id", "sprite_%02d" % (index + 1))).left(16),
					"image": snapshot["image"],
				}
			)
		)
	var sheet_result: Dictionary = Exporter.export_spritesheet(
		export_items, target_path, {"columns": 0, "padding": 1, "image": target_path.get_file()}
	)
	var json_path := target_path.get_basename() + ".json"
	var created := []
	for output_path in [target_path, json_path]:
		if FileAccess.file_exists(output_path):
			created.append(output_path)
	return {
		"ok": bool(sheet_result.get("ok", false)),
		"error": int(sheet_result.get("error", OK)),
		"expected": [target_path, json_path],
		"created": created,
	}


func _show_success(result: Dictionary) -> void:
	var created: Array = result.get("created", [])
	_last_output_path = String(created[0])
	_open_folder_button.visible = true
	var display_paths := []
	for path in created:
		display_paths.append(_display_path(String(path)))
	_status_label.text = Strings.STATUS_EXPORT_SUCCESS_FORMAT % ", ".join(display_paths)


func _show_failure(result: Dictionary) -> void:
	var message := format_failure_summary(
		result.get("expected", []), result.get("created", []), int(result.get("error", FAILED))
	)
	_status_label.text = message
	_notice_dialog.dialog_text = message
	_notice_dialog.popup_centered()
	_open_folder_button.visible = not Array(result.get("created", [])).is_empty()
	if _open_folder_button.visible:
		_last_output_path = String(Array(result["created"])[0])


static func format_failure_summary(expected: Array, created: Array, error: Error) -> String:
	var created_text := Strings.EXPORT_NONE_CREATED
	if not created.is_empty():
		created_text = Strings.EXPORT_CREATED_FORMAT % ", ".join(created)
	var missing := []
	for path in expected:
		if not created.has(path):
			missing.append(String(path))
	var missing_text := Strings.EXPORT_MISSING_FORMAT % ", ".join(missing)
	return (
		Strings.STATUS_EXPORT_FAILED_DETAIL_FORMAT
		% [error_string(error), created_text, missing_text]
	)


func _existing_output_paths(png_path: String, snapshot_count: int) -> Array:
	var paths := [png_path]
	if snapshot_count > 1:
		paths.append(png_path.get_basename() + ".json")
	var existing := []
	for path in paths:
		if FileAccess.file_exists(path):
			existing.append(_display_path(path))
	return existing


func _display_path(path: String) -> String:
	return _global_path(path)


func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
