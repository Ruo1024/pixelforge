extends "res://addons/gut/test.gd"

const Drawing := preload("res://core/editor/pixel_drawing.gd")


func test_bresenham_and_pixel_perfect_golden_paths() -> void:
	assert_eq(
		Drawing.bresenham(Vector2i(0, 0), Vector2i(4, 2)),
		[Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 2), Vector2i(4, 2)]
	)
	assert_eq(
		Drawing.pixel_perfect([Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]),
		[Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1)]
	)


func test_fast_120hz_circle_strokes_are_connected() -> void:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var previous := Vector2i(48, 32)
	for step in range(120):
		var angle := TAU * float(step) / 120.0
		var point := Vector2i((Vector2(32, 32) + Vector2(cos(angle), sin(angle)) * 16.0).round())
		Drawing.stroke(image, previous, point, Color.WHITE)
		previous = point
	var visited := {}
	var queue: Array[Vector2i] = [Vector2i(48, 32)]
	while not queue.is_empty():
		var point: Vector2i = queue.pop_front()
		if visited.has(point) or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(point):
			continue
		if image.get_pixelv(point).a <= 0.0:
			continue
		visited[point] = true
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
			queue.append(point + offset)
	var opaque := 0
	for y in range(64):
		for x in range(64):
			opaque += 1 if image.get_pixel(x, y).a > 0.0 else 0
	assert_eq(visited.size(), opaque)


func test_palette_constraint_survives_one_thousand_random_operations() -> void:
	var palette: Array[Color] = [Color.BLACK, Color.WHITE, Color.RED, Color.BLUE]
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var random := RandomNumberGenerator.new()
	random.seed = 6001
	for _step in range(1000):
		var raw := Color(random.randf(), random.randf(), random.randf(), 1.0)
		var constrained := Drawing.nearest_palette_color(raw, palette)
		var start := Vector2i(random.randi_range(0, 31), random.randi_range(0, 31))
		var finish := Vector2i(random.randi_range(0, 31), random.randi_range(0, 31))
		Drawing.stroke(image, start, finish, constrained)
	for y in range(32):
		for x in range(32):
			var color := image.get_pixel(x, y)
			assert_true(color.a <= 0.0 or palette.has(color))


func test_global_fill_replaces_only_the_target_color() -> void:
	var image := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.set_pixel(3, 1, Color.BLUE)
	Drawing.flood_fill(image, Vector2i.ZERO, Color.GREEN, true)
	assert_eq(image.get_pixel(0, 0), Color.GREEN)
	assert_eq(image.get_pixel(3, 1), Color.BLUE)
