class_name PFComfyWorkflowTemplate
extends RefCounted

## ComfyUI API-workflow discovery and deterministic PF request binding.

const BUILTIN_PATHS := {
	"sdxl_pixel_txt2img": "res://plugins/bridge_comfyui/templates/sdxl_pixel_txt2img.json",
	"sdxl_pixel_img2img": "res://plugins/bridge_comfyui/templates/sdxl_pixel_img2img.json",
}


static func load_builtin(template_id: String) -> Dictionary:
	return load_from_path(String(BUILTIN_PATHS.get(template_id, "")))


static func load_from_path(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func builtin_ids() -> Array:
	var ids: Array = BUILTIN_PATHS.keys()
	ids.sort()
	return ids


static func discover_slots(workflow: Dictionary) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var node_ids: Array = workflow.keys()
	node_ids.sort()
	for node_id in node_ids:
		var node: Dictionary = workflow[node_id]
		var class_type := String(node.get("class_type", ""))
		var inputs: Dictionary = node.get("inputs", {})
		for input_name in inputs.keys():
			var field := _field_for(class_type, String(input_name))
			if not field.is_empty():
				(
					slots
					. append(
						{
							"path": "%s.inputs.%s" % [node_id, input_name],
							"field": field,
							"class_type": class_type,
						}
					)
				)
	return slots


static func fill(template: Dictionary, request: Dictionary, upload_name: String = "") -> Dictionary:
	var workflow: Dictionary = Dictionary(template.get("workflow", {})).duplicate(true)
	var bindings: Dictionary = template.get("bindings", {})
	for field in bindings.keys():
		var value: Variant = _request_value(String(field), request, upload_name)
		for path_value in _binding_paths(bindings[field]):
			_set_path(workflow, String(path_value), value)
	return workflow


static func import_api_workflow(
	workflow: Dictionary, template_id: String, name: String, bindings: Dictionary
) -> Dictionary:
	return {
		"id": template_id.to_snake_case(),
		"name": name,
		"mode": "img2img" if bindings.has("ref_image") else "txt2img",
		"workflow": workflow.duplicate(true),
		"bindings": bindings.duplicate(true),
		"discovered_slots": discover_slots(workflow),
	}


static func _field_for(class_type: String, input_name: String) -> String:
	if class_type == "KSampler" and input_name == "seed":
		return "seed"
	if class_type == "CLIPTextEncode" and input_name == "text":
		return "prompt"
	if class_type == "EmptyLatentImage" and input_name in ["width", "height", "batch_size"]:
		return input_name.replace("batch_size", "batch")
	if class_type == "LoadImage" and input_name == "image":
		return "ref_image"
	if class_type == "LoraLoader" and input_name in ["lora_name", "strength_model"]:
		return "lora"
	return ""


static func _request_value(field: String, request: Dictionary, upload_name: String) -> Variant:
	match field:
		"prompt":
			return String(request.get("prompt", "pixel art sprite"))
		"negative_prompt":
			return String(request.get("negative_prompt", ""))
		"seed":
			var seed := int(request.get("seed", -1))
			return seed if seed >= 0 else randi()
		"width", "height", "batch":
			return int(request.get(field, 1))
		"ref_image":
			return upload_name
		"lora":
			return request.get("extra", {}).get("lora", "pixel-art-xl.safetensors")
	return request.get("extra", {}).get(field, null)


static func _binding_paths(value: Variant) -> Array:
	return value if value is Array else [value]


static func _set_path(workflow: Dictionary, path: String, value: Variant) -> bool:
	var parts := path.split(".")
	if parts.size() != 3 or parts[1] != "inputs" or not workflow.has(parts[0]):
		return false
	var node: Dictionary = workflow[parts[0]]
	var inputs: Dictionary = node.get("inputs", {})
	if not inputs.has(parts[2]):
		return false
	inputs[parts[2]] = value
	node["inputs"] = inputs
	workflow[parts[0]] = node
	return true
