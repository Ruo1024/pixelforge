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
			selected_rows.append(
				{"id": String(row["id"]), "text": String(row["text"]), "count": int(row["count"])}
			)
	return {"subjects": selected_rows}


static func validate_v2_rows(params: Dictionary) -> Dictionary:
	if params.size() != 1 or not params.has("rows") or not (params["rows"] is Array):
		return {"ok": false, "path": "params"}
	var seen_ids := {}
	var rows: Array = params["rows"]
	for index in range(rows.size()):
		if not (rows[index] is Dictionary):
			return {"ok": false, "path": "params.rows[%d]" % index}
		var row: Dictionary = rows[index]
		if row.size() != 4:
			return {"ok": false, "path": "params.rows[%d]" % index}
		for key in ["id", "text", "count", "enabled"]:
			if not row.has(key):
				return {"ok": false, "path": "params.rows[%d].%s" % [index, key]}
		if not (row["id"] is String) or not (row["text"] is String):
			return {"ok": false, "path": "params.rows[%d]" % index}
		var row_id := String(row["id"]).strip_edges()
		var text := String(row["text"]).strip_edges()
		if row_id.is_empty() or text.is_empty() or seen_ids.has(row_id):
			return {"ok": false, "path": "params.rows[%d]" % index}
		if not (row["count"] is int) or int(row["count"]) < 1 or int(row["count"]) > 999:
			return {"ok": false, "path": "params.rows[%d].count" % index}
		if not (row["enabled"] is bool):
			return {"ok": false, "path": "params.rows[%d].enabled" % index}
		seen_ids[row_id] = true
	return {"ok": true}


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
