class_name PFComfyUIWorkflowNode
extends PFNode

## First-class graph node that selects a ComfyUI workflow template.

const Templates := preload("res://plugins/bridge_comfyui/workflow_template.gd")


func get_type() -> String:
	return "comfyui.run_workflow"


func get_display_name() -> String:
	return "ComfyUI Workflow"


func get_category() -> String:
	return "generate"


func get_input_ports() -> Array[Dictionary]:
	return [
		{"name": "image", "type": "image", "required": false},
		{"name": "text", "type": "text", "required": false},
		{"name": "items", "type": "text_list", "required": false},
		{"name": "spec", "type": "spec", "required": true},
		{"name": "style", "type": "style", "required": false},
	]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "images", "type": "image_list"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "template_id",
			"label_key": "ComfyUI Template",
			"kind": KIND_ENUM,
			"default": "sdxl_pixel_txt2img",
			"options": Templates.builtin_ids(),
		},
		{"key": "seed", "label_key": "Seed", "kind": KIND_SEED, "default": 1, "min": 0},
	]


func is_async() -> bool:
	return true


func execute(_inputs: Dictionary, _params: Dictionary, _ctx: Variant) -> Dictionary:
	return {
		"__error":
		{
			"code": "async_provider_required",
			"message": "Run this graph through the ComfyUI provider queue",
		}
	}
