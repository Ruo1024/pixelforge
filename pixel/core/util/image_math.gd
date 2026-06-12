class_name PFImageMath
extends RefCounted

## 图像数学公共函数。
## contract: 01-architecture/ARCHITECTURE.md §4.1，所有函数不修改入参，返回新的 Image。


static func duplicate_rgba8(source: Image) -> Image:
	var copy := source.duplicate()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	return copy


static func estimate_rgba8_bytes(image: Image) -> int:
	return image.get_width() * image.get_height() * 4


static func snapshot_region(source: Image, rect: Rect2i) -> Image:
	var image_bounds := Rect2i(Vector2i.ZERO, source.get_size())
	var clipped := rect.intersection(image_bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)

	var snapshot := Image.create(clipped.size.x, clipped.size.y, false, source.get_format())
	snapshot.blit_rect(source, clipped, Vector2i.ZERO)
	return snapshot


static func color_set(image: Image) -> Dictionary:
	var colors := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			colors[image.get_pixel(x, y).to_html(true)] = true
	return colors
