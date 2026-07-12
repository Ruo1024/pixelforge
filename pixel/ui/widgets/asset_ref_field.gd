class_name PFAssetRefField
extends VBoxContainer

## Shared project-asset selector for every `asset_ref` schema field.

signal value_changed(asset_id: String)
signal import_requested

const Strings := preload("res://ui/shell/strings.gd")

var _option: OptionButton = null
var _import_button: Button = null
var _clear_button: Button = null
var _asset_ids: Array[String] = []
var _value := ""
var _suppress_signal := false


func _ready() -> void:
	_build()


func set_value(asset_id: String) -> void:
	_build()
	_value = asset_id
	_refresh_options()


func get_value() -> String:
	return _value


func _build() -> void:
	if _option != null:
		return
	_option = OptionButton.new()
	_option.name = "AssetOption"
	_option.item_selected.connect(_on_item_selected)
	add_child(_option)
	var actions := HBoxContainer.new()
	_import_button = Button.new()
	_import_button.name = "ImportButton"
	_import_button.text = Strings.text("ACTION_IMPORT_REFERENCE")
	_import_button.pressed.connect(func() -> void: import_requested.emit())
	actions.add_child(_import_button)
	_clear_button = Button.new()
	_clear_button.name = "ClearButton"
	_clear_button.text = Strings.text("ACTION_CLEAR_REFERENCE")
	_clear_button.pressed.connect(func() -> void: set_value_and_emit(""))
	actions.add_child(_clear_button)
	add_child(actions)
	_refresh_options()


func set_value_and_emit(asset_id: String) -> void:
	set_value(asset_id)
	value_changed.emit(_value)


func _refresh_options() -> void:
	if _option == null:
		return
	_suppress_signal = true
	_option.clear()
	_asset_ids.clear()
	_add_option(Strings.text("CONTENT_REFERENCE_NONE"), "")
	var metadata: Dictionary = AssetLibrary.get_all_meta()
	var ids: Array = metadata.keys()
	ids.sort()
	for asset_id_value in ids:
		var asset_id := String(asset_id_value)
		var meta: Dictionary = metadata[asset_id]
		_add_option(String(meta.get("name", asset_id.left(8))), asset_id)
	if not _value.is_empty() and not _asset_ids.has(_value):
		_add_option(Strings.text("CONTENT_REFERENCE_MISSING_FORMAT") % _value.left(8), _value)
	_option.select(maxi(0, _asset_ids.find(_value)))
	_clear_button.disabled = _value.is_empty()
	_suppress_signal = false


func _add_option(label: String, asset_id: String) -> void:
	_option.add_item(label)
	_option.set_item_metadata(_option.item_count - 1, asset_id)
	_asset_ids.append(asset_id)


func _on_item_selected(index: int) -> void:
	if _suppress_signal:
		return
	_value = String(_option.get_item_metadata(index))
	_clear_button.disabled = _value.is_empty()
	value_changed.emit(_value)
