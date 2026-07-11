class_name PFRepairAnalysis
extends RefCounted

## AI-output repair helpers: isolated-noise cleanup and 1px outline endpoint detection.


static func clean_noise(image: Image, max_occurrences: int = 2) -> Array[Vector2i]:
	var counts := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var key := image.get_pixel(x, y).to_html()
			counts[key] = int(counts.get(key, 0)) + 1
	var changed: Array[Vector2i] = []
	var source := image.duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point := Vector2i(x, y)
			var current: Color = source.get_pixelv(point)
			if current.a <= 0.0 or int(counts.get(current.to_html(), 0)) > max_occurrences:
				continue
			var replacement := _neighbor_majority(source, point)
			if replacement.a <= 0.0 or _protected_highlight(current, replacement):
				continue
			if not replacement.is_equal_approx(current):
				image.set_pixelv(point, replacement)
				changed.append(point)
	return changed


static func outline_endpoints(image: Image) -> Array[Vector2i]:
	var endpoints: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point := Vector2i(x, y)
			if image.get_pixelv(point).a <= 0.0:
				continue
			var neighbors := 0
			for offset in [
				Vector2i.LEFT,
				Vector2i.RIGHT,
				Vector2i.UP,
				Vector2i.DOWN,
				Vector2i(-1, -1),
				Vector2i(1, -1),
				Vector2i(-1, 1),
				Vector2i(1, 1)
			]:
				var candidate: Vector2i = point + offset
				if (
					Rect2i(Vector2i.ZERO, image.get_size()).has_point(candidate)
					and image.get_pixelv(candidate).a > 0.0
				):
					neighbors += 1
			if neighbors == 1:
				endpoints.append(point)
	return endpoints


static func _neighbor_majority(image: Image, point: Vector2i) -> Color:
	var counts := {}
	var colors := {}
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = point + offset
		if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(candidate):
			continue
		var color := image.get_pixelv(candidate)
		if color.a <= 0.0:
			continue
		var key := color.to_html()
		counts[key] = int(counts.get(key, 0)) + 1
		colors[key] = color
	var best_key := ""
	var best_count := 0
	for key in counts:
		if int(counts[key]) > best_count:
			best_key = String(key)
			best_count = int(counts[key])
	return colors.get(best_key, Color.TRANSPARENT)


static func _protected_highlight(current: Color, replacement: Color) -> bool:
	return current.get_luminance() - replacement.get_luminance() >= 0.35
