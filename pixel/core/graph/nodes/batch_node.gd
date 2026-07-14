class_name PFBatchNode
extends PFNode

## Output 领域容器。素材真相只存在 result_slots；asset_ids 已硬切删除。


func get_type() -> String:
	return "batch"


func get_display_name() -> String:
	return "Output"


func get_category() -> String:
	return "container"


func get_input_ports() -> Array[Dictionary]:
	return [{"name": "in", "type": "asset_list", "required": false}]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "assets", "type": "asset_list"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func is_canvas_resident() -> bool:
	return true


func validate_params(params: Dictionary) -> Dictionary:
	return {
		"label": String(params.get("label", "")),
		"source_node_id": String(params.get("source_node_id", "")),
		"source_run_id": String(params.get("source_run_id", "")),
		"role": _valid_role(String(params.get("role", "standalone"))),
		"input_snapshots": Dictionary(params.get("input_snapshots", {})).duplicate(true) if params.get("input_snapshots", {}) is Dictionary else {},
		"request_records": Array(params.get("request_records", [])).duplicate(true) if params.get("request_records", []) is Array else [],
		"result_slots": Array(params.get("result_slots", [])).duplicate(true) if params.get("result_slots", []) is Array else [],
	}


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	return {"assets": get_visible_asset_ids(params)}


static func get_visible_asset_ids(batch_params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var slots: Variant = batch_params.get("result_slots", [])
	if not (slots is Array):
		return result
	for raw_slot in slots:
		if not (raw_slot is Dictionary):
			continue
		if String(raw_slot.get("status", "")) != "succeeded" or bool(raw_slot.get("detached", false)):
			continue
		var asset_id := String(raw_slot.get("asset_id", ""))
		if not asset_id.is_empty():
			result.append(asset_id)
	return result


func _valid_role(value: String) -> String:
	return value if value in ["current", "history", "standalone"] else "standalone"
