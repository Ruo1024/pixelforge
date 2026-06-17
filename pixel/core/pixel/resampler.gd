class_name PFResampler
extends RefCounted

## 网格重采样器。
## contract: 03-milestones/M1-cleanup-pipeline.md §M1-3；按物理网格降到逻辑像素图。

const ImageMath := preload("res://core/util/image_math.gd")
const ColorSpace := preload("res://core/pixel/color_space.gd")

const MODE_MODE := "mode"
const MODE_CENTER := "center"
const MODE_MEDIAN := "median"
const MODE_EDGE_AWARE := "edge_aware"
const DEFAULT_SCALE := 4.0
const TRANSPARENT_ALPHA_LIMIT := 128
const DEFAULT_EDGE_THRESHOLD := 0.15


static func resample(source: Image, params: Dictionary = {}) -> Image:
	var image := ImageMath.duplicate_rgba8(source)
	var scale := maxf(0.001, float(params.get("scale", DEFAULT_SCALE)))
	var offset: Vector2 = params.get("offset", Vector2.ZERO)
	var mode := String(params.get("mode", MODE_MODE))
	var keep_alpha_gradient := bool(params.get("keep_alpha_gradient", false))
	var edge_threshold := float(params.get("edge_threshold", DEFAULT_EDGE_THRESHOLD))
	var target_size: Vector2i = params.get("target_size", Vector2i.ZERO)
	if target_size.x <= 0 or target_size.y <= 0:
		target_size = Vector2i(
			maxi(1, int(ceil(float(image.get_width()) / scale))),
			maxi(1, int(ceil(float(image.get_height()) / scale)))
		)

	var output := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	for y in range(target_size.y):
		for x in range(target_size.x):
			var cell := _cell_rect(image, x, y, scale, offset)
			var color := _sample_cell(image, cell, mode, keep_alpha_gradient, edge_threshold)
			output.set_pixel(x, y, color)
	return output


static func _cell_rect(
	image: Image, cell_x: int, cell_y: int, scale: float, offset: Vector2
) -> Rect2i:
	var start_x := floori(offset.x + float(cell_x) * scale)
	var start_y := floori(offset.y + float(cell_y) * scale)
	var end_x := ceili(offset.x + float(cell_x + 1) * scale)
	var end_y := ceili(offset.y + float(cell_y + 1) * scale)
	var rect := Rect2i(Vector2i(start_x, start_y), Vector2i(end_x - start_x, end_y - start_y))
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var clipped := rect.intersection(bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		var fallback_x := clampi(
			int(round(offset.x + (float(cell_x) + 0.5) * scale)), 0, image.get_width() - 1
		)
		var fallback_y := clampi(
			int(round(offset.y + (float(cell_y) + 0.5) * scale)), 0, image.get_height() - 1
		)
		return Rect2i(Vector2i(fallback_x, fallback_y), Vector2i.ONE)
	return clipped


static func _sample_cell(
	image: Image, cell: Rect2i, mode: String, keep_alpha_gradient: bool, edge_threshold: float
) -> Color:
	match mode:
		MODE_CENTER:
			return _sample_center(image, cell, keep_alpha_gradient)
		MODE_MEDIAN:
			return _sample_median(image, cell, keep_alpha_gradient)
		MODE_EDGE_AWARE:
			return _sample_edge_aware(image, cell, keep_alpha_gradient, edge_threshold)
		_:
			return _sample_mode(image, cell, keep_alpha_gradient)


static func _sample_center(image: Image, cell: Rect2i, keep_alpha_gradient: bool) -> Color:
	var center := cell.position + cell.size / 2
	var color := image.get_pixel(
		clampi(center.x, 0, image.get_width() - 1), clampi(center.y, 0, image.get_height() - 1)
	)
	return _normalize_alpha(color, keep_alpha_gradient)


static func _sample_mode(image: Image, cell: Rect2i, keep_alpha_gradient: bool) -> Color:
	var counts := {}
	var nearest_center_distance := {}
	var cell_center := Vector2(cell.position) + Vector2(cell.size) * 0.5

	for y in range(cell.position.y, cell.position.y + cell.size.y):
		for x in range(cell.position.x, cell.position.x + cell.size.x):
			var color := image.get_pixel(x, y)
			var key := 0
			if _alpha_byte(color) >= TRANSPARENT_ALPHA_LIMIT:
				key = ColorSpace.color_to_rgba32(Color(color.r, color.g, color.b, 1.0), true)

			counts[key] = int(counts.get(key, 0)) + 1
			var distance := Vector2(x, y).distance_squared_to(cell_center)
			nearest_center_distance[key] = minf(
				float(nearest_center_distance.get(key, INF)), distance
			)

	var best_key := 0
	var best_count := -1
	var best_distance := INF
	for key in counts.keys():
		var count := int(counts[key])
		var distance := float(nearest_center_distance[key])
		if count > best_count or (count == best_count and distance < best_distance):
			best_key = int(key)
			best_count = count
			best_distance = distance

	if best_key == 0:
		return Color(0, 0, 0, 0)
	var result := ColorSpace.rgba32_to_color(best_key)
	return _normalize_alpha(result, keep_alpha_gradient)


static func _sample_median(image: Image, cell: Rect2i, keep_alpha_gradient: bool) -> Color:
	var channels := [[], [], [], []]
	for y in range(cell.position.y, cell.position.y + cell.size.y):
		for x in range(cell.position.x, cell.position.x + cell.size.x):
			var color := image.get_pixel(x, y)
			channels[0].append(_byte_from_unit(color.r))
			channels[1].append(_byte_from_unit(color.g))
			channels[2].append(_byte_from_unit(color.b))
			channels[3].append(_byte_from_unit(color.a))

	for channel in channels:
		channel.sort()
	var middle := int(channels[0].size() / 2)
	var result := Color8(
		int(channels[0][middle]),
		int(channels[1][middle]),
		int(channels[2][middle]),
		int(channels[3][middle])
	)
	return _normalize_alpha(result, keep_alpha_gradient)


static func _sample_edge_aware(
	image: Image, cell: Rect2i, keep_alpha_gradient: bool, threshold: float
) -> Color:
	if not _is_edge_cell(image, cell, threshold):
		return _sample_mode(image, cell, keep_alpha_gradient)

	var center_color := _sample_center(image, cell, keep_alpha_gradient)
	var mode_color := _sample_mode(image, cell, keep_alpha_gradient)
	if absf(_luma(center_color) - _luma(mode_color)) > threshold:
		return center_color
	return mode_color


static func _is_edge_cell(image: Image, cell: Rect2i, threshold: float) -> bool:
	var min_luma := 1.0
	var max_luma := 0.0
	for y in range(cell.position.y, cell.position.y + cell.size.y):
		for x in range(cell.position.x, cell.position.x + cell.size.x):
			var color := image.get_pixel(x, y)
			if _alpha_byte(color) < TRANSPARENT_ALPHA_LIMIT:
				continue
			var luma := _luma(color)
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
	return max_luma - min_luma > threshold


static func _normalize_alpha(color: Color, keep_alpha_gradient: bool) -> Color:
	if keep_alpha_gradient:
		return color
	if _alpha_byte(color) < TRANSPARENT_ALPHA_LIMIT:
		return Color(0, 0, 0, 0)
	return Color(color.r, color.g, color.b, 1.0)


static func _alpha_byte(color: Color) -> int:
	return ColorSpace.byte_from_unit(color.a)


static func _byte_from_unit(value: float) -> int:
	return ColorSpace.byte_from_unit(value)


static func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114
