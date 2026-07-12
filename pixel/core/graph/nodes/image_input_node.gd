class_name PFImageInputNode
extends PFNode

## Project-local reference image input resolved only through PFGraphContext.

const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")


func get_type() -> String:
	return "image_input"


func get_display_name() -> String:
	return "Reference Image"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "image", "type": "image"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "asset_id",
			"label_key": "GRAPH_PARAM_REFERENCE_ASSET",
			"kind": KIND_ASSET_REF,
			"default": "",
		}
	]


func execute(_inputs: Dictionary, params: Dictionary, ctx: Variant) -> Dictionary:
	var asset_id := String(params.get("asset_id", "")).strip_edges()
	if asset_id.is_empty():
		return _error("missing_asset_reference")
	if not (ctx is PFGraphContext) or not ctx.has_asset(asset_id):
		return _error("asset_not_found", asset_id)
	var image: Image = ctx.get_asset_image(asset_id)
	if image == null:
		return _error("asset_decode_failed", asset_id)
	return {
		"image": image,
		"__reference_asset_id": asset_id,
		"__reference_content_sha256": GraphContextScript.image_content_sha256(image),
	}


func _error(code: String, asset_id: String = "") -> Dictionary:
	return {
		"__error":
		{
			"code": code,
			"message": code,
			"asset_id": asset_id,
		}
	}
