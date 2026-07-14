class_name PFProjectResourceCatalog
extends RefCounted

## Read-only project asset, split preset, and workflow search facade.

const PromptPresetRegistry := preload("res://services/prompt_preset_registry.gd")
const CleanupPresetRegistry := preload("res://services/cleanup_preset_registry.gd")
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


static func search_prompt_presets(query: String = "") -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	var registry := PromptPresetRegistry.new()
	for preset_id in registry.get_preset_ids():
		var preset: Dictionary = registry.get_preset(preset_id)
		var name := _preset_name(preset)
		if (
			not normalized_query.is_empty()
			and normalized_query
			not in (
				"%s %s %s" % [preset_id, name, String(preset.get("prefix", ""))]
			).to_lower()
		):
			continue
		result.append(
			{
				"id": String(preset_id),
				"name": name,
				"name_key": String(preset.get("name_key", "")),
				"available": true,
				"preset": preset.duplicate(true),
			}
		)
	return result


static func search_cleanup_presets(query: String = "") -> Array[Dictionary]:
	var normalized_query := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	var registry := CleanupPresetRegistry.new()
	for preset_id in registry.get_preset_ids():
		var preset: Dictionary = registry.get_preset(preset_id)
		var name := _preset_name(preset)
		var settings: Dictionary = preset.get("settings", {})
		var quantize: Dictionary = settings.get("quantize", {})
		var detect: Dictionary = settings.get("detect_grid", {})
		var haystack := (
			"%s %s %s %s %s"
			% [
				preset_id,
				name,
				String(quantize.get("palette_id", "")),
				String(quantize.get("dither", "")),
				str(detect.get("base_size", "")),
			]
		)
		if not normalized_query.is_empty() and normalized_query not in haystack.to_lower():
			continue
		result.append(
			{
				"id": String(preset_id),
				"name": name,
				"name_key": String(preset.get("name_key", "")),
				"available": true,
				"preset": preset.duplicate(true),
			}
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


static func _preset_name(preset: Dictionary) -> String:
	if preset.has("name"):
		return String(preset["name"])
	match String(preset.get("name_key", "")):
		"PROMPT_PRESET_HIBIT":
			return LocalizationService.text("PROMPT_PRESET_HIBIT")
		"PROMPT_PRESET_GB":
			return LocalizationService.text("PROMPT_PRESET_GB")
		"PROMPT_PRESET_HD2D_PROP":
			return LocalizationService.text("PROMPT_PRESET_HD2D_PROP")
		"PROMPT_PRESET_1BIT":
			return LocalizationService.text("PROMPT_PRESET_1BIT")
		"PROMPT_PRESET_NES":
			return LocalizationService.text("PROMPT_PRESET_NES")
		"PROMPT_PRESET_16BIT_DB32":
			return LocalizationService.text("PROMPT_PRESET_16BIT_DB32")
		"CLEANUP_PRESET_HIBIT":
			return LocalizationService.text("CLEANUP_PRESET_HIBIT")
		"CLEANUP_PRESET_GB":
			return LocalizationService.text("CLEANUP_PRESET_GB")
		"CLEANUP_PRESET_HD2D_PROP":
			return LocalizationService.text("CLEANUP_PRESET_HD2D_PROP")
		"CLEANUP_PRESET_1BIT":
			return LocalizationService.text("CLEANUP_PRESET_1BIT")
		"CLEANUP_PRESET_NES":
			return LocalizationService.text("CLEANUP_PRESET_NES")
		"CLEANUP_PRESET_16BIT_DB32":
			return LocalizationService.text("CLEANUP_PRESET_16BIT_DB32")
		_:
			return String(preset.get("id", ""))
