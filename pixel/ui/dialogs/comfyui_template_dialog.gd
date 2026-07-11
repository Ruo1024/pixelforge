class_name PFComfyUITemplateDialog
extends ConfirmationDialog

## Imports ComfyUI API JSON and lets users bind PF request fields to node input paths.

const Strings := preload("res://ui/shell/strings.gd")
const Templates := preload("res://plugins/bridge_comfyui/workflow_template.gd")

const FIELDS := [
	"prompt", "negative_prompt", "seed", "width", "height", "batch", "ref_image", "lora"
]

var _workflow := {}
var _slots: Array = []
var _bindings := {}
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _slot_list: ItemList = null
var _field_options: OptionButton = null
var _status: Label = null
var _file_dialog: FileDialog = null


func _ready() -> void:
	title = Strings.DIALOG_COMFY_TEMPLATES
	ok_button_text = Strings.ACTION_CLOSE
	min_size = Vector2i(820, 620)
	_build_ui()


func show_manager() -> void:
	_status.text = Strings.COMFY_TEMPLATE_HELP
	popup_centered()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var top := HFlowContainer.new()
	root.add_child(top)
	_add_button(
		top, Strings.COMFY_IMPORT_WORKFLOW, func() -> void: _file_dialog.popup_centered_ratio()
	)
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = Strings.COMFY_TEMPLATE_ID
	top.add_child(_id_edit)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Strings.COMFY_TEMPLATE_NAME
	top.add_child(_name_edit)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_slot_list = ItemList.new()
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list.item_selected.connect(_on_slot_selected)
	body.add_child(_slot_list)
	var binding_panel := VBoxContainer.new()
	binding_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(binding_panel)
	_field_options = OptionButton.new()
	for field in FIELDS:
		_field_options.add_item(field)
	binding_panel.add_child(_field_options)
	_add_button(binding_panel, Strings.COMFY_BIND_FIELD, _bind_selected)
	_add_button(binding_panel, Strings.COMFY_SAVE_TEMPLATE, _save_template)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binding_panel.add_child(_status)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.json ; ComfyUI API Workflow JSON"])
	_file_dialog.file_selected.connect(_load_workflow)
	add_child(_file_dialog)


func _load_workflow(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_status.text = Strings.COMFY_WORKFLOW_INVALID
		return
	_workflow = parsed
	_slots = Templates.discover_slots(_workflow)
	_bindings.clear()
	_id_edit.text = path.get_file().get_basename().to_snake_case()
	_name_edit.text = path.get_file().get_basename()
	_slot_list.clear()
	for slot in _slots:
		_slot_list.add_item("%s  →  %s" % [slot["path"], slot["field"]])
		_slot_list.set_item_metadata(_slot_list.item_count - 1, slot)
		if not _bindings.has(slot["field"]):
			_bindings[slot["field"]] = slot["path"]
	_status.text = Strings.COMFY_SLOTS_FOUND % _slots.size()


func _on_slot_selected(index: int) -> void:
	var slot: Dictionary = _slot_list.get_item_metadata(index)
	var field_index := FIELDS.find(String(slot.get("field", "prompt")))
	_field_options.select(maxi(0, field_index))


func _bind_selected() -> void:
	var selected := _slot_list.get_selected_items()
	if selected.is_empty():
		return
	var slot: Dictionary = _slot_list.get_item_metadata(selected[0])
	var field := String(_field_options.get_item_text(_field_options.selected))
	_bindings[field] = String(slot["path"])
	_status.text = Strings.COMFY_BOUND % [field, slot["path"]]


func _save_template() -> void:
	var provider: PFProvider = ProviderService.get_provider("comfyui")
	if provider == null or _workflow.is_empty():
		_status.text = Strings.COMFY_WORKFLOW_INVALID
		return
	var template := Templates.import_api_workflow(
		_workflow, _id_edit.text.strip_edges(), _name_edit.text.strip_edges(), _bindings
	)
	var result: Dictionary = provider.save_template(template)
	_status.text = (
		Strings.COMFY_TEMPLATE_SAVED
		if result.get("ok", false)
		else String(result.get("message", Strings.COMFY_WORKFLOW_INVALID))
	)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
