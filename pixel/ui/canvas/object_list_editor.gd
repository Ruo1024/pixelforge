class_name PFObjectListEditor
extends VBoxContainer

signal params_commit_requested(params: Dictionary)

const IdUtil := preload("res://core/util/id_util.gd")
const Strings := preload("res://ui/shell/strings.gd")

const PASTE_MIN_SIZE := Vector2(0, 64)
const COUNT_MIN_SIZE := Vector2(76, 30)
const ROW_MENU_MIN_SIZE := Vector2(32, 30)

var _params := {}
var _paste_edit: TextEdit


func setup(params: Dictionary) -> void:
	_params = params.duplicate(true)
	_build()


func _build() -> void:
	var rows := _rows()
	var count_label := Label.new()
	count_label.name = "ItemCount"
	count_label.text = (
		Strings.text("CONTENT_OBJECT_CARD_SUMMARY")
		% [_enabled_count(rows), rows.size(), _expected_count(rows)]
	)
	add_child(count_label)
	var search := LineEdit.new()
	search.name = "ObjectFilter"
	search.placeholder_text = Strings.text("CONTENT_OBJECT_FILTER_PLACEHOLDER")
	add_child(search)
	var scroll := ScrollContainer.new()
	scroll.name = "ObjectRowsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var row_list := VBoxContainer.new()
	row_list.name = "ObjectRows"
	row_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(rows.size()):
		row_list.add_child(_row_control(rows, index))
	scroll.add_child(row_list)
	add_child(scroll)
	search.text_changed.connect(_filter_rows.bind(row_list, rows))
	var add_button := Button.new()
	add_button.name = "AddObjectRow"
	add_button.text = Strings.text("ACTION_ADD_OBJECT_ROW")
	add_button.pressed.connect(_add_row.bind(rows))
	add_child(add_button)
	var paste_toggle := Button.new()
	paste_toggle.name = "PasteRowsToggle"
	paste_toggle.text = Strings.text("ACTION_PASTE_OBJECT_ROWS")
	paste_toggle.toggle_mode = true
	add_child(paste_toggle)
	_paste_edit = TextEdit.new()
	_paste_edit.name = "ObjectEdit"
	_paste_edit.custom_minimum_size = PASTE_MIN_SIZE
	_paste_edit.placeholder_text = Strings.text("CONTENT_OBJECT_PASTE_PLACEHOLDER")
	_paste_edit.visible = false
	_paste_edit.focus_exited.connect(_commit_pasted_rows)
	add_child(_paste_edit)
	paste_toggle.toggled.connect(func(value: bool) -> void: _paste_edit.visible = value)


func _row_control(rows: Array, index: int) -> Control:
	var row_data: Dictionary = rows[index]
	var row := HBoxContainer.new()
	row.name = "ObjectRow%d" % index
	var enabled := CheckBox.new()
	enabled.name = "ObjectEnabled%d" % index
	enabled.button_pressed = bool(row_data.get("enabled", true))
	enabled.toggled.connect(func(value: bool) -> void: _commit_row(rows, index, {"enabled": value}))
	row.add_child(enabled)
	var text_edit := LineEdit.new()
	text_edit.name = "ObjectText%d" % index
	text_edit.text = String(row_data.get("text", ""))
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.text_submitted.connect(
		func(value: String) -> void: _commit_row(rows, index, {"text": value})
	)
	text_edit.focus_exited.connect(
		func() -> void: _commit_row(rows, index, {"text": text_edit.text})
	)
	row.add_child(text_edit)
	var count := SpinBox.new()
	count.name = "ObjectCount%d" % index
	count.min_value = 1
	count.max_value = 999
	count.value = int(row_data.get("count", 1))
	count.custom_minimum_size = COUNT_MIN_SIZE
	count.value_changed.connect(
		func(value: float) -> void: _commit_row(rows, index, {"count": int(value)})
	)
	row.add_child(count)
	var menu := MenuButton.new()
	menu.name = "ObjectMenu%d" % index
	menu.text = "..."
	menu.custom_minimum_size = ROW_MENU_MIN_SIZE
	menu.get_popup().add_item(Strings.text("ACTION_REMOVE"), 0)
	menu.get_popup().id_pressed.connect(func(_id: int) -> void: _remove_row(rows, index))
	row.add_child(menu)
	return row


func _filter_rows(query: String, row_list: VBoxContainer, rows: Array) -> void:
	var normalized := query.strip_edges().to_lower()
	for index in range(row_list.get_child_count()):
		row_list.get_child(index).visible = (
			normalized.is_empty() or normalized in String(rows[index].get("text", "")).to_lower()
		)


func _commit_pasted_rows() -> void:
	var pasted := _paste_edit.text
	if pasted.strip_edges().is_empty():
		return
	var rows := _rows()
	for raw_line in pasted.split("\n", false):
		var text := String(raw_line).strip_edges()
		if not text.is_empty():
			rows.append({"id": IdUtil.uuid_v4(), "text": text, "count": 1, "enabled": true})
	_emit_rows(rows)


func _commit_row(rows: Array, index: int, changes: Dictionary) -> void:
	var updated := rows.duplicate(true)
	updated[index].merge(changes, true)
	_emit_rows(updated)


func _set_all_enabled(rows: Array, enabled: bool) -> void:
	var updated := rows.duplicate(true)
	for row in updated:
		row["enabled"] = enabled
	_emit_rows(updated)


func _add_row(rows: Array) -> void:
	var updated := rows.duplicate(true)
	updated.append({"id": IdUtil.uuid_v4(), "text": "", "count": 1, "enabled": true})
	_emit_rows(updated)


func _remove_row(rows: Array, index: int) -> void:
	var updated := rows.duplicate(true)
	updated.remove_at(index)
	_emit_rows(updated)


func _emit_rows(rows: Array) -> void:
	var lines: Array[String] = []
	for row in rows:
		lines.append(String(row.get("text", "")))
	params_commit_requested.emit({"items": "\n".join(lines), "rows": rows})


func _rows() -> Array:
	var value: Variant = _params.get("rows", null)
	if value is Array:
		return value.duplicate(true)
	var rows := []
	for raw_line in String(_params.get("items", "")).split("\n", false):
		var text := String(raw_line).strip_edges()
		if not text.is_empty():
			rows.append({"id": IdUtil.uuid_v4(), "text": text, "count": 1, "enabled": true})
	return rows


func _enabled_count(rows: Array) -> int:
	var count := 0
	for row in rows:
		if row is Dictionary and bool(row.get("enabled", true)):
			count += 1
	return count


func _expected_count(rows: Array) -> int:
	var count := 0
	for row in rows:
		if row is Dictionary and bool(row.get("enabled", true)):
			count += maxi(1, int(row.get("count", 1)))
	return count
