class_name PFPixelEditorFlowController
extends RefCounted

## Keeps pixel-editor source routing and batch/sprite replacement out of the main UI controller.

var _canvas: Control = null
var _status: Label = null
var _editor: ConfirmationDialog = null


func setup(canvas: Control, status: Label, editor: ConfirmationDialog) -> void:
	_canvas = canvas
	_status = status
	_editor = editor
	_editor.asset_saved.connect(_on_asset_saved)


func open_selected() -> bool:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.size() == 1:
		return open_asset(String(snapshots[0]["data"].get("asset_id", "")), "")
	for item_value in _canvas.export_canvas_data()["items"]:
		var item: Dictionary = item_value
		var item_id := String(item.get("id", ""))
		if not _canvas.get_selected_ids().has(item_id):
			continue
		var ids: Array = _canvas._get_batch_asset_ids(item_id, true)
		if not ids.is_empty():
			return open_asset(String(ids[0]), item_id)
	_status.text = PFStrings.EDITOR_SELECT_ASSET
	return false


func open_asset(asset_id: String, batch_id: String) -> bool:
	if _editor.open_asset(asset_id, batch_id):
		return true
	_status.text = PFStrings.EDITOR_OPEN_FAILED
	return false


func _on_asset_saved(old_asset_id: String, new_asset_id: String, batch_id: String) -> void:
	if batch_id.is_empty():
		_canvas._replace_asset_reference(old_asset_id, new_asset_id)
	else:
		var ids: Array = _canvas._get_batch_asset_ids(batch_id)
		for index in range(ids.size()):
			if String(ids[index]) == old_asset_id:
				ids[index] = new_asset_id
		_canvas._replace_batch_asset_ids(batch_id, ids, true)
	_status.text = PFStrings.EDITOR_SAVED
