class_name PFReferenceSetNode
extends PFNode

## Ordered project-local reference images resolved only through PFGraphContext.

const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")


func get_type() -> String:
	return "reference_set"


func get_display_name() -> String:
	return "Reference Set"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "images", "type": "image_list"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func validate_params(params: Dictionary) -> Dictionary:
	var validated := params.duplicate(true)
	validated["asset_ids"] = _string_array(params.get("asset_ids", []))
	return validated


func execute(_inputs: Dictionary, params: Dictionary, ctx: Variant) -> Dictionary:
	var asset_ids := _string_array(params.get("asset_ids", []))
	if asset_ids.is_empty():
		return _error("missing_asset_reference", -1)

	var images: Array[Image] = []
	var content_sha256s: Array[String] = []
	for index in range(asset_ids.size()):
		var asset_id := asset_ids[index]
		if asset_id.strip_edges().is_empty():
			return _error("missing_asset_reference", index, asset_id)
		if not (ctx is PFGraphContext) or not ctx.has_asset(asset_id):
			return _error("asset_not_found", index, asset_id)
		var image: Image = ctx.get_asset_image(asset_id)
		if image == null:
			return _error("asset_decode_failed", index, asset_id)
		images.append(image)
		content_sha256s.append(GraphContextScript.image_content_sha256(image))

	return {
		"images": images,
		"__reference_asset_ids": asset_ids.duplicate(),
		"__reference_content_sha256s": content_sha256s,
	}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array or value is PackedStringArray):
		return result
	for item in value:
		result.append(String(item))
	return result


func _error(code: String, index: int, asset_id: String = "") -> Dictionary:
	return {
		"__error":
		{
			"code": code,
			"message": code,
			"asset_id": asset_id,
			"index": index,
		}
	}
