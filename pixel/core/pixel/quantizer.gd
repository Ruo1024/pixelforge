class_name PFQuantizer
extends RefCounted

## 颜色量化器。
## contract: 03-milestones/M1-cleanup-pipeline.md §M1-4；输出颜色数不超过目标调色板或 k。

const ImageMath := preload("res://core/util/image_math.gd")
const ColorSpace := preload("res://core/pixel/color_space.gd")
const PaletteScript := preload("res://core/pixel/palette.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const Ditherer := preload("res://core/pixel/ditherer.gd")

const MODE_NONE := "none"
const MODE_AUTO_K := "auto_k"
const MODE_FIXED_PALETTE := "fixed_palette"
const AUTO_K_STRATEGY_MEDIAN_CUT := "median_cut"
const AUTO_K_STRATEGY_KMEANS := "kmeans"
const DEFAULT_MAX_COLORS := 16
const ALPHA_LIMIT := 128
const KMEANS_SAMPLE_LIMIT := 65536
const KMEANS_MAX_ITERATIONS := 16
# 收敛阈值沿用 M1.1 计划原文的 0.5/255（8bit RGB 半个色阶的保守口径）。
# 注意它作用在 OKLab 欧氏距离上：OKLab 的 L 范围约 0..1、a/b 约 ±0.4，
# 0.5/255 ≈ 0.002 在 OKLab 中略低于一般可感知差异（JND ~0.01–0.02），
# 即"宁可多迭代也不提前停"。如需调整请先更新 M1.1 契约说明再改值。
const KMEANS_CONVERGENCE_DISTANCE := 0.5 / 255.0


static func quantize(source: Image, params: Dictionary = {}) -> Dictionary:
	var mode := String(params.get("mode", MODE_AUTO_K))
	if mode == MODE_NONE:
		return {
			"image": ImageMath.duplicate_rgba8(source),
			"palette": null,
			"color_count": count_colors(source),
		}

	var palette: PFPalette = _resolve_palette(source, params)
	var output := quantize_to_palette(source, palette, params)
	return {
		"image": output,
		"palette": palette,
		"color_count": count_colors(output),
	}


static func quantize_to_palette(
	source: Image, palette: PFPalette, params: Dictionary = {}
) -> Image:
	var dither_mode := String(params.get("dither", Ditherer.MODE_NONE))
	var strength := clampf(float(params.get("dither_strength", 0.0)), 0.0, 1.0)
	var distance_mode := String(params.get("distance", PaletteScript.DISTANCE_OKLAB))
	if dither_mode == Ditherer.MODE_NONE or strength <= 0.0:
		return PaletteScript.map_image(source, palette, distance_mode)
	if dither_mode == Ditherer.MODE_CHROMATIC:
		return _quantize_chromatic(source, palette, params, distance_mode)
	if Ditherer.is_ordered(dither_mode):
		return _quantize_ordered(source, palette, dither_mode, strength, distance_mode)
	if dither_mode == Ditherer.MODE_ERROR_DIFFUSION:
		return _quantize_error_diffusion(source, palette, strength, distance_mode)
	return PaletteScript.map_image(source, palette, distance_mode)


static func count_colors(source: Image, include_transparent: bool = false) -> int:
	var image := ImageMath.duplicate_rgba8(source)
	var seen := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if _alpha_byte(color) < ALPHA_LIMIT and not include_transparent:
				continue
			seen[ColorSpace.color_to_rgba32(color)] = true
	return seen.size()


static func normalize_auto_k_strategy(value: Variant) -> String:
	var strategy := String(value)
	if strategy == AUTO_K_STRATEGY_KMEANS:
		return AUTO_K_STRATEGY_KMEANS
	return AUTO_K_STRATEGY_MEDIAN_CUT


static func _resolve_palette(source: Image, params: Dictionary) -> PFPalette:
	if params.has("palette") and params["palette"] is PFPalette:
		return params["palette"]

	var mode := String(params.get("mode", MODE_AUTO_K))
	if mode == MODE_FIXED_PALETTE:
		return PaletteRegistry.resolve(params)

	var max_colors := int(params.get("k", DEFAULT_MAX_COLORS))
	var strategy := normalize_auto_k_strategy(
		params.get("auto_k_strategy", AUTO_K_STRATEGY_MEDIAN_CUT)
	)
	return _extract_auto_k_palette(source, max_colors, strategy)


static func _extract_auto_k_palette(source: Image, max_colors: int, strategy: String) -> PFPalette:
	var median_palette := PaletteScript.extract_palette(source, max_colors)
	if strategy != AUTO_K_STRATEGY_KMEANS:
		return median_palette
	return _extract_palette_kmeans(source, max_colors, median_palette)


static func _extract_palette_kmeans(
	source: Image, max_colors: int, initial_palette: PFPalette
) -> PFPalette:
	var requested_colors := clampi(
		max_colors, PaletteScript.MIN_PALETTE_COLORS, PaletteScript.MAX_PALETTE_COLORS
	)
	var samples := _collect_kmeans_samples(source)
	if samples.is_empty() or initial_palette.colors.is_empty():
		return initial_palette

	var centers := []
	for color in initial_palette.colors:
		centers.append(ColorSpace.color_to_oklab(color))
	while centers.size() < requested_colors and centers.size() < samples.size():
		var sample: Dictionary = samples[centers.size()]
		centers.append(sample["lab"])

	for _iteration in range(KMEANS_MAX_ITERATIONS):
		var sums := []
		var weights := []
		for _center in centers:
			sums.append(Vector3.ZERO)
			weights.append(0.0)

		for sample in samples:
			var lab: Vector3 = sample["lab"]
			var weight := float(sample["weight"])
			var cluster := _nearest_lab_index(lab, centers)
			sums[cluster] = Vector3(sums[cluster]) + lab * weight
			weights[cluster] = float(weights[cluster]) + weight

		var max_shift := 0.0
		var empty_clusters := []
		for index in range(centers.size()):
			if float(weights[index]) <= 0.0:
				empty_clusters.append(index)
				continue
			var old_center: Vector3 = centers[index]
			var new_center := Vector3(sums[index]) / float(weights[index])
			centers[index] = new_center
			max_shift = maxf(max_shift, old_center.distance_to(new_center))

		# 空簇重播种：丢弃的中心会造成调色板死色/重复色。把每个空簇移动到
		# "距当前所有非空中心最近距离最大"的样本上（即覆盖最差的颜色），
		# 样本按 RGBA32 升序枚举、并列取首个，保证逐像素确定性。
		if not empty_clusters.is_empty():
			max_shift = maxf(max_shift, _reseed_empty_clusters(centers, empty_clusters, samples))

		if max_shift < KMEANS_CONVERGENCE_DISTANCE:
			break

	var extracted := PackedColorArray()
	for center in centers:
		extracted.append(ColorSpace.oklab_to_color(center, 1.0))
	return PFPalette.new("extracted", "Extracted", extracted)


static func _collect_kmeans_samples(source: Image) -> Array:
	var image := ImageMath.duplicate_rgba8(source)
	var width := image.get_width()
	var height := image.get_height()
	var total_pixels := width * height
	var stride := 1
	if total_pixels > KMEANS_SAMPLE_LIMIT:
		stride = int(ceil(sqrt(float(total_pixels) / float(KMEANS_SAMPLE_LIMIT))))

	var color_weights := {}
	for y in range(0, height, stride):
		for x in range(0, width, stride):
			var color := image.get_pixel(x, y)
			if _alpha_byte(color) < ALPHA_LIMIT:
				continue
			var rgba := ColorSpace.color_to_rgba32(color, true)
			color_weights[rgba] = int(color_weights.get(rgba, 0)) + 1

	var keys := color_weights.keys()
	keys.sort()
	var samples := []
	for rgba in keys:
		var color := ColorSpace.rgba32_to_color(int(rgba))
		(
			samples
			. append(
				{
					"lab": ColorSpace.color_to_oklab(color),
					"weight": int(color_weights[rgba]),
				}
			)
		)
	return samples


static func _reseed_empty_clusters(centers: Array, empty_clusters: Array, samples: Array) -> float:
	var reseed_shift := 0.0
	for empty_index in empty_clusters:
		var best_sample_lab := Vector3.ZERO
		var best_distance := -1.0
		for sample in samples:
			var lab: Vector3 = sample["lab"]
			var nearest := INF
			for center_index in range(centers.size()):
				if center_index == empty_index:
					continue
				nearest = minf(
					nearest, ColorSpace.oklab_distance(lab, Vector3(centers[center_index]))
				)
			if nearest > best_distance:
				best_distance = nearest
				best_sample_lab = lab
		if best_distance < 0.0:
			continue
		var old_center: Vector3 = centers[empty_index]
		centers[empty_index] = best_sample_lab
		reseed_shift = maxf(reseed_shift, old_center.distance_to(best_sample_lab))
	return reseed_shift


static func _nearest_lab_index(sample: Vector3, centers: Array) -> int:
	var best_index := 0
	var best_distance := INF
	for index in range(centers.size()):
		var distance := ColorSpace.oklab_distance(sample, Vector3(centers[index]))
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


static func _quantize_ordered(
	source: Image, palette: PFPalette, dither_mode: String, strength: float, distance_mode: String
) -> Image:
	var image := ImageMath.duplicate_rgba8(source)
	var output := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if _alpha_byte(color) < ALPHA_LIMIT:
				output.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var adjusted := Ditherer.ordered_adjust(color, x, y, dither_mode, strength)
			output.set_pixel(x, y, palette.nearest_color(adjusted, distance_mode))
	return output


static func _quantize_chromatic(
	source: Image, palette: PFPalette, params: Dictionary, distance_mode: String
) -> Image:
	var image := ImageMath.duplicate_rgba8(source)
	var output := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	var bayer_mode := String(params.get("dither_matrix", Ditherer.MODE_BAYER4))
	var contrast := float(params.get("dither_contrast", params.get("dither_strength", 0.0)))
	var chroma := float(params.get("dither_chroma", 0.0))
	var density := float(params.get("dither_density", 1.0))
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if _alpha_byte(color) < ALPHA_LIMIT:
				output.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var adjusted := Ditherer.chromatic_adjust(
				color, x, y, bayer_mode, contrast, chroma, density
			)
			output.set_pixel(x, y, palette.nearest_color(adjusted, distance_mode))
	return output


static func _quantize_error_diffusion(
	source: Image, palette: PFPalette, strength: float, distance_mode: String
) -> Image:
	var image := ImageMath.duplicate_rgba8(source)
	var width := image.get_width()
	var height := image.get_height()
	var working := []
	working.resize(width * height)

	for y in range(height):
		for x in range(width):
			working[_index(x, y, width)] = image.get_pixel(x, y)

	var output := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		var serpentine := y % 2 == 1
		for step in range(width):
			var x := width - 1 - step if serpentine else step
			var idx := _index(x, y, width)
			var old_color: Color = working[idx]
			if _alpha_byte(old_color) < ALPHA_LIMIT:
				output.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var new_color := palette.nearest_color(old_color, distance_mode)
			output.set_pixel(x, y, new_color)
			var error := Color(
				(old_color.r - new_color.r) * strength,
				(old_color.g - new_color.g) * strength,
				(old_color.b - new_color.b) * strength,
				0.0
			)
			_diffuse_error(working, width, height, x, y, error, serpentine)
	return output


static func _diffuse_error(
	working: Array, width: int, height: int, x: int, y: int, error: Color, serpentine: bool
) -> void:
	var direction := -1 if serpentine else 1
	_add_error(working, width, height, x + direction, y, error, 7.0 / 16.0)
	_add_error(working, width, height, x - direction, y + 1, error, 3.0 / 16.0)
	_add_error(working, width, height, x, y + 1, error, 5.0 / 16.0)
	_add_error(working, width, height, x + direction, y + 1, error, 1.0 / 16.0)


static func _add_error(
	working: Array, width: int, height: int, x: int, y: int, error: Color, weight: float
) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var idx := _index(x, y, width)
	var color: Color = working[idx]
	if _alpha_byte(color) < ALPHA_LIMIT:
		return
	working[idx] = Color(
		clampf(color.r + error.r * weight, 0.0, 1.0),
		clampf(color.g + error.g * weight, 0.0, 1.0),
		clampf(color.b + error.b * weight, 0.0, 1.0),
		color.a
	)


static func _index(x: int, y: int, width: int) -> int:
	return y * width + x


static func _alpha_byte(color: Color) -> int:
	return ColorSpace.byte_from_unit(color.a)
