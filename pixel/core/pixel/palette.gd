class_name PFPalette
extends RefCounted

## 调色板对象与颜色映射工具。
## contract: 02-contracts/STYLE-PRESETS.md §3；输入 Image 不会被修改，透明像素保留为透明。

const ImageMath := preload("res://core/util/image_math.gd")
const ColorSpace := preload("res://core/pixel/color_space.gd")

const DISTANCE_RGB := "rgb"
const DISTANCE_OKLAB := "oklab"
const TRANSPARENT_RGBA := 0
const OPAQUE_ALPHA := 255
const MIN_PALETTE_COLORS := 2
const MAX_PALETTE_COLORS := 256
const BUILTIN_IDS := [
	"db16",
	"db32",
	"pico8",
	"endesga32",
	"endesga64",
	"aap64",
	"gb_4",
	"nes_full",
	"bw_2",
]

static var _builtin_cache := {}

var id := ""
var name := ""
var colors := PackedColorArray()

var _oklab_colors := []


func _init(
	p_id: String = "", p_name: String = "", p_colors: PackedColorArray = PackedColorArray()
) -> void:
	id = p_id
	name = p_name
	colors = p_colors.duplicate()
	_rebuild_oklab_cache()


static func from_json(value: Dictionary) -> PFPalette:
	var parsed_colors := PackedColorArray()
	for raw_hex in value.get("colors", []):
		parsed_colors.append(hex_to_color(String(raw_hex)))
	return PFPalette.new(String(value.get("id", "")), String(value.get("name", "")), parsed_colors)


static func from_color_values(p_id: String, p_name: String, values: Variant) -> PFPalette:
	if not (values is Array) and not (values is PackedColorArray):
		return null

	var parsed_colors := PackedColorArray()
	for value in values:
		if value is Color:
			parsed_colors.append(value)
		else:
			parsed_colors.append(hex_to_color(String(value)))
	if parsed_colors.is_empty():
		return null
	return PFPalette.new(p_id, p_name, parsed_colors)


static func load_builtin(palette_id: String) -> PFPalette:
	if _builtin_cache.has(palette_id):
		return _builtin_cache[palette_id].duplicate_palette()

	var path := "res://assets/palettes/%s.json" % palette_id
	if not FileAccess.file_exists(path):
		return null

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return null

	var palette := PFPalette.from_json(parsed)
	_builtin_cache[palette_id] = palette
	return palette.duplicate_palette()


static func hex_to_color(hex_text: String) -> Color:
	return ColorSpace.hex_to_color(hex_text)


static func color_to_hex(color: Color) -> String:
	return ColorSpace.color_to_hex(color)


static func color_to_rgba32(color: Color, force_opaque: bool = false) -> int:
	return ColorSpace.color_to_rgba32(color, force_opaque)


static func rgba32_to_color(value: int) -> Color:
	return ColorSpace.rgba32_to_color(value)


static func map_image(
	source: Image, palette: PFPalette, distance_mode: String = DISTANCE_OKLAB
) -> Image:
	var image := ImageMath.duplicate_rgba8(source)
	var output := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	var color_cache := {}

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source_color := image.get_pixel(x, y)
			var rgba := color_to_rgba32(source_color)
			if color_cache.has(rgba):
				output.set_pixel(x, y, color_cache[rgba])
				continue

			var mapped := Color(0, 0, 0, 0)
			if ColorSpace.byte_from_unit(source_color.a) >= 128:
				mapped = palette.nearest_color(source_color, distance_mode)
				mapped.a = 1.0
			color_cache[rgba] = mapped
			output.set_pixel(x, y, mapped)

	return output


static func extract_palette(
	source: Image, max_colors: int, palette_id: String = "extracted"
) -> PFPalette:
	var requested_colors := clampi(max_colors, MIN_PALETTE_COLORS, MAX_PALETTE_COLORS)
	var color_counts := _collect_opaque_color_counts(source)
	var unique_colors := color_counts.keys()
	if unique_colors.is_empty():
		return PFPalette.new(palette_id, "Extracted", PackedColorArray([Color.BLACK, Color.WHITE]))

	if unique_colors.size() <= requested_colors:
		unique_colors.sort()
		return PFPalette.new(palette_id, "Extracted", _colors_from_rgba_keys(unique_colors))

	var boxes := [unique_colors]
	while boxes.size() < requested_colors:
		var split_index := _largest_range_box_index(boxes)
		if split_index < 0:
			break

		var box: Array = boxes[split_index]
		var channel := _widest_channel(box)
		box.sort_custom(
			func(left: int, right: int) -> bool:
				return _channel_value(left, channel) < _channel_value(right, channel)
		)

		var midpoint := maxi(1, box.size() / 2)
		var left_box := box.slice(0, midpoint)
		var right_box := box.slice(midpoint)
		if left_box.is_empty() or right_box.is_empty():
			break

		boxes.remove_at(split_index)
		boxes.append(left_box)
		boxes.append(right_box)

	var extracted := PackedColorArray()
	for box in boxes:
		extracted.append(_average_box_color(box, color_counts))

	return PFPalette.new(palette_id, "Extracted", extracted)


func duplicate_palette() -> PFPalette:
	return PFPalette.new(id, name, colors)


func to_json() -> Dictionary:
	var hex_colors := []
	for color in colors:
		hex_colors.append(color_to_hex(color))
	return {
		"id": id,
		"name": name,
		"colors": hex_colors,
		"source": "lospec",
		"license": "CC0",
	}


func get_color_count() -> int:
	return colors.size()


func nearest_color(color: Color, distance_mode: String = DISTANCE_OKLAB) -> Color:
	var index := nearest_color_index(color, distance_mode)
	if index < 0:
		return Color(0, 0, 0, 0)
	return colors[index]


func nearest_color_index(color: Color, distance_mode: String = DISTANCE_OKLAB) -> int:
	if colors.is_empty():
		return -1

	var best_index := 0
	var best_distance := INF
	var use_oklab := distance_mode == DISTANCE_OKLAB
	var sample_oklab := ColorSpace.color_to_oklab(color) if use_oklab else Vector3.ZERO
	for index in range(colors.size()):
		var distance := (
			ColorSpace.oklab_distance(sample_oklab, _oklab_colors[index])
			if use_oklab
			else ColorSpace.rgb_distance(color, colors[index])
		)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func map(source: Image, distance_mode: String = DISTANCE_OKLAB) -> Image:
	return PFPalette.map_image(source, self, distance_mode)


func _rebuild_oklab_cache() -> void:
	_oklab_colors.clear()
	for color in colors:
		_oklab_colors.append(ColorSpace.color_to_oklab(color))


static func _collect_opaque_color_counts(source: Image) -> Dictionary:
	var image := ImageMath.duplicate_rgba8(source)
	var color_counts := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if ColorSpace.byte_from_unit(color.a) < 128:
				continue
			var rgba := color_to_rgba32(color, true)
			color_counts[rgba] = int(color_counts.get(rgba, 0)) + 1
	return color_counts


static func _colors_from_rgba_keys(keys: Array) -> PackedColorArray:
	var output := PackedColorArray()
	for rgba in keys:
		output.append(rgba32_to_color(int(rgba)))
	return output


static func _largest_range_box_index(boxes: Array) -> int:
	var best_index := -1
	var best_score := -1
	for index in range(boxes.size()):
		var box: Array = boxes[index]
		if box.size() < 2:
			continue
		var range_score := _box_range(box) * box.size()
		if range_score > best_score:
			best_score = range_score
			best_index = index
	return best_index


static func _box_range(box: Array) -> int:
	var ranges := _channel_ranges(box)
	return maxi(ranges[0], maxi(ranges[1], ranges[2]))


static func _widest_channel(box: Array) -> int:
	var ranges := _channel_ranges(box)
	if ranges[0] >= ranges[1] and ranges[0] >= ranges[2]:
		return 0
	if ranges[1] >= ranges[0] and ranges[1] >= ranges[2]:
		return 1
	return 2


static func _channel_ranges(box: Array) -> Array:
	var mins := [255, 255, 255]
	var maxs := [0, 0, 0]
	for rgba in box:
		for channel in range(3):
			var value := _channel_value(int(rgba), channel)
			mins[channel] = mini(mins[channel], value)
			maxs[channel] = maxi(maxs[channel], value)
	return [maxs[0] - mins[0], maxs[1] - mins[1], maxs[2] - mins[2]]


static func _average_box_color(box: Array, color_counts: Dictionary) -> Color:
	var total_weight := 0
	var totals := [0, 0, 0]
	for rgba in box:
		var key := int(rgba)
		var weight := int(color_counts.get(key, 1))
		total_weight += weight
		for channel in range(3):
			totals[channel] += _channel_value(key, channel) * weight
	if total_weight <= 0:
		return rgba32_to_color(int(box[0]))
	return Color8(
		int(round(float(totals[0]) / float(total_weight))),
		int(round(float(totals[1]) / float(total_weight))),
		int(round(float(totals[2]) / float(total_weight))),
		OPAQUE_ALPHA
	)


static func _channel_value(rgba: int, channel: int) -> int:
	match channel:
		0:
			return (rgba >> 24) & 0xff
		1:
			return (rgba >> 16) & 0xff
		_:
			return (rgba >> 8) & 0xff
