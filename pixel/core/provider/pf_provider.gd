class_name PFProvider
extends RefCounted

## AI Provider 领域接口。
## contract: 02-contracts/PROVIDER-API.md；实现不得持久化凭据或依赖 UI。


func get_id() -> String:
	return "base"


func get_display_name() -> String:
	return "Base Provider"


func get_api_version() -> int:
	return 1


func get_capabilities() -> Dictionary:
	return {}


func get_model_descriptors() -> Array[Dictionary]:
	return []


func resolve_model_id(model_id: String = "") -> String:
	var requested := model_id.strip_edges()
	var fallback := ""
	for descriptor in get_model_descriptors():
		var descriptor_id := String(descriptor.get("model_id", "")).strip_edges()
		if bool(descriptor.get("is_default", false)):
			fallback = descriptor_id
		if descriptor_id == requested and not requested.is_empty():
			return descriptor_id
	return fallback if requested.is_empty() else ""


func get_model_descriptor(model_id: String = "") -> Dictionary:
	var resolved := resolve_model_id(model_id)
	for descriptor in get_model_descriptors():
		if String(descriptor.get("model_id", "")) == resolved:
			return descriptor.duplicate(true)
	return {}


func validate_generation_request(request: Dictionary) -> Variant:
	var requested_model := String(request.get("model_id", ""))
	var descriptor := get_model_descriptor(requested_model)
	var validation_error: Variant = null
	if descriptor.is_empty():
		validation_error = _request_error("Unknown model: %s" % requested_model)
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var mode := String(request.get("mode", "txt2img"))
	if validation_error == null and not bool(capabilities.get(mode, false)):
		validation_error = _request_error("Model does not support %s" % mode)
	var batch := int(request.get("batch", 1))
	if validation_error == null and (batch < 1 or batch > int(capabilities.get("max_batch", 1))):
		validation_error = _request_error("Batch size is outside the model limit")
	var references := get_reference_images(request)
	if (
		validation_error == null
		and references.size() > int(capabilities.get("max_reference_images", 0))
	):
		validation_error = _request_error("Reference image count is outside the model limit")
	var requested_output := (
		String(request.get("output_size", request.get("extra", {}).get("output_size", "")))
		. strip_edges()
	)
	var output_sizes: Array = capabilities.get("output_sizes", [])
	if (
		validation_error == null
		and not requested_output.is_empty()
		and not output_sizes.has(requested_output)
	):
		validation_error = _request_error("Output size is not supported by the model")
	var constraints: Dictionary = capabilities.get("output_size_constraints", {})
	var width := int(request.get("width", constraints.get("min_side", 1)))
	var height := int(request.get("height", constraints.get("min_side", 1)))
	if validation_error == null and not constraints.is_empty():
		var minimum := int(constraints.get("min_side", 1))
		var maximum := int(constraints.get("max_side", 0x7FFFFFFF))
		if width < minimum or height < minimum or width > maximum or height > maximum:
			validation_error = _request_error("Output dimensions are outside the model limits")
	var wants_transparency := bool(
		(
			request
			. get(
				"transparent_bg",
				request.get("extra", {}).get("transparent_bg", false),
			)
		)
	)
	if (
		validation_error == null
		and wants_transparency
		and not bool(capabilities.get("transparent_bg", false))
	):
		validation_error = _request_error("Transparent output is not supported by the model")
	return validation_error


func get_reference_images(request: Dictionary) -> Array:
	var references: Variant = request.get("ref_images", [])
	if references is Array and not references.is_empty():
		return references
	var legacy: Variant = request.get("ref_image")
	return [legacy] if legacy is Image else []


func get_config_schema() -> Array[Dictionary]:
	return []


func configure(_config: Dictionary) -> Variant:
	return null


func validate_credentials() -> Variant:
	return null


func generate(_request: Dictionary) -> Variant:
	return null


func estimate_cost(_request: Dictionary) -> float:
	return -1.0


func cancel(_task_id: String) -> void:
	return


func _request_error(message: String) -> Dictionary:
	return {"code": "invalid_request", "message": message, "recoverable": true}
