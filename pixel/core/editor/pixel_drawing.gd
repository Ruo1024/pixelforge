class_name PFPixelDrawing
extends RefCounted

## Deterministic pixel-perfect drawing primitives for the repair editor.


static func bresenham(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var current := start
	var dx := absi(finish.x - start.x)
	var step_x := 1 if start.x < finish.x else -1
	var dy := -absi(finish.y - start.y)
	var step_y := 1 if start.y < finish.y else -1
	var error := dx + dy
	while true:
		points.append(current)
		if current == finish:
			break
		var twice := error * 2
		if twice >= dy:
			error += dy
			current.x += step_x
		if twice <= dx:
			error += dx
			current.y += step_y
	return points


static func pixel_perfect(points: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for point in points:
		result.append(point)
		if result.size() < 3:
			continue
		var a := result[result.size() - 3]
		var b := result[result.size() - 2]
		var c := result[result.size() - 1]
		var first := b - a
		var second := c - b
		if absi(first.x) + absi(first.y) == 1 and absi(second.x) + absi(second.y) == 1:
			if first.x != 0 and second.y != 0 or first.y != 0 and second.x != 0:
				result.remove_at(result.size() - 2)
	return result


static func stroke(
	image: Image,
	start: Vector2i,
	finish: Vector2i,
	color: Color,
	size: int = 1,
	circular: bool = false,
	pixel_perfect_mode: bool = true,
	mirror_h: bool = false,
	mirror_v: bool = false
) -> Rect2i:
	var points := bresenham(start, finish)
	if pixel_perfect_mode:
		points = pixel_perfect(points)
	var dirty := Rect2i(start, Vector2i.ONE)
	for point in points:
		for mirrored in _mirrors(point, image.get_size(), mirror_h, mirror_v):
			dirty = dirty.merge(_stamp(image, mirrored, color, size, circular))
	return dirty


static func flood_fill(image: Image, start: Vector2i, color: Color, global: bool = false) -> Rect2i:
	if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(start):
		return Rect2i()
	var target := image.get_pixelv(start)
	if target.is_equal_approx(color):
		return Rect2i(start, Vector2i.ONE)
	if global:
		var dirty := Rect2i(start, Vector2i.ONE)
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).is_equal_approx(target):
					image.set_pixel(x, y, color)
					dirty = dirty.merge(Rect2i(x, y, 1, 1))
		return dirty
	var queue: Array[Vector2i] = [start]
	var seen := {}
	var bounds := Rect2i(start, Vector2i.ONE)
	while not queue.is_empty():
		var point: Vector2i = queue.pop_front()
		if seen.has(point) or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
			continue
		seen[point] = true
		if not image.get_pixelv(point).is_equal_approx(target):
			continue
		image.set_pixelv(point, color)
		bounds = bounds.merge(Rect2i(point, Vector2i.ONE))
		queue.append_array(
			[
				point + Vector2i.LEFT,
				point + Vector2i.RIGHT,
				point + Vector2i.UP,
				point + Vector2i.DOWN
			]
		)
	return bounds


static func rectangle(image: Image, rect: Rect2i, color: Color, filled: bool = false) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if (
				filled
				or x in [rect.position.x, rect.end.x - 1]
				or y in [rect.position.y, rect.end.y - 1]
			):
				_set_if_inside(image, Vector2i(x, y), color)


static func ellipse(image: Image, rect: Rect2i, color: Color) -> void:
	var center := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
	var radius := Vector2(maxi(1, rect.size.x - 1), maxi(1, rect.size.y - 1)) * 0.5
	for step in range(maxi(12, int(TAU * maxf(radius.x, radius.y) * 2.0))):
		var angle := TAU * float(step) / float(maxi(1, int(TAU * maxf(radius.x, radius.y) * 2.0)))
		_set_if_inside(
			image,
			Vector2i((center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)).round()),
			color
		)


static func nearest_palette_color(color: Color, palette: Array[Color]) -> Color:
	if palette.is_empty():
		return color
	var best := palette[0]
	var best_distance := INF
	for candidate in palette:
		var distance := _oklab_distance_squared(color, candidate)
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


static func _stamp(
	image: Image, center: Vector2i, color: Color, size: int, circular: bool
) -> Rect2i:
	var diameter := clampi(size, 1, 8)
	var origin := center - Vector2i(diameter / 2, diameter / 2)
	var rect := Rect2i(origin, Vector2i(diameter, diameter))
	for y in range(diameter):
		for x in range(diameter):
			if (
				circular
				and (
					Vector2(x, y).distance_to(Vector2(diameter - 1, diameter - 1) * 0.5)
					> diameter * 0.5
				)
			):
				continue
			_set_if_inside(image, origin + Vector2i(x, y), color)
	return rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))


static func _mirrors(
	point: Vector2i, image_size: Vector2i, mirror_h: bool, mirror_v: bool
) -> Array[Vector2i]:
	var points: Array[Vector2i] = [point]
	if mirror_h:
		points.append(Vector2i(image_size.x - point.x - 1, point.y))
	if mirror_v:
		points.append(Vector2i(point.x, image_size.y - point.y - 1))
	if mirror_h and mirror_v:
		points.append(Vector2i(image_size.x - point.x - 1, image_size.y - point.y - 1))
	return points


static func _set_if_inside(image: Image, point: Vector2i, color: Color) -> void:
	if Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
		image.set_pixelv(point, color)


static func _oklab_distance_squared(a: Color, b: Color) -> float:
	var lab_a := _linear_to_oklab(a.srgb_to_linear())
	var lab_b := _linear_to_oklab(b.srgb_to_linear())
	return lab_a.distance_squared_to(lab_b)


static func _linear_to_oklab(color: Color) -> Vector3:
	var l := 0.4122214708 * color.r + 0.5363325363 * color.g + 0.0514459929 * color.b
	var m := 0.2119034982 * color.r + 0.6806995451 * color.g + 0.1073969566 * color.b
	var s := 0.0883024619 * color.r + 0.2817188376 * color.g + 0.6299787005 * color.b
	var l_root := signf(l) * pow(absf(l), 1.0 / 3.0)
	var m_root := signf(m) * pow(absf(m), 1.0 / 3.0)
	var s_root := signf(s) * pow(absf(s), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l_root + 0.793617785 * m_root - 0.0040720468 * s_root,
		1.9779984951 * l_root - 2.428592205 * m_root + 0.4505937099 * s_root,
		0.0259040371 * l_root + 0.7827717662 * m_root - 0.808675766 * s_root
	)
