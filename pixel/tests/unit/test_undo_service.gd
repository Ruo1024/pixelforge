extends "res://addons/gut/test.gd"


class Counter:
	var value := 0


func before_each() -> void:
	var undo := get_tree().root.get_node("UndoService")
	undo.clear()
	undo.reset_limits()


func test_undo_redo_50_lightweight_actions() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var counter := Counter.new()

	for _index in range(50):
		undo.perform_action(
			"increment", func() -> void: counter.value += 1, func() -> void: counter.value -= 1, 4
		)

	assert_eq(counter.value, 50)
	assert_eq(undo.get_undo_count(), 50)

	for _index in range(50):
		assert_true(undo.undo())
	assert_eq(counter.value, 0)

	for _index in range(50):
		assert_true(undo.redo())
	assert_eq(counter.value, 50)


func test_undo_memory_limit_drops_oldest_actions() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var counter := Counter.new()
	undo.configure_limits(100, 10)

	for _index in range(5):
		undo.perform_action(
			"costly increment",
			func() -> void: counter.value += 1,
			func() -> void: counter.value -= 1,
			4
		)

	assert_lte(undo.get_memory_bytes(), 10)
	assert_lte(undo.get_undo_count(), 2)
	undo.reset_limits()


func test_snapshot_region_returns_expected_pixels() -> void:
	var undo := get_tree().root.get_node("UndoService")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	image.set_pixel(2, 2, Color.WHITE)

	var snapshot: Image = undo.snapshot_region(image, Rect2i(2, 2, 1, 1))
	assert_eq(snapshot.get_size(), Vector2i.ONE)
	assert_eq(snapshot.get_pixel(0, 0), Color.WHITE)
