class_name PFObjectListNode
extends PFNode

## 有序批量对象行输入。
## contract: 02-contracts/GRAPH-SCHEMA.md §4.2；只接受 rows，不迁移旧 items。


func get_type() -> String:
	return "object_list"


func get_display_name() -> String:
	return "Object List"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "subjects", "type": "subject_list"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func validate_params(params: Dictionary) -> Dictionary:
	return {"rows": _validated_rows(params.get("rows", []))}


func rows_for_params(params: Dictionary) -> Array[Dictionary]:
	return _validated_rows(params.get("rows", []))


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	var selected_rows: Array[Dictionary] = []
	for row in _validated_rows(params.get("rows", [])):
		if bool(row["enabled"]):
			selected_rows.append(row.duplicate(true))
	return {"subjects": selected_rows}


func _validated_rows(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	var seen_ids := {}
	for raw_row in value:
		if not (raw_row is Dictionary):
			continue
		var row_id := String(raw_row.get("id", "")).strip_edges()
		var text := String(raw_row.get("text", "")).strip_edges()
		var count_value: Variant = raw_row.get("count", null)
		var enabled_value: Variant = raw_row.get("enabled", null)
		if (
			row_id.is_empty()
			or seen_ids.has(row_id)
			or text.is_empty()
			or not (count_value is int or count_value is float)
			or float(count_value) != floorf(float(count_value))
			or int(count_value) < 1
			or int(count_value) > 999
			or not (enabled_value is bool)
		):
			continue
		seen_ids[row_id] = true
		result.append(
			{"id": row_id, "text": text, "count": int(count_value), "enabled": bool(enabled_value)}
		)
	return result
