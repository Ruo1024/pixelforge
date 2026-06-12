class_name PFCleanupPipeline
extends RefCounted

## 像素清洗管线编排器。
## contract: 03-milestones/M1-cleanup-pipeline.md §M1-5；入口保持 Image + 参数字典，内部按步骤链执行。
## PFCleanupParams 的 auto_k_strategy 是速度/质量选择：默认 median_cut；kmeans
## 仅在 quantize=auto_k 时生效，旧项目缺省或非法值必须保持 M1 输出不变。

const ImageMath := preload("res://core/util/image_math.gd")
const PipelineStep := preload("res://core/pixel/image_pipeline_step.gd")
const GridDetector := preload("res://core/pixel/grid_detector.gd")
const Resampler := preload("res://core/pixel/resampler.gd")
const Quantizer := preload("res://core/pixel/quantizer.gd")
const PaletteScript := preload("res://core/pixel/palette.gd")
const Ditherer := preload("res://core/pixel/ditherer.gd")

const DETECT_AUTO := "auto"
const DETECT_MANUAL := "manual"
const DETECT_NONE := "none"
const STEP_DETECT_GRID := "detect_grid"
const STEP_RESAMPLE := "resample"
const STEP_QUANTIZE := "quantize"
const DEFAULT_STEP_ORDER := [STEP_DETECT_GRID, STEP_RESAMPLE, STEP_QUANTIZE]


static func default_params(style_preset: Dictionary = {}) -> Dictionary:
	var palette_ref := "db32"
	var palette_data: Variant = style_preset.get("palette", {})
	if palette_data is Dictionary:
		palette_ref = String(palette_data.get("ref", palette_ref))

	return {
		"steps": DEFAULT_STEP_ORDER.duplicate(),
		STEP_DETECT_GRID:
		{
			"enabled": true,
			"mode": DETECT_AUTO,
			"scale": 4.0,
			"offset": Vector2.ZERO,
			"base_size": int(style_preset.get("base_size", 0)),
			"prior_scale": 0.0,
		},
		STEP_RESAMPLE:
		{
			"enabled": true,
			"mode": Resampler.MODE_MODE,
			"scale": 4.0,
			"offset": Vector2.ZERO,
			"target_size": Vector2i.ZERO,
			"keep_alpha_gradient": false,
			"edge_threshold": Resampler.DEFAULT_EDGE_THRESHOLD,
		},
		STEP_QUANTIZE:
		{
			"enabled": true,
			"mode": Quantizer.MODE_AUTO_K,
			"palette_id": palette_ref,
			"palette_name": "Custom",
			"palette_colors": [],
			"palette_path": "",
			"auto_k_strategy":
			Quantizer.normalize_auto_k_strategy(
				style_preset.get("auto_k_strategy", Quantizer.AUTO_K_STRATEGY_MEDIAN_CUT)
			),
			"k": int(style_preset.get("max_colors_per_sprite", Quantizer.DEFAULT_MAX_COLORS)),
			"dither": String(style_preset.get("dither", Ditherer.MODE_NONE)),
			"dither_matrix": Ditherer.MODE_BAYER4,
			"dither_strength": float(style_preset.get("dither_strength", 0.0)),
			# Chromatic dithering perturbs OKLab lightness and chroma before nearest-color
			# mapping: contrast controls lightness, chroma controls a/b drift, density gates pixels.
			"dither_contrast": float(style_preset.get("dither_strength", 0.0)),
			"dither_chroma": 0.0,
			"dither_density": 1.0,
			"distance": PaletteScript.DISTANCE_OKLAB,
		},
	}


static func normalize_params(params: Dictionary = {}, style_preset: Dictionary = {}) -> Dictionary:
	var normalized := default_params(style_preset)
	_apply_flat_compatibility(normalized, params)
	_merge_step_params(normalized, params)
	_apply_step_controls(normalized, params)
	return normalized


static func get_default_step_ids() -> Array:
	return DEFAULT_STEP_ORDER.duplicate()


static func apply(source: Image, params: Dictionary = {}) -> Dictionary:
	var normalized := normalize_params(params)
	var input := ImageMath.duplicate_rgba8(source)
	var context := {
		"source": input,
		"image": input,
		"params": normalized,
		"grid": {},
		"report":
		{
			"input_size": [input.get_width(), input.get_height()],
			"steps": [],
		},
	}

	for step in _build_steps(normalized):
		if step.is_enabled(normalized):
			context["report"]["steps"].append({"id": step.id, "enabled": true})
			context = step.apply(context)
		else:
			context["report"]["steps"].append({"id": step.id, "enabled": false})

	var output: Image = context["image"]
	context["report"]["output_size"] = [output.get_width(), output.get_height()]
	return {"image": output, "report": context["report"]}


static func _build_steps(params: Dictionary) -> Array:
	var registry := {
		STEP_DETECT_GRID:
		PipelineStep.new(
			STEP_DETECT_GRID,
			"Detect grid",
			true,
			func(context: Dictionary) -> Dictionary: return _step_detect_grid(context)
		),
		STEP_RESAMPLE:
		PipelineStep.new(
			STEP_RESAMPLE,
			"Resample",
			true,
			func(context: Dictionary) -> Dictionary: return _step_resample(context)
		),
		STEP_QUANTIZE:
		PipelineStep.new(
			STEP_QUANTIZE,
			"Quantize",
			true,
			func(context: Dictionary) -> Dictionary: return _step_quantize(context)
		),
	}

	var steps := []
	for step_id in params.get("steps", DEFAULT_STEP_ORDER):
		var normalized_id := String(step_id)
		if registry.has(normalized_id):
			steps.append(registry[normalized_id])
	return steps


static func _step_detect_grid(context: Dictionary) -> Dictionary:
	var image: Image = context["image"]
	var params: Dictionary = context["params"][STEP_DETECT_GRID]
	var mode := String(params.get("mode", DETECT_AUTO))
	var grid := {}
	if mode == DETECT_MANUAL:
		var scale := maxf(1.0, float(params.get("scale", 4.0)))
		grid = {
			"scale": scale,
			"scale_x": scale,
			"scale_y": scale,
			"non_square_warning": false,
			"non_square_ratio": 0.0,
			"offset": params.get("offset", Vector2.ZERO),
			"confidence": 1.0,
			"threshold": GridDetector.LOW_CONFIDENCE_THRESHOLD,
			"status": "manual",
		}
	else:
		var detect_params := _detect_params_for_detector(params)
		grid = GridDetector.detect(image, detect_params)
		if float(grid.get("confidence", 0.0)) < GridDetector.LOW_CONFIDENCE_THRESHOLD:
			grid["scale"] = maxf(1.0, float(params.get("scale", grid.get("scale", 4.0))))
			grid["offset"] = params.get("offset", grid.get("offset", Vector2.ZERO))

	context["grid"] = grid
	context["report"]["detect"] = grid
	context["report"][STEP_DETECT_GRID] = grid
	return context


static func _step_resample(context: Dictionary) -> Dictionary:
	var image: Image = context["image"]
	var params: Dictionary = context["params"][STEP_RESAMPLE]
	var grid: Dictionary = context.get("grid", {})
	var scale := maxf(1.0, float(grid.get("scale", params.get("scale", 4.0))))
	var offset: Vector2 = grid.get("offset", params.get("offset", Vector2.ZERO))
	var output := (
		Resampler
		. resample(
			image,
			{
				"scale": scale,
				"offset": offset,
				"mode": String(params.get("mode", Resampler.MODE_MODE)),
				"target_size": params.get("target_size", Vector2i.ZERO),
				"keep_alpha_gradient": bool(params.get("keep_alpha_gradient", false)),
				"edge_threshold":
				float(params.get("edge_threshold", Resampler.DEFAULT_EDGE_THRESHOLD)),
			}
		)
	)

	context["image"] = output
	context["report"]["resample"] = {
		"mode": String(params.get("mode", Resampler.MODE_MODE)),
		"scale": scale,
		"offset": offset,
		"enabled": true,
	}
	return context


static func _step_quantize(context: Dictionary) -> Dictionary:
	var image: Image = context["image"]
	var params: Dictionary = context["params"][STEP_QUANTIZE]
	var quantize_report := Quantizer.quantize(image, params)
	var output: Image = quantize_report["image"]
	context["image"] = output
	context["report"]["quantize"] = {
		"mode": String(params.get("mode", Quantizer.MODE_AUTO_K)),
		"palette_id": String(params.get("palette_id", "")),
		"auto_k_strategy":
		Quantizer.normalize_auto_k_strategy(
			params.get("auto_k_strategy", Quantizer.AUTO_K_STRATEGY_MEDIAN_CUT)
		),
		"k": int(params.get("k", Quantizer.DEFAULT_MAX_COLORS)),
		"dither": String(params.get("dither", Ditherer.MODE_NONE)),
		"dither_strength": float(params.get("dither_strength", 0.0)),
		"dither_chroma": float(params.get("dither_chroma", 0.0)),
		"dither_density": float(params.get("dither_density", 1.0)),
		"color_count": int(quantize_report["color_count"]),
		"enabled": true,
	}
	return context


static func _detect_params_for_detector(params: Dictionary) -> Dictionary:
	var detect_params := {}
	for key in ["base_size", "prior_scale", "min_lag", "max_lag"]:
		if params.has(key) and float(params[key]) > 0.0:
			detect_params[key] = params[key]
	return detect_params


static func _apply_flat_compatibility(normalized: Dictionary, params: Dictionary) -> void:
	var detect_params: Dictionary = normalized[STEP_DETECT_GRID]
	var resample_params: Dictionary = normalized[STEP_RESAMPLE]
	var quantize_params: Dictionary = normalized[STEP_QUANTIZE]

	if params.has("detect"):
		detect_params["mode"] = String(params["detect"])
		detect_params["enabled"] = String(params["detect"]) != DETECT_NONE
	if params.has("scale"):
		detect_params["scale"] = float(params["scale"])
		resample_params["scale"] = float(params["scale"])
	if params.has("offset"):
		detect_params["offset"] = params["offset"]
		resample_params["offset"] = params["offset"]
	if params.has("base_size"):
		detect_params["base_size"] = int(params["base_size"])
	if params.has("prior_scale"):
		detect_params["prior_scale"] = float(params["prior_scale"])
	if params.has("target_size"):
		resample_params["target_size"] = params["target_size"]
	if params.has("resample") and not (params["resample"] is Dictionary):
		resample_params["mode"] = String(params["resample"])
		resample_params["enabled"] = String(params["resample"]) != "none"
	if params.has("quantize") and not (params["quantize"] is Dictionary):
		quantize_params["mode"] = String(params["quantize"])
	if params.has("palette") and params["palette"] is PFPalette:
		quantize_params["palette"] = params["palette"]

	for key in [
		"palette_id",
		"palette_name",
		"palette_colors",
		"palette_path",
		"palette_json",
		"auto_k_strategy",
		"k",
		"dither",
		"dither_matrix",
		"dither_strength",
		"dither_contrast",
		"dither_chroma",
		"dither_density",
		"distance",
	]:
		if params.has(key):
			quantize_params[key] = params[key]


static func _merge_step_params(normalized: Dictionary, params: Dictionary) -> void:
	for step_id in DEFAULT_STEP_ORDER:
		if params.has(step_id) and params[step_id] is Dictionary:
			var target: Dictionary = normalized[step_id]
			var source: Dictionary = params[step_id]
			for key in source.keys():
				target[key] = source[key]


static func _apply_step_controls(normalized: Dictionary, params: Dictionary) -> void:
	if params.has("steps"):
		_merge_inline_step_entries(normalized, params["steps"])
		normalized["steps"] = _normalize_step_list(params["steps"])
		for step_id in DEFAULT_STEP_ORDER:
			normalized[step_id]["enabled"] = normalized["steps"].has(step_id)
	if params.has("enabled_steps"):
		for step_id in params["enabled_steps"]:
			if DEFAULT_STEP_ORDER.has(String(step_id)):
				normalized[String(step_id)]["enabled"] = true
	if params.has("disabled_steps"):
		for step_id in params["disabled_steps"]:
			if DEFAULT_STEP_ORDER.has(String(step_id)):
				normalized[String(step_id)]["enabled"] = false


static func _normalize_step_list(raw_steps: Variant) -> Array:
	if raw_steps is Dictionary:
		var enabled := []
		for step_id in DEFAULT_STEP_ORDER:
			if bool(raw_steps.get(step_id, false)):
				enabled.append(step_id)
		return enabled
	if raw_steps is Array:
		var normalized := []
		for entry in raw_steps:
			if entry is Dictionary:
				var id := String(entry.get("id", ""))
				if DEFAULT_STEP_ORDER.has(id):
					normalized.append(id)
			elif DEFAULT_STEP_ORDER.has(String(entry)):
				normalized.append(String(entry))
		return normalized
	return DEFAULT_STEP_ORDER.duplicate()


static func _merge_inline_step_entries(normalized: Dictionary, raw_steps: Variant) -> void:
	if not (raw_steps is Array):
		return

	for entry in raw_steps:
		if not (entry is Dictionary):
			continue
		var step_id := String(entry.get("id", ""))
		if not DEFAULT_STEP_ORDER.has(step_id):
			continue
		var target: Dictionary = normalized[step_id]
		for key in entry.keys():
			if key != "id":
				target[key] = entry[key]
