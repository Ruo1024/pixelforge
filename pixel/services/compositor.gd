class_name PFCompositor
extends RefCounted

## Shared pixel compositor used by Board export and the M6 edit document.


static func blend_image(
	destination: Image,
	source: Image,
	position: Vector2i = Vector2i.ZERO,
	opacity: float = 1.0,
	blend: String = "normal",
	flip_h: bool = false
) -> void:
	var alpha_scale := clampf(opacity, 0.0, 1.0)
	for source_y in range(source.get_height()):
		var target_y := position.y + source_y
		if target_y < 0 or target_y >= destination.get_height():
			continue
		for source_x in range(source.get_width()):
			var target_x := position.x + source_x
			if target_x < 0 or target_x >= destination.get_width():
				continue
			var read_x := source.get_width() - source_x - 1 if flip_h else source_x
			var source_color := source.get_pixel(read_x, source_y)
			source_color.a *= alpha_scale
			if source_color.a > 0.0:
				destination.set_pixel(
					target_x,
					target_y,
					blend_color(destination.get_pixel(target_x, target_y), source_color, blend)
				)


static func blend_color(destination: Color, source: Color, blend: String) -> Color:
	var alpha := source.a + destination.a * (1.0 - source.a)
	if blend == "add":
		return Color(
			minf(1.0, destination.r + source.r * source.a),
			minf(1.0, destination.g + source.g * source.a),
			minf(1.0, destination.b + source.b * source.a),
			alpha
		)
	if blend == "multiply":
		return Color(
			destination.r * lerpf(1.0, source.r, source.a),
			destination.g * lerpf(1.0, source.g, source.a),
			destination.b * lerpf(1.0, source.b, source.a),
			alpha
		)
	if alpha <= 0.0:
		return Color.TRANSPARENT
	return Color(
		(source.r * source.a + destination.r * destination.a * (1.0 - source.a)) / alpha,
		(source.g * source.a + destination.g * destination.a * (1.0 - source.a)) / alpha,
		(source.b * source.a + destination.b * destination.a * (1.0 - source.a)) / alpha,
		alpha
	)
