class_name PFStylePresetNode
extends PFNode

## Embedded style preset input.
## contract: 02-contracts/GRAPH-SCHEMA.md §1/§5 and STYLE-PRESETS.md; output is detached
## from graph parameters so downstream consumers cannot mutate persisted project state.

const PRESET_REF_EMBEDDED := "embedded"
const AUTO_K_MEDIAN_CUT := "median_cut"
const AUTO_K_KMEANS := "kmeans"


func get_type() -> String:
	return "style_preset"


func get_display_name() -> String:
	return "Style Preset"


func get_category() -> String:
	return "style"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "style", "type": "style"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "preset_ref",
			"label_key": "GRAPH_PARAM_STYLE_PRESET",
			"kind": KIND_TEXT,
			"default": PRESET_REF_EMBEDDED,
		},
	]


func validate_params(params: Dictionary) -> Dictionary:
	var validated := super(params)
	var preset_value: Variant = params.get("preset", {})
	var preset: Dictionary = preset_value.duplicate(true) if preset_value is Dictionary else {}
	var strategy := String(preset.get("auto_k_strategy", AUTO_K_MEDIAN_CUT))
	if strategy not in [AUTO_K_MEDIAN_CUT, AUTO_K_KMEANS]:
		strategy = AUTO_K_MEDIAN_CUT
	if not preset.is_empty() or preset.has("auto_k_strategy"):
		preset["auto_k_strategy"] = strategy
	validated["preset"] = preset
	return validated


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	var preset_value: Variant = params.get("preset", {})
	var preset: Dictionary = preset_value.duplicate(true) if preset_value is Dictionary else {}
	return {"style": preset}
