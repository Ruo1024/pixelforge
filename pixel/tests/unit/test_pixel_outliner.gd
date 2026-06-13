extends "res://addons/gut/test.gd"

const Outliner := preload("res://core/pixel/outliner.gd")


func test_outer_outline_roundtrip_preserves_original_alpha_mask() -> void:
	var source := _make_disk_sprite()
	var outlined: Image = Outliner.add_outline(
		source,
		{"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_SQUARE}
	)
	assert_eq(outlined.get_size(), source.get_size() + Vector2i(2, 2))
	assert_eq(outlined.get_pixel(4, 1).to_html(false), Color.BLACK.to_html(false))

	var removed: Image = Outliner.remove_outline(
		outlined, {"color": Color.BLACK, "corner": Outliner.CORNER_SQUARE}
	)
	assert_eq(removed.get_size(), source.get_size())
	assert_gt(_alpha_iou(source, removed), 0.95)


func test_selective_outer_outline_respects_lower_half_mask() -> void:
	var source := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	source.fill(Color.RED)
	var mask := PackedByteArray()
	mask.resize(4 * 4)
	mask.fill(0)
	for y in range(2, 4):
		for x in range(4):
			mask[y * 4 + x] = 1

	var outlined: Image = (
		Outliner
		. add_outline(
			source,
			{
				"type": Outliner.TYPE_OUTER,
				"color": Color.BLACK,
				"corner": Outliner.CORNER_CROSS,
				"mask": mask,
			}
		)
	)
	assert_eq(outlined.get_pixel(2, 0).a, 0.0)
	assert_eq(outlined.get_pixel(2, 5).to_html(false), Color.BLACK.to_html(false))


func _make_disk_sprite() -> Image:
	var image := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(4, 4)
	for y in range(9):
		for x in range(9):
			if Vector2(x, y).distance_to(center) <= 3.2:
				image.set_pixel(x, y, Color.RED)
	return image


func _alpha_iou(left: Image, right: Image) -> float:
	var intersection := 0
	var union := 0
	for y in range(left.get_height()):
		for x in range(left.get_width()):
			var a := left.get_pixel(x, y).a > 0.004
			var b := right.get_pixel(x, y).a > 0.004
			if a and b:
				intersection += 1
			if a or b:
				union += 1
	if union == 0:
		return 1.0
	return float(intersection) / float(union)
