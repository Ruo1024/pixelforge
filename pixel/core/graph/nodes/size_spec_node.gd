class_name PFSizeSpecNode
extends PFNode

## 尺寸规格输入节点。
## contract: 02-contracts/GRAPH-SCHEMA.md §5；输出生成阶段使用的尺寸与每物体数量建议。

const MIN_SIZE := 1
const MAX_SIZE := 512
const DEFAULT_SIZE := 32


func get_type() -> String:
	return "size_spec"


func get_display_name() -> String:
	return "Size Spec"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "spec", "type": "spec"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "width",
			"label_key": "GRAPH_PARAM_WIDTH",
			"kind": KIND_INT,
			"default": DEFAULT_SIZE,
			"min": MIN_SIZE,
			"max": MAX_SIZE,
		},
		{
			"key": "height",
			"label_key": "GRAPH_PARAM_HEIGHT",
			"kind": KIND_INT,
			"default": DEFAULT_SIZE,
			"min": MIN_SIZE,
			"max": MAX_SIZE,
		},
		{
			"key": "per_subject",
			"label_key": "GRAPH_PARAM_PER_SUBJECT",
			"kind": KIND_INT,
			"default": 1,
			"min": 1,
			"max": 16,
		},
	]


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	return {
		"spec":
		{
			"width": int(params.get("width", DEFAULT_SIZE)),
			"height": int(params.get("height", DEFAULT_SIZE)),
			"per_subject": int(params.get("per_subject", 1)),
		},
	}
