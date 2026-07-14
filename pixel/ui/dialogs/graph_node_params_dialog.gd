class_name PFGraphNodeParamsDialog
extends ConfirmationDialog

## Graph 节点参数对话框。
## contract: 02-contracts/GRAPH-SCHEMA.md §3；控件只由 get_param_schema() 生成。

signal params_confirmed(graph_id: String, node_id: String, params: Dictionary)
signal asset_import_requested(graph_id: String, node_id: String, param_key: String)

const Strings := preload("res://ui/shell/strings.gd")
const AssetRefFieldScript := preload("res://ui/widgets/asset_ref_field.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")

const DIALOG_WIDTH := 480
const DIALOG_HEIGHT := 420
const CONTROL_HEIGHT := 30
const MULTILINE_HEIGHT := 150
const ROOT_SEPARATION := 8
const ROW_SEPARATION := 2
const FLEXIBLE_WIDTH := 0

var _graph_id := ""
var _node_id := ""
var _node: PFNode = null
var _base_params := {}
var _fields := {}
var _root: VBoxContainer = null
var _built := false


func _ready() -> void:
	_ensure_built()


func configure_for_node(
	graph_id: String, node_id: String, node: PFNode, params: Dictionary
) -> void:
	_ensure_built()
	_graph_id = graph_id
	_node_id = node_id
	_node = node
	_base_params = params.duplicate(true)
	title = (Strings.text("DIALOG_GRAPH_NODE_PARAMS_TITLE_FORMAT") % _localized_node_name(node))
	_clear_fields()
	for schema in node.get_param_schema():
		_add_schema_field(schema, _base_params.get(schema.get("key", ""), schema.get("default")))


func get_params() -> Dictionary:
	var result := _base_params.duplicate(true)
	for key in _fields.keys():
		result[String(key)] = _control_value(_fields[key])
	return _node.validate_params(result) if _node != null else result


func set_param_value(key: String, value: Variant) -> bool:
	if not _fields.has(key):
		return false
	_set_control_value(_fields[key], value)
	return true


func get_param_value(key: String) -> Variant:
	if not _fields.has(key):
		return null
	return _control_value(_fields[key])


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	ok_button_text = Strings.text("ACTION_APPLY")
	cancel_button_text = Strings.text("ACTION_CANCEL")
	min_size = Vector2i(DIALOG_WIDTH, DIALOG_HEIGHT)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(_root)
	confirmed.connect(_emit_params)
	LocalizationService.language_changed.connect(_on_language_changed)


func _emit_params() -> void:
	params_confirmed.emit(_graph_id, _node_id, get_params())


func _clear_fields() -> void:
	_fields.clear()
	for child in _root.get_children():
		_root.remove_child(child)
		child.free()


func _add_schema_field(schema: Dictionary, value: Variant) -> void:
	var key := String(schema.get("key", ""))
	if key.is_empty():
		return
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var label := Label.new()
	label.text = _label_text(schema)
	row.add_child(label)
	var control := _make_control(schema, value)
	row.add_child(control)
	_root.add_child(row)
	_fields[key] = control


func _make_control(schema: Dictionary, value: Variant) -> Control:
	var kind := String(schema.get("kind", ""))
	match kind:
		PFNode.KIND_INT, PFNode.KIND_FLOAT, PFNode.KIND_SEED:
			var spin := SpinBox.new()
			spin.min_value = float(schema.get("min", -2147483648))
			spin.max_value = float(schema.get("max", 2147483647))
			spin.step = 1.0 if kind != PFNode.KIND_FLOAT else 0.01
			spin.value = float(value)
			spin.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
			return spin
		PFNode.KIND_BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(value)
			return check
		PFNode.KIND_TEXT_MULTILINE:
			var edit := TextEdit.new()
			edit.text = String(value)
			edit.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, MULTILINE_HEIGHT)
			return edit
		PFNode.KIND_ENUM, PFNode.KIND_PROVIDER:
			var options := OptionButton.new()
			var values: Array = schema.get("options", [])
			if kind == PFNode.KIND_PROVIDER:
				values = ProviderService.get_selectable_provider_ids()
			if values.is_empty():
				values = [String(value)]
			for option in values:
				options.add_item(String(option))
			var selected := values.find(String(value))
			options.select(maxi(0, selected))
			options.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
			return options
		PFNode.KIND_ASSET_REF:
			var field := AssetRefFieldScript.new()
			field.set_value(String(value))
			field.import_requested.connect(
				func() -> void:
					asset_import_requested.emit(_graph_id, _node_id, String(schema["key"]))
			)
			return field
		_:
			var edit := LineEdit.new()
			edit.text = String(value)
			edit.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
			return edit


func _control_value(control: Control) -> Variant:
	var value: Variant = null
	if control is SpinBox:
		value = float(control.value) if control.step < 1.0 else int(control.value)
	elif control is CheckBox:
		value = control.button_pressed
	elif control is TextEdit:
		value = control.text
	elif control is OptionButton:
		value = control.get_item_text(control.selected)
	elif control is LineEdit:
		value = control.text
	elif control is PFAssetRefField:
		value = control.get_value()
	return value


func _set_control_value(control: Control, value: Variant) -> void:
	if control is SpinBox:
		control.value = float(value)
	elif control is CheckBox:
		control.button_pressed = bool(value)
	elif control is TextEdit:
		control.text = String(value)
	elif control is OptionButton:
		var index := -1
		for option_index in range(control.item_count):
			if control.get_item_text(option_index) == String(value):
				index = option_index
				break
		if index < 0:
			control.add_item(String(value))
			index = control.item_count - 1
		control.select(index)
	elif control is LineEdit:
		control.text = String(value)
	elif control is PFAssetRefField:
		control.set_value(String(value))


func _label_text(schema: Dictionary) -> String:
	return SchemaTextResolverScript.resolve(schema, "label_key")


func _localized_node_name(node: PFNode) -> String:
	var keys := {
		"object_list": "NODE_OBJECT_LIST",
		"image_input": "NODE_IMAGE_INPUT",
		"prompt_preset": "NODE_PROMPT_PRESET",
		"pixel_cleanup": "NODE_PIXEL_CLEANUP",
		"ai_generate": "NODE_AI_GENERATE",
		"batch": "NODE_BATCH",
	}
	var key := String(keys.get(node.get_type(), ""))
	return (
		Strings.text(key, node.get_display_name())
		if not key.is_empty()
		else node.get_display_name()
	)


func _on_language_changed(_preference: String, _locale: String) -> void:
	ok_button_text = Strings.text("ACTION_APPLY")
	cancel_button_text = Strings.text("ACTION_CANCEL")
	if _node == null:
		return
	var current_params := get_params()
	configure_for_node(_graph_id, _node_id, _node, current_params)
