class_name PFImportFlowController
extends Node

## 图片导入交互：稳定落点、原子预检、失败重试、空画布提示与最近导入聚焦。

signal add_input_requested
signal open_example_requested
signal reference_asset_imported(target: Dictionary, asset_id: String)

const Strings := preload("res://ui/shell/strings.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const EmptyImportHintScript := preload("res://ui/shell/empty_canvas_import_hint.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const Log := preload("res://core/util/log_util.gd")

const ITEM_GAP := 8
const LARGE_IMAGE_PIXELS := 1024 * 1024

var _canvas: Control = null
var _status_label: Label = null
var _import_dialog: FileDialog = null
var _reference_dialog: FileDialog = null
var _empty_import_hint: Control = null
var _import_error_dialog: ConfirmationDialog = null
var _retry_import_files := PackedStringArray()
var _reference_target := {}
var _retry_reference_path := ""
var _retry_reference_target := {}
var _last_import_item_ids: Array[String] = []
var _file_menu_popup: PopupMenu = null
var _focus_menu_id := -1
var _retry_menu_id := -1


func setup(canvas: Control, status_label: Label, dialog_parent: Node) -> void:
	_canvas = canvas
	_status_label = status_label
	_create_dialogs(dialog_parent)
	_create_empty_hint()
	_canvas.canvas_changed.connect(refresh_empty_hint)
	ProjectService.project_loaded.connect(_on_project_loaded)
	LocalizationService.language_changed.connect(_refresh_localized_text)


func configure_file_menu(popup: PopupMenu, focus_menu_id: int, retry_menu_id: int) -> void:
	_file_menu_popup = popup
	_focus_menu_id = focus_menu_id
	_retry_menu_id = retry_menu_id
	_set_menu_enabled(_focus_menu_id, false)
	_set_menu_enabled(_retry_menu_id, false)


func show_import_dialog() -> void:
	_import_dialog.popup_centered_ratio(0.7)


func show_reference_import_dialog(target: Dictionary = {}) -> void:
	_reference_target = target.duplicate(true)
	_reference_dialog.popup_centered_ratio(0.7)


func import_files_at_mouse(files: PackedStringArray) -> Dictionary:
	return _import_image_files(files, _canvas.get_mouse_world_position())


func import_files_from_dialog(files: PackedStringArray) -> Dictionary:
	return _import_image_files(files, stable_import_anchor())


func retry_import() -> void:
	if not _retry_reference_path.is_empty():
		_import_reference_file(_retry_reference_path, _retry_reference_target)
		return
	if _retry_import_files.is_empty():
		return
	_import_image_files(_retry_import_files, stable_import_anchor())


func focus_last_import() -> void:
	var items := _last_import_items()
	if items.is_empty():
		return
	_focus_canvas_on_bounds(_bounds_for_items(items))
	_canvas.select_ids(_last_import_item_ids)
	_status_label.text = Strings.text("STATUS_IMPORT_FOCUSED")


func stable_import_anchor() -> Vector2:
	return _canvas.screen_to_world(_canvas.size * 0.5).round()


func refresh_empty_hint() -> void:
	if _empty_import_hint != null:
		_empty_import_hint.set_canvas_empty(_canvas.get_item_count() == 0)


func _create_dialogs(dialog_parent: Node) -> void:
	_import_dialog = FileDialog.new()
	_import_dialog.name = "ImportImagesDialog"
	DialogScalePolicy.configure_file_dialog(_import_dialog)
	_import_dialog.title = Strings.text("DIALOG_IMPORT_IMAGES")
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.filters = PackedStringArray(["*.png ; PNG Image", "*.jpg,*.jpeg ; JPEG Image"])
	_import_dialog.files_selected.connect(import_files_from_dialog)
	dialog_parent.add_child(_import_dialog)
	_reference_dialog = FileDialog.new()
	_reference_dialog.name = "ImportReferenceDialog"
	DialogScalePolicy.configure_file_dialog(_reference_dialog)
	_reference_dialog.title = Strings.text("ACTION_IMPORT_REFERENCE")
	_reference_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_reference_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_reference_dialog.filters = _import_dialog.filters
	_reference_dialog.file_selected.connect(
		func(path: String) -> void: _import_reference_file(path, _reference_target)
	)
	dialog_parent.add_child(_reference_dialog)

	_import_error_dialog = ConfirmationDialog.new()
	_import_error_dialog.name = "ImportErrorDialog"
	_import_error_dialog.title = Strings.text("DIALOG_IMPORT_FAILED_TITLE")
	_import_error_dialog.get_ok_button().text = Strings.text("ACTION_RETRY_IMPORT")
	_import_error_dialog.confirmed.connect(retry_import)
	dialog_parent.add_child(_import_error_dialog)


func _create_empty_hint() -> void:
	_empty_import_hint = EmptyImportHintScript.new()
	_empty_import_hint.import_requested.connect(show_import_dialog)
	_empty_import_hint.add_input_requested.connect(func() -> void: add_input_requested.emit())
	_empty_import_hint.open_example_requested.connect(func() -> void: open_example_requested.emit())
	_canvas.add_child(_empty_import_hint)


func _import_image_files(files: PackedStringArray, world_position: Vector2) -> Dictionary:
	_retry_reference_path = ""
	_retry_reference_target.clear()
	var preflight := _decode_all(files)
	var failed_files: Array = preflight["failed_files"]
	var decoded: Array = preflight["decoded"]
	if not failed_files.is_empty() or decoded.is_empty():
		return _report_import_failure(files, failed_files)

	var was_empty: bool = _canvas.get_item_count() == 0
	var imported_asset_ids: Array[String] = []
	var imported_items := []
	var make_batch := decoded.size() > 1
	var drop_position := world_position
	for decoded_item in decoded:
		var file_path := String(decoded_item["path"])
		var image: Image = decoded_item["image"]
		if image.get_width() * image.get_height() > LARGE_IMAGE_PIXELS:
			Log.warn(
				"Large image imported without M1 cleanup",
				{"path": file_path, "size": [image.get_width(), image.get_height()]}
			)
		var asset_name := file_path.get_file().get_basename()
		var asset_id := AssetLibrary.register_image(image, asset_name, {"origin": "imported"})
		imported_asset_ids.append(asset_id)
		if not make_batch:
			var sprite: Node = _canvas.add_sprite_item(image, asset_id, drop_position)
			if sprite != null:
				imported_items.append(sprite)
		drop_position += Vector2(image.get_width() + ITEM_GAP, 0)

	if make_batch:
		var card: Node = _canvas._add_batch_card(
			imported_asset_ids, world_position, Strings.BATCH_DEFAULT_LABEL
		)
		if card != null:
			imported_items.append(card)

	_last_import_item_ids.clear()
	for item in imported_items:
		_last_import_item_ids.append(String(item.item_id))
	_retry_import_files.clear()
	_set_menu_enabled(_retry_menu_id, false)
	_set_menu_enabled(_focus_menu_id, not _last_import_item_ids.is_empty())
	if was_empty and not imported_items.is_empty():
		_focus_canvas_on_bounds(_bounds_for_items(imported_items))
	_status_label.text = Strings.text("STATUS_IMPORT_DONE_FORMAT") % imported_asset_ids.size()
	refresh_empty_hint()
	return {
		"ok": true,
		"failed_files": [],
		"asset_ids": imported_asset_ids,
		"item_ids": _last_import_item_ids.duplicate(),
		"auto_focused": was_empty,
		"anchor": world_position,
	}


func _import_reference_file(path: String, target: Dictionary) -> Dictionary:
	var preflight := _decode_all(PackedStringArray([path]))
	if not Array(preflight["failed_files"]).is_empty() or Array(preflight["decoded"]).is_empty():
		_retry_reference_path = path
		_retry_reference_target = target.duplicate(true)
		return _report_import_failure(PackedStringArray([path]), Array(preflight["failed_files"]))
	var decoded: Dictionary = Array(preflight["decoded"])[0]
	var image: Image = decoded["image"]
	var asset_id := AssetLibrary.register_image(
		image, path.get_file().get_basename(), {"origin": "imported"}
	)
	_retry_reference_path = ""
	_retry_reference_target.clear()
	_retry_import_files.clear()
	reference_asset_imported.emit(target.duplicate(true), asset_id)
	_status_label.text = Strings.text("STATUS_IMPORT_DONE_FORMAT") % 1
	return {"ok": true, "asset_id": asset_id, "target": target.duplicate(true)}


func _decode_all(files: PackedStringArray) -> Dictionary:
	var decoded := []
	var failed_files := []
	for file_path in files:
		var path := String(file_path)
		if not _is_supported_image_path(path):
			failed_files.append(path)
			continue
		var image: Image = FileIOScript.load_png(path)
		if image == null:
			failed_files.append(path)
			continue
		decoded.append({"path": path, "image": image})
	return {"decoded": decoded, "failed_files": failed_files}


func _report_import_failure(files: PackedStringArray, failed_files: Array) -> Dictionary:
	_retry_import_files = files.duplicate()
	_set_menu_enabled(_retry_menu_id, true)
	var displayed_failures: Array = failed_files if not failed_files.is_empty() else Array(files)
	var failed_text := "\n".join(displayed_failures)
	_status_label.text = (
		Strings.text("STATUS_IMPORT_FAILED_FORMAT") % failed_text.replace("\n", ", ")
	)
	_import_error_dialog.dialog_text = (
		Strings.text("DIALOG_IMPORT_FAILED_BODY_FORMAT") % failed_text
	)
	_import_error_dialog.popup_centered()
	return {"ok": false, "failed_files": displayed_failures, "asset_ids": [], "item_ids": []}


func _refresh_localized_text(_preference: String, _locale: String) -> void:
	_import_dialog.title = Strings.text("DIALOG_IMPORT_IMAGES")
	_reference_dialog.title = Strings.text("ACTION_IMPORT_REFERENCE")
	_import_error_dialog.title = Strings.text("DIALOG_IMPORT_FAILED_TITLE")
	_import_error_dialog.get_ok_button().text = Strings.text("ACTION_RETRY_IMPORT")


func _last_import_items() -> Array:
	var items := []
	for item_id in _last_import_item_ids:
		if _canvas._items_by_id.has(item_id):
			items.append(_canvas._items_by_id[item_id])
	return items


func _focus_canvas_on_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or _canvas.size.is_zero_approx():
		return
	var target_zoom := minf(
		_canvas.size.x * 0.62 / bounds.size.x, _canvas.size.y * 0.62 / bounds.size.y
	)
	_canvas.set_camera_zoom(target_zoom, _canvas.size * 0.5)
	_canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)


func _bounds_for_items(items: Array) -> Rect2:
	var bounds: Rect2 = items[0].get_canvas_bounds()
	for index in range(1, items.size()):
		bounds = bounds.merge(items[index].get_canvas_bounds())
	return bounds


func _set_menu_enabled(item_id: int, enabled: bool) -> void:
	if _file_menu_popup == null or item_id < 0:
		return
	var index := _file_menu_popup.get_item_index(item_id)
	if index >= 0:
		_file_menu_popup.set_item_disabled(index, not enabled)


func _on_project_loaded(_project: Variant) -> void:
	_last_import_item_ids.clear()
	_set_menu_enabled(_focus_menu_id, false)
	call_deferred("refresh_empty_hint")


func _is_supported_image_path(file_path: String) -> bool:
	var lower_path := file_path.to_lower()
	return (
		lower_path.ends_with(".png")
		or lower_path.ends_with(".jpg")
		or lower_path.ends_with(".jpeg")
	)
