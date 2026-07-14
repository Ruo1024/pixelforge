class_name PFPixelCleanupNode
extends PFNode

const DEFAULT_SETTINGS := {
	"detect_grid": {"enabled": true, "mode": "auto", "scale": 4.0, "offset": [0.0, 0.0], "base_size": 32},
	"resample": {"enabled": true, "mode": "mode", "scale": 4.0, "offset": [0.0, 0.0]},
	"quantize": {
		"enabled": true,
		"mode": "fixed_palette",
		"palette_id": "db32",
		"auto_k_strategy": "median_cut",
		"k": 16,
		"dither": "none",
		"dither_strength": 0.0,
		"dither_contrast": 0.0,
		"dither_chroma": 0.0,
		"dither_density": 1.0,
	},
}


func get_type() -> String:
	return "pixel_cleanup"


func get_display_name() -> String:
	return "Pixel Cleanup"


func get_category() -> String:
	return "process"


func get_execution_policy() -> String:
	return "manual"


func get_input_ports() -> Array[Dictionary]:
	return [{"name": "assets", "type": "asset_list", "required": true}]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "assets", "type": "asset_list"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func validate_params(params: Dictionary) -> Dictionary:
	var settings: Variant = params.get("settings", DEFAULT_SETTINGS)
	return {
		"preset_id": String(params.get("preset_id", "cleanup-16bit-db32")),
		"settings": Dictionary(settings).duplicate(true) if settings is Dictionary else DEFAULT_SETTINGS.duplicate(true),
	}


func execute(_inputs: Dictionary, _params: Dictionary, _ctx: Variant) -> Dictionary:
	return {"__error": {"code": "manual_execution_required"}}
