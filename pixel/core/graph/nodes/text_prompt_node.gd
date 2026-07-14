class_name PFTextPromptNode
extends PFNode

## Free-form prompt input for a single generation subject.
## contract: 02-contracts/GRAPH-SCHEMA.md §5; preserves the authored multiline text.


func get_type() -> String:
	return "text_prompt"


func get_display_name() -> String:
	return "Text Prompt"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "prompt", "type": "text"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "text",
			"label_key": "GRAPH_PARAM_TEXT_PROMPT",
			"kind": KIND_TEXT_MULTILINE,
			"default": "",
		},
	]


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	return {"prompt": String(params.get("text", ""))}
