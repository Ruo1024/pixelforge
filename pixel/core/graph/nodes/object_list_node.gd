class_name PFObjectListNode
extends PFNode

## 批量对象描述输入节点。
## contract: 02-contracts/GRAPH-SCHEMA.md §5；把多行文本规范化为 text_list 输出。


func get_type() -> String:
	return "object_list"


func get_display_name() -> String:
	return "Object List"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "items", "type": "text_list"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "items",
			"label_key": "GRAPH_PARAM_OBJECT_LIST",
			"kind": KIND_TEXT_MULTILINE,
			"default": "",
		},
	]


func validate_params(params: Dictionary) -> Dictionary:
	var validated := super(params)
	var rows_value: Variant = params.get("rows", null)
	if rows_value is Array:
		validated["rows"] = _validated_rows(rows_value)
	else:
		validated.erase("rows")
	return validated


func rows_for_params(params: Dictionary) -> Array[Dictionary]:
	var rows_value: Variant = params.get("rows", null)
	if rows_value is Array:
		return _validated_rows(rows_value)
	return _legacy_rows(String(params.get("items", "")))


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	var rows_value: Variant = params.get("rows", null)
	if rows_value is Array:
		var selected: Array[String] = []
		var selected_rows: Array[Dictionary] = []
		for row in _validated_rows(rows_value):
			if bool(row["enabled"]):
				selected.append(String(row["text"]))
				selected_rows.append(row.duplicate(true))
		return {"items": PackedStringArray(selected), "__source_rows": selected_rows}
	return {"items": PackedStringArray(_split_lines(String(params.get("items", ""))))}


func _validated_rows(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	var seen_ids := {}
	for index in range(value.size()):
		var raw_row: Variant = value[index]
		if not (raw_row is Dictionary):
			continue
		var text := String(raw_row.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var row_id := String(raw_row.get("id", "")).strip_edges()
		if row_id.is_empty() or seen_ids.has(row_id):
			row_id = _legacy_row_id(text, index)
		seen_ids[row_id] = true
		(
			result
			. append(
				{
					"id": row_id,
					"text": text,
					"count": clampi(int(raw_row.get("count", 1)), 1, 999),
					"enabled": bool(raw_row.get("enabled", true)),
				}
			)
		)
	return result


func _legacy_rows(items: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lines := _split_lines(items)
	for index in range(lines.size()):
		var text := String(lines[index])
		result.append(
			{"id": _legacy_row_id(text, index), "text": text, "count": 1, "enabled": true}
		)
	return result


func _legacy_row_id(text: String, index: int) -> String:
	return "legacy_%08x_%03d" % [abs(text.hash()), index]


func _split_lines(text: String) -> Array:
	var result := []
	for raw_line in text.split("\n", false):
		var line := String(raw_line).strip_edges()
		if not line.is_empty():
			result.append(line)
	return result
