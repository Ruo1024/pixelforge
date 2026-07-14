class_name PFPromptPresetNode
extends PFNode

const DEFAULT_PRESET := {
	"prompt_preset_version": 1,
	"id": "prompt-16bit-db32",
	"name_key": "PROMPT_PRESET_16BIT_DB32",
	"prefix":
	"pixel art, 16-bit style, limited palette, clean pixel grid, retro game asset, DawnBringer palette",
}


func get_type() -> String:
	return "prompt_preset"


func get_display_name() -> String:
	return "Style Prompt"


func get_category() -> String:
	return "input"


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "prefix", "type": "prompt_prefix"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func validate_params(params: Dictionary) -> Dictionary:
	var preset: Variant = params.get("preset", DEFAULT_PRESET)
	return {
		"preset":
		(
			Dictionary(preset).duplicate(true)
			if preset is Dictionary
			else DEFAULT_PRESET.duplicate(true)
		)
	}


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	var preset: Dictionary = validate_params(params)["preset"]
	return {
		"prefix":
		{"prefix": String(preset.get("prefix", "")), "preset_id": String(preset.get("id", ""))}
	}
