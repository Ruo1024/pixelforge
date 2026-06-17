class_name PFPixelOperations
extends RefCounted

## M3 批次菜单与未来 process 节点共用的像素操作入口。
## contract: 03-milestones/M3-开发规划.md G-3；本层只编排 core 算法和素材派生元数据，不依赖 UI。

const IdUtil := preload("res://core/util/id_util.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Outliner := preload("res://core/pixel/outliner.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")

const OP_CLEANUP := "pixel_cleanup"
const OP_MATTING := "matting"
const OP_OUTLINE := "outline"


static func apply_image(operation: String, source: Image, params: Dictionary = {}) -> Dictionary:
	match operation:
		OP_CLEANUP:
			return _apply_cleanup(source, params)
		OP_MATTING:
			return _apply_matting(source, params)
		OP_OUTLINE:
			return _apply_outline(source, params)
		_:
			return {"ok": false, "error": "unsupported_operation", "operation": operation}


static func apply_to_assets(
	asset_ids: Array,
	asset_library: Node,
	operation: String,
	params: Dictionary = {},
	cancel_check: Callable = Callable(),
	progress: Callable = Callable()
) -> Dictionary:
	var ids := _string_array(asset_ids)
	var results := []
	for index in range(ids.size()):
		if cancel_check.is_valid() and bool(cancel_check.call()):
			return {"canceled": true, "items": results}

		var asset_id := String(ids[index])
		var image: Image = asset_library.get_image(asset_id)
		if image == null:
			continue

		var item_result := apply_image(operation, image, params)
		if bool(item_result.get("ok", false)):
			item_result["parent_asset"] = asset_id
			results.append(item_result)

		if progress.is_valid():
			progress.call(float(index + 1) / float(maxi(1, ids.size())), operation)
	return {"canceled": false, "items": results}


static func register_result_asset(
	asset_library: Node, parent_asset_id: String, item_result: Dictionary
) -> String:
	var parent_id := String(item_result.get("parent_asset", parent_asset_id))
	var suffix := String(item_result.get("name_suffix", item_result.get("suffix", "operation")))
	return (
		asset_library
		. register_image(
			item_result["image"],
			"%s_%s" % [parent_id.left(8), suffix],
			{
				"origin": String(item_result.get("origin", "edited")),
				"tags": item_result.get("tags", []),
				"provenance": make_provenance(parent_id, item_result),
			}
		)
	)


static func make_provenance(parent_asset_id: String, item_result: Dictionary) -> Dictionary:
	var provenance_key := String(item_result.get("provenance_key", "operation"))
	var operation_report: Variant = json_safe(item_result.get("report", {}))
	if operation_report is Dictionary:
		var report_dict: Dictionary = operation_report
		if not report_dict.has("source_asset"):
			report_dict["source_asset"] = parent_asset_id
		operation_report = report_dict

	var provenance := {
		"provider": null,
		"model": null,
		"prompt": "",
		"seed": null,
		"parent_asset": parent_asset_id,
		"graph_id": null,
		"created_at": IdUtil.utc_now_iso(),
	}
	provenance[provenance_key] = operation_report
	return provenance


static func normalize_matte_params(params: Dictionary) -> Dictionary:
	if params.is_empty():
		return {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
	return {
		"mode": String(params.get("mode", Matting.MODE_FLOOD)),
		"tolerance": float(params.get("tolerance", 12.0)),
		"feather": int(params.get("feather", 0)),
	}


static func normalize_outline_params(params: Dictionary) -> Dictionary:
	if params.is_empty():
		return {"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
	return {
		"type": String(params.get("type", Outliner.TYPE_OUTER)),
		"color": params.get("color", Color.BLACK),
		"corner": String(params.get("corner", Outliner.CORNER_CROSS)),
		"colored": bool(params.get("colored", false)),
	}


static func json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var output := {}
			for key in Dictionary(value).keys():
				output[String(key)] = json_safe(Dictionary(value)[key])
			return output
		TYPE_ARRAY:
			var output := []
			for item in Array(value):
				output.append(json_safe(item))
			return output
		TYPE_VECTOR2:
			var vector := Vector2(value)
			return [vector.x, vector.y]
		TYPE_VECTOR2I:
			var vector_i := Vector2i(value)
			return [vector_i.x, vector_i.y]
		TYPE_RECT2I:
			var rect := Rect2i(value)
			return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		TYPE_COLOR:
			return Color(value).to_html(true)
		_:
			return value


static func _apply_cleanup(source: Image, params: Dictionary) -> Dictionary:
	var normalized := Pipeline.normalize_params(params)
	var cleanup_result := Pipeline.apply(source, normalized)
	return {
		"ok": true,
		"operation": OP_CLEANUP,
		"image": cleanup_result["image"],
		"suffix": "clean",
		"name_suffix": "clean",
		"origin": "edited",
		"tags": ["cleanup"],
		"provenance_key": "cleanup",
		"report":
		{
			"params": json_safe(normalized),
			"report": json_safe(cleanup_result.get("report", {})),
		},
	}


static func _apply_matting(source: Image, params: Dictionary) -> Dictionary:
	var normalized := normalize_matte_params(params)
	var matting_result: Dictionary = Matting.matte(source, normalized)
	# Provenance must stay JSON-safe; the generated Image is stored as an asset, not in metadata.
	var report := matting_result.duplicate(true)
	report.erase("image")
	report["params"] = json_safe(normalized)
	return {
		"ok": true,
		"operation": OP_MATTING,
		"image": matting_result["image"],
		"suffix": "matte",
		"name_suffix": "matte",
		"origin": "edited",
		"tags": ["matting"],
		"provenance_key": "matting",
		"report": json_safe(report),
		"warning": String(matting_result.get("warning", "")),
	}


static func _apply_outline(source: Image, params: Dictionary) -> Dictionary:
	var normalized := normalize_outline_params(params)
	return {
		"ok": true,
		"operation": OP_OUTLINE,
		"image": Outliner.add_outline(source, normalized),
		"suffix": "outline",
		"name_suffix": "outline",
		"origin": "edited",
		"tags": ["outline"],
		"provenance_key": "outline",
		"report": json_safe(normalized),
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in Array(value):
			var id := String(item)
			if not id.is_empty():
				result.append(id)
	return result
