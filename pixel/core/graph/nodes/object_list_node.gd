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


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	return {"items": PackedStringArray(_split_lines(String(params.get("items", ""))))}


func _split_lines(text: String) -> Array:
	var result := []
	for raw_line in text.split("\n", false):
		var line := String(raw_line).strip_edges()
		if not line.is_empty():
			result.append(line)
	return result
