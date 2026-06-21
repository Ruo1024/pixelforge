class_name PFBatchNode
extends PFNode

## 批次内容节点。
## contract: 02-contracts/GRAPH-SCHEMA.md §5a；asset_ids 是图逻辑的物化队列。

const DEFAULT_LABEL := "Batch"


func get_type() -> String:
	return "batch"


func get_display_name() -> String:
	return "Batch"


func get_category() -> String:
	return "container"


func get_input_ports() -> Array[Dictionary]:
	return [{"name": "in", "type": "image_list", "required": false}]


func get_output_ports() -> Array[Dictionary]:
	return [
		{"name": "images", "type": "image_list"},
		{"name": "assets", "type": "asset_list"},
	]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "label",
			"label_key": "BATCH_DEFAULT_LABEL",
			"kind": KIND_TEXT,
			"default": DEFAULT_LABEL
		},
	]


func is_canvas_resident() -> bool:
	return true


func get_canvas_actions() -> Array[Dictionary]:
	return [
		{"id": "clean_batch", "label_key": "BATCH_ACTION_CLEANUP", "core_op": "pixel_cleanup"},
		{"id": "matte_batch", "label_key": "BATCH_ACTION_MATTE", "core_op": "matting"},
		{"id": "outline_batch", "label_key": "BATCH_ACTION_OUTLINE", "core_op": "outline"},
		{"id": "quantize_batch", "label_key": "BATCH_ACTION_QUANTIZE", "core_op": "palette_map"},
		{"id": "export_batch", "label_key": "BATCH_ACTION_EXPORT", "core_op": "export_png"},
		{"id": "split_batch", "label_key": "BATCH_ACTION_SPLIT", "core_op": "select"},
		{
			"id": "send_to_editor",
			"label_key": "BATCH_ACTION_SEND_TO_EDITOR",
			"core_op": "open_editor"
		},
	]


func validate_params(params: Dictionary) -> Dictionary:
	var validated := super(params)
	validated["asset_ids"] = _string_array(params.get("asset_ids", []))
	if String(validated.get("label", "")).is_empty():
		validated["label"] = DEFAULT_LABEL
	return validated


func _string_array(value: Variant) -> Array:
	var result := []
	if not (value is Array):
		return result
	for entry in value:
		var id := String(entry)
		if not id.is_empty():
			result.append(id)
	return result
