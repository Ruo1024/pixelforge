class_name PFProjectResourceCatalog
extends RefCounted

## Read-only project asset and built-in style search; callers keep AssetLibrary and preset JSON as truth.

const STYLE_PATHS := [
	"res://assets/presets/preset_16bit_db32.json",
	"res://assets/presets/preset_gb.json",
	"res://assets/presets/preset_nes.json",
	"res://assets/presets/preset_hibit.json",
	"res://assets/presets/preset_1bit.json",
	"res://assets/presets/preset_hd2d_prop.json",
]
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")


static func search_assets(query: String = "", origin: String = "") -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var normalized_origin := origin.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	var metadata: Dictionary = AssetLibrary.get_all_meta()
	var asset_ids := metadata.keys()
	asset_ids.sort()
	for raw_id in asset_ids:
		var asset_id := String(raw_id)
		var meta: Dictionary = metadata[asset_id]
		var asset_origin := String(meta.get("origin", "")).to_lower()
		if not normalized_origin.is_empty() and asset_origin != normalized_origin:
			continue
		var haystack := (
			"%s %s %s"
			% [
				String(meta.get("name", "")),
				" ".join(Array(meta.get("tags", []))),
				asset_origin,
			]
		)
		if not normalized_query.is_empty() and normalized_query not in haystack.to_lower():
			continue
		(
			result
			. append(
				{
					"asset_id": asset_id,
					"name": String(meta.get("name", asset_id.left(8))),
					"origin": asset_origin,
					"available":
					AssetLibrary.has_asset(asset_id) and AssetLibrary.get_image(asset_id) != null,
				}
			)
		)
	return result


static func search_styles(query: String = "", resolution_tier: String = "") -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var normalized_tier := resolution_tier.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for path in STYLE_PATHS:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var preset: Dictionary = parsed
		var tier := String(preset.get("resolution_tier", "")).to_lower()
		if not normalized_tier.is_empty() and tier != normalized_tier:
			continue
		var name := String(preset.get("name", preset.get("id", "")))
		if (
			not normalized_query.is_empty()
			and normalized_query not in ("%s %s" % [name, tier]).to_lower()
		):
			continue
		(
			result
			. append(
				{
					"id": String(preset.get("id", "")),
					"name": name,
					"resolution_tier": tier,
					"path": path,
					"preset": preset.duplicate(true),
				}
			)
		)
	return result


static func search_workflows(query: String = "", source: String = "") -> Array[Dictionary]:
	var listed := WorkflowTemplateService.list_templates(query)
	var result: Array[Dictionary] = []
	for template in listed["templates"]:
		var template_source := "builtin" if bool(template.get("builtin", false)) else "user"
		if not source.is_empty() and source != template_source:
			continue
		var requirements: Dictionary = template.get("requirements", {})
		(
			result
			. append(
				{
					"id": String(template.get("id", "")),
					"name": String(template.get("name", "")),
					"description": String(template.get("description", "")),
					"source": template_source,
					"node_count": template.get("nodes", []).size(),
					"model_ids": requirements.get("model_ids", []),
					"reference_slots": int(requirements.get("reference_slots", 0)),
					"available": true,
					"template": template.duplicate(true),
				}
			)
		)
	return result
