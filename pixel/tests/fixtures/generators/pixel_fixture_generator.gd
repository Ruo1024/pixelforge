class_name PFPixelFixtureGenerator
extends RefCounted

## M1 黄金样本生成器。
## 所有算法真值由代码生成，避免手工 PNG 变成不可追踪的测试来源。

const PaletteScript := preload("res://core/pixel/palette.gd")


static func make_base_sprite(size: Vector2i = Vector2i(16, 16), variant: int = 0) -> Image:
	var palette := [
		Color8(20, 20, 36),
		Color8(89, 125, 206),
		Color8(214, 125, 44),
		Color8(109, 170, 44),
		Color8(222, 238, 214),
	]
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(palette[0])
	for y in range(size.y):
		for x in range(size.x):
			if x == y or x == size.x - y - 1:
				image.set_pixel(x, y, palette[4])
			elif (x + y + variant) % 7 == 0:
				image.set_pixel(x, y, palette[2])
			elif x > size.x / 4 and x < size.x * 3 / 4 and y > size.y / 4 and y < size.y * 3 / 4:
				image.set_pixel(x, y, palette[1 + variant % 3])
			elif (x / 2 + y / 3 + variant) % 3 == 0:
				image.set_pixel(x, y, palette[3])
	return image


static func make_checkerboard(size: Vector2i, colors: Array, tile_size: int = 1) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var index := (int(x / tile_size) + int(y / tile_size)) % colors.size()
			image.set_pixel(x, y, colors[index])
	return image


static func make_gradient(size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var value := float(x) / maxf(1.0, float(size.x - 1))
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	return image


static func scale_nearest(source: Image, factor: int) -> Image:
	var output := Image.create(
		source.get_width() * factor, source.get_height() * factor, false, Image.FORMAT_RGBA8
	)
	for y in range(output.get_height()):
		for x in range(output.get_width()):
			output.set_pixel(x, y, source.get_pixel(int(x / factor), int(y / factor)))
	return output


static func scale_bilinear(source: Image, scale: float, offset: Vector2 = Vector2.ZERO) -> Image:
	var width := maxi(1, int(ceil(float(source.get_width()) * scale + offset.x)))
	var height := maxi(1, int(ceil(float(source.get_height()) * scale + offset.y)))
	var output := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		for x in range(width):
			var src_x := (float(x) - offset.x) / scale
			var src_y := (float(y) - offset.y) / scale
			output.set_pixel(x, y, _sample_bilinear(source, src_x, src_y))
	return output


static func jpeg_roundtrip(source: Image, quality: float = 0.85) -> Image:
	var rgba := source.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bytes: PackedByteArray = rgba.save_jpg_to_buffer(clampf(quality, 0.0, 1.0))
	var output := Image.new()
	var error := output.load_jpg_from_buffer(bytes)
	if error != OK:
		return rgba
	if output.get_format() != Image.FORMAT_RGBA8:
		output.convert(Image.FORMAT_RGBA8)
	return output


static func add_cell_center_noise(source: Image, factor: int, ratio: float) -> Image:
	var image := source.duplicate()
	var cells_x := source.get_width() / factor
	var cells_y := source.get_height() / factor
	var changed := 0
	var target := int(round(float(cells_x * cells_y) * ratio))
	for y in range(cells_y):
		for x in range(cells_x):
			if changed >= target:
				return image
			var center_x := x * factor + factor / 2
			var center_y := y * factor + factor / 2
			image.set_pixel(center_x, center_y, Color.MAGENTA)
			changed += 1
	return image


static func similarity(left: Image, right: Image) -> float:
	var width := mini(left.get_width(), right.get_width())
	var height := mini(left.get_height(), right.get_height())
	var matches := 0
	for y in range(height):
		for x in range(width):
			if (
				PaletteScript.color_to_rgba32(left.get_pixel(x, y))
				== PaletteScript.color_to_rgba32(right.get_pixel(x, y))
			):
				matches += 1
	return float(matches) / maxf(1.0, float(width * height))


static func _sample_bilinear(source: Image, x: float, y: float) -> Color:
	var clamped_x := clampf(x, 0.0, float(source.get_width() - 1))
	var clamped_y := clampf(y, 0.0, float(source.get_height() - 1))
	var x0 := floori(clamped_x)
	var y0 := floori(clamped_y)
	var x1 := mini(x0 + 1, source.get_width() - 1)
	var y1 := mini(y0 + 1, source.get_height() - 1)
	var tx := clamped_x - float(x0)
	var ty := clamped_y - float(y0)
	var top := source.get_pixel(x0, y0).lerp(source.get_pixel(x1, y0), tx)
	var bottom := source.get_pixel(x0, y1).lerp(source.get_pixel(x1, y1), tx)
	return top.lerp(bottom, ty)
