extends "res://addons/gut/test.gd"

const EditDoc := preload("res://core/editor/pf_edit_doc.gd")
const History := preload("res://core/editor/edit_history.gd")


func test_frame_layer_flatten_and_isolated_history_are_exact() -> void:
	var base := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	base.fill(Color.RED)
	var document := EditDoc.from_asset(base, "source")
	var overlay := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	overlay.fill(Color(0, 0, 1, 0.5))
	document.add_layer("Overlay", overlay)
	var flat := document.flatten(0)
	assert_almost_eq(flat.get_pixel(0, 0).r, 0.5, 0.01)
	assert_almost_eq(flat.get_pixel(0, 0).b, 0.5, 0.01)

	var history := History.new()
	history.capture(document)
	document.get_frame(1, 0).fill(Color.GREEN)
	assert_true(history.undo(document))
	assert_almost_eq(document.get_frame(1, 0).get_pixel(0, 0).b, 1.0, 0.01)
	assert_true(history.redo(document))
	assert_almost_eq(document.get_frame(1, 0).get_pixel(0, 0).g, 1.0, 0.01)


func test_32_layer_by_64_frame_matrix_has_explicit_limit_budget() -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var document := EditDoc.from_asset(image, "matrix")
	for index in range(31):
		document.add_layer("Layer %d" % index)
	for index in range(63):
		document.add_frame(index)
	var started := Time.get_ticks_msec()
	var flat := document.flatten(63)
	var elapsed := Time.get_ticks_msec() - started
	assert_eq(document.layers.size(), 32)
	assert_eq(document.frame_count(), 64)
	assert_eq(flat.get_size(), Vector2i(8, 8))
	assert_lt(elapsed, 500)
