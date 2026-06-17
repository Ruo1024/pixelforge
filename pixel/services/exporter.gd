class_name PFExporter
extends RefCounted

## 素材导出器 v1。
## contract: 03-milestones/M2-matting-slicing.md §M2-5；PLUGIN-API.md §2 register_exporter 预留能力。
## 输入 items 统一为 Dictionary 数组：{"name": String, "image": Image, "id": String?}。
## 输出 PNG 使用最近邻放大；spritesheet JSON 对齐 TexturePacker JSON hash 的常用子集。

const FileIOScript := preload("res://infra/file_io.gd")
const ImageMath := preload("res://core/util/image_math.gd")

const MODE_FILES := "files"
const MODE_SPRITESHEET := "spritesheet"
const DEFAULT_TEMPLATE := "{name}.png"
const DEFAULT_PADDING := 0
const DEFAULT_SCALE := 1


static func export_png(image: Image, path: String, params: Dictionary = {}) -> Error:
	var scale := int(params.get("scale", DEFAULT_SCALE))
	var output := _scaled_nearest(image, scale)
	return FileIOScript.save_png(output, path)


static func export_files(
	items: Array, directory_path: String, params: Dictionary = {}
) -> Dictionary:
	var template := String(params.get("template", DEFAULT_TEMPLATE))
	var scale := int(params.get("scale", DEFAULT_SCALE))
	var written := []
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var file_name := _render_template(template, item, i)
		if not file_name.to_lower().ends_with(".png"):
			file_name += ".png"
		var path := directory_path.path_join(file_name)
		var error := export_png(item["image"], path, {"scale": scale})
		if error != OK:
			return {"ok": false, "error": error, "files": written}
		written.append(path)
	return {"ok": true, "error": OK, "files": written}


static func export_spritesheet(
	items: Array, png_path: String, params: Dictionary = {}
) -> Dictionary:
	var packed := pack_spritesheet(items, params)
	var image: Image = packed["image"]
	var error := FileIOScript.save_png(image, png_path)
	if error != OK:
		return {"ok": false, "error": error, "png": png_path, "json": ""}

	var json_path := String(params.get("json_path", png_path.get_basename() + ".json"))
	error = FileIOScript.atomic_write(json_path, FileIOScript.json_to_bytes(packed["json"]))
	if error != OK:
		return {"ok": false, "error": error, "png": png_path, "json": json_path}
	return {"ok": true, "error": OK, "png": png_path, "json": json_path, "meta": packed["json"]}


static func pack_spritesheet(items: Array, params: Dictionary = {}) -> Dictionary:
	var padding := maxi(0, int(params.get("padding", DEFAULT_PADDING)))
	var scale := maxi(1, int(params.get("scale", DEFAULT_SCALE)))
	var columns := int(params.get("columns", 0))
	if columns <= 0:
		columns = ceili(sqrt(float(maxi(1, items.size()))))

	var scaled_items := []
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var source_image: Image = item["image"]
		(
			scaled_items
			. append(
				{
					"name": _sprite_name(item, i),
					"image": _scaled_nearest(source_image, scale),
					"source_size": source_image.get_size(),
				}
			)
		)

	var rows := ceili(float(scaled_items.size()) / float(columns))
	var column_widths := PackedInt32Array()
	var row_heights := PackedInt32Array()
	column_widths.resize(columns)
	row_heights.resize(rows)
	for i in range(scaled_items.size()):
		var col := i % columns
		var row := int(i / columns)
		var image: Image = scaled_items[i]["image"]
		column_widths[col] = maxi(column_widths[col], image.get_width())
		row_heights[row] = maxi(row_heights[row], image.get_height())

	var sheet_w := _sum_ints(column_widths) + padding * maxi(0, columns - 1)
	var sheet_h := _sum_ints(row_heights) + padding * maxi(0, rows - 1)
	var sheet := Image.create(maxi(1, sheet_w), maxi(1, sheet_h), false, Image.FORMAT_RGBA8)
	sheet.fill(Color.TRANSPARENT)

	var frames := {}
	for i in range(scaled_items.size()):
		var col := i % columns
		var row := int(i / columns)
		var pos := Vector2i(
			_offset_for(column_widths, col, padding), _offset_for(row_heights, row, padding)
		)
		var image: Image = scaled_items[i]["image"]
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), pos)
		var file_name := "%s.png" % String(scaled_items[i]["name"])
		var source_size: Vector2i = scaled_items[i]["source_size"]
		frames[file_name] = {
			"frame": {"x": pos.x, "y": pos.y, "w": image.get_width(), "h": image.get_height()},
			"rotated": false,
			"trimmed": false,
			"spriteSourceSize": {"x": 0, "y": 0, "w": image.get_width(), "h": image.get_height()},
			"sourceSize": {"w": source_size.x * scale, "h": source_size.y * scale},
		}

	return {
		"image": sheet,
		"json":
		{
			"frames": frames,
			"meta":
			{
				"app": "PixelForge",
				"image": String(params.get("image", "spritesheet.png")),
				"format": "RGBA8888",
				"scale": str(scale),
				"size": {"w": sheet.get_width(), "h": sheet.get_height()},
			},
		},
	}


static func _scaled_nearest(source: Image, scale: int) -> Image:
	var output := ImageMath.duplicate_rgba8(source)
	var normalized_scale := maxi(1, scale)
	if normalized_scale == 1:
		return output
	output.resize(
		output.get_width() * normalized_scale,
		output.get_height() * normalized_scale,
		Image.INTERPOLATE_NEAREST
	)
	return output


static func _render_template(template: String, item: Dictionary, index: int) -> String:
	return template.replace("{name}", _sprite_name(item, index)).replace(
		"{index}", "%02d" % (index + 1)
	)


static func _sprite_name(item: Dictionary, index: int) -> String:
	var raw_name := String(item.get("name", item.get("id", "sprite_%02d" % (index + 1))))
	var safe := raw_name.strip_edges().replace(" ", "_")
	if safe.is_empty():
		safe = "sprite_%02d" % (index + 1)
	return safe


static func _sum_ints(values: PackedInt32Array) -> int:
	var total := 0
	for value in values:
		total += value
	return total


static func _offset_for(values: PackedInt32Array, index: int, padding: int) -> int:
	var offset := 0
	for i in range(index):
		offset += values[i] + padding
	return offset
