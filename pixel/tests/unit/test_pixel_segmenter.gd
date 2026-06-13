extends "res://addons/gut/test.gd"

const Segmenter := preload("res://core/pixel/segmenter.gd")


func test_segments_six_known_components_and_filters_noise() -> void:
	var image := Image.create(32, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var rects := [
		Rect2i(1, 1, 3, 3),
		Rect2i(8, 1, 4, 2),
		Rect2i(16, 1, 3, 4),
		Rect2i(20, 9, 4, 4),
		Rect2i(1, 10, 5, 3),
		Rect2i(10, 11, 3, 3),
	]
	for rect in rects:
		_fill_rect(image, rect, Color.RED)
	image.set_pixel(30, 18, Color.RED)
	image.set_pixel(31, 18, Color.RED)

	var segments: Array = Segmenter.segment(image, {"merge_distance": 0, "min_area": 4})
	assert_eq(segments.size(), 6)
	for i in range(rects.size()):
		var expected: Rect2i = rects[i]
		assert_eq(segments[i]["rect"], expected)
		var sub: Image = segments[i]["image"]
		assert_eq(sub.get_size(), expected.size)


func test_merge_distance_combines_nearby_floating_part() -> void:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_fill_rect(image, Rect2i(3, 2, 4, 4), Color.RED)
	_fill_rect(image, Rect2i(3, 7, 4, 2), Color.ORANGE)

	var separated: Array = Segmenter.segment(image, {"merge_distance": 0, "min_area": 4})
	assert_eq(separated.size(), 2)

	var merged: Array = Segmenter.segment(image, {"merge_distance": 2, "min_area": 4})
	assert_eq(merged.size(), 1)
	assert_eq(merged[0]["rect"], Rect2i(3, 2, 4, 7))


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			image.set_pixel(x, y, color)
