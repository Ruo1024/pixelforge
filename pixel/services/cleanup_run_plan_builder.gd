class_name PFCleanupRunPlanBuilder
extends RefCounted

## Freezes one explicit cleanup click before an Output or worker is created.

const IdUtil := preload("res://core/util/id_util.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const PaletteRegistryScript := preload("res://core/pixel/palette_registry.gd")


static func build(graph: PFGraph, cleanup_node_id: String, asset_source: Variant) -> Dictionary:
	if graph == null or graph.get_node(cleanup_node_id) == null:
		return _issue("missing_cleanup_input", "assets")
	var source_id := ""
	for edge in graph.edges:
		if String(edge.get("to", ["", ""])[0]) == cleanup_node_id:
			source_id = String(edge.get("from", ["", ""])[0])
			break
	if source_id.is_empty() or graph.get_node(source_id) == null:
		return _issue("missing_cleanup_input", "assets")
	var source_type := graph.get_node(source_id).get_type()
	if source_type == "ai_generate":
		return _issue("cleanup_requires_output_source", "assets")
	if source_type not in ["batch", "image_input", "reference_set"]:
		return _issue("invalid_cleanup_source", "assets")
	var inputs := _source_inputs(graph, source_id, source_type)
	if inputs.is_empty():
		return _issue("missing_cleanup_input", "assets")
	if inputs.size() > 999:
		return _issue("cleanup_input_limit_exceeded", "assets")
	var params := graph.get_node_params(cleanup_node_id)
	var palette_result := freeze_palette(Dictionary(params.get("settings", {})).get("quantize", {}))
	if not bool(palette_result.get("ok", false)):
		return palette_result
	var run_id := IdUtil.uuid_v4()
	var slots := []
	for index in range(inputs.size()):
		var item: Dictionary = inputs[index]
		var asset_id := String(item["asset_id"])
		if (
			not asset_source.has_asset(asset_id)
			or asset_source.get_bitmap_status(asset_id) != "ready"
		):
			return _issue("missing_cleanup_input", "assets")
		var meta: Dictionary = asset_source.get_asset_meta(asset_id)
		var source_size: Array = Array(meta.get("size", [])).duplicate()
		if not _positive_pair(source_size):
			return _issue("missing_cleanup_input", "assets")
		var target := _effective_target(meta)
		var settings: Dictionary = Dictionary(params.get("settings", {})).duplicate(true)
		var planned_size := (
			target
			if bool(settings.get("resample", {}).get("enabled", false)) and _positive_pair(target)
			else source_size
		)
		var request_id := IdUtil.uuid_v4()
		var slot_id := IdUtil.uuid_v4()
		var snapshot := {
			"kind": "cleanup",
			"graph_id": graph.id,
			"source_node_id": cleanup_node_id,
			"input_source_kind": source_type,
			"input_source_node_id": source_id,
			"source_batch_node_id": source_id if source_type == "batch" else "",
			"source_slot_id": String(item.get("slot_id", "")),
			"source_asset_id": asset_id,
			"effective_target_size": target.duplicate(),
			"preset_id": String(params.get("preset_id", "")),
			"settings": settings,
			"palette_snapshot": palette_result.get("snapshot"),
		}
		(
			slots
			. append(
				{
					"slot_id": slot_id,
					"request_id": request_id,
					"source_row_id": "",
					"source_asset_id": asset_id,
					"planned_size": planned_size.duplicate(),
					"input_snapshot": snapshot,
				}
			)
		)
	return {"ok": true, "kind": "cleanup", "run_id": run_id, "slots": slots}


static func freeze_palette(quantize: Dictionary) -> Dictionary:
	if (
		not bool(quantize.get("enabled", false))
		or String(quantize.get("mode", "none")) != "fixed_palette"
	):
		return {"ok": true, "snapshot": null}
	var requested_id := String(quantize.get("palette_id", ""))
	var palette: PFPalette = PaletteRegistryScript.resolve(quantize, "")
	if (
		palette == null
		or requested_id.is_empty()
		or palette.id != requested_id
		or palette.colors.is_empty()
	):
		return _issue("missing_cleanup_palette", "settings.quantize.palette_id")
	var colors := []
	for color in palette.colors:
		colors.append("#%s" % Color(color).to_html(true).to_upper())
	var encoded := JSON.stringify(colors, "", false)
	return {
		"ok": true,
		"snapshot":
		{
			"palette_id": requested_id,
			"content_sha256": encoded.sha256_text(),
			"colors_rgba8": colors
		}
	}


static func _source_inputs(graph: PFGraph, source_id: String, source_type: String) -> Array:
	var params := graph.get_node_params(source_id)
	var result := []
	if source_type == "batch":
		for slot in params.get("result_slots", []):
			if (
				String(slot.get("status", "")) == "succeeded"
				and not bool(slot.get("detached", false))
			):
				result.append(
					{
						"asset_id": String(slot.get("asset_id", "")),
						"slot_id": String(slot.get("slot_id", ""))
					}
				)
	elif source_type == "image_input":
		result.append({"asset_id": String(params.get("asset_id", "")), "slot_id": ""})
	else:
		for asset_id in params.get("asset_ids", []):
			result.append({"asset_id": String(asset_id), "slot_id": ""})
	return result


static func _effective_target(meta: Dictionary) -> Array:
	var provenance: Dictionary = meta.get("provenance", {})
	var generation: Dictionary = provenance.get("generation_snapshot", {})
	if int(generation.get("target_width", 0)) > 0 and int(generation.get("target_height", 0)) > 0:
		return [int(generation["target_width"]), int(generation["target_height"])]
	var cleanup: Dictionary = provenance.get("cleanup", {})
	var target: Variant = cleanup.get("effective_target_size", [0, 0])
	return Array(target).duplicate() if _positive_pair(target) else [0, 0]


static func _positive_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and int(value[0]) > 0 and int(value[1]) > 0


static func _issue(code: String, field: String) -> Dictionary:
	return {"ok": false, "issue": {"code": code, "field": field, "args": {}}, "slots": []}
