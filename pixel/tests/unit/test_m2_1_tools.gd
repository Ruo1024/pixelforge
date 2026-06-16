extends "res://addons/gut/test.gd"

const MagicWandToolScript := preload("res://ui/tools/magic_wand_tool.gd")
const RectangleToolScript := preload("res://ui/tools/rectangle_tool.gd")
const LassoToolScript := preload("res://ui/tools/lasso_tool.gd")


func test_magic_wand_tool_commits_pixel_selection() -> void:
	var tool := MagicWandToolScript.new()
	var image := _make_two_color_image()
	var emitted := []
	tool.selection_committed.connect(
		func(selection: PFSelection) -> void: emitted.append(selection)
	)
	tool.set_source_image(image)

	tool.on_mouse_press(Vector2i(0, 0), MOUSE_BUTTON_LEFT, 0)

	assert_eq(emitted.size(), 1)
	var selection: PFSelection = emitted[0]
	assert_eq(selection.get_selected_count(), 8)
	assert_eq(selection.get_bbox(), Rect2i(0, 0, 2, 4))


func test_rectangle_tool_drag_commits_rect_selection() -> void:
	var tool := RectangleToolScript.new()
	var emitted := []
	tool.selection_committed.connect(
		func(selection: PFSelection) -> void: emitted.append(selection)
	)
	tool.set_source_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))

	tool.on_mouse_press(Vector2i(1, 1), MOUSE_BUTTON_LEFT, 0)
	tool.on_mouse_move(Vector2i(3, 4))
	tool.on_mouse_release(Vector2i(3, 4), MOUSE_BUTTON_LEFT, 0)

	assert_eq(emitted.size(), 1)
	var selection: PFSelection = emitted[0]
	assert_eq(selection.get_bbox(), Rect2i(1, 1, 3, 4))
	assert_eq(selection.get_selected_count(), 12)


func test_lasso_tool_right_click_closes_polygon_selection() -> void:
	var tool := LassoToolScript.new()
	var emitted := []
	tool.selection_committed.connect(
		func(selection: PFSelection) -> void: emitted.append(selection)
	)
	tool.set_source_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))

	tool.on_mouse_press(Vector2i(1, 1), MOUSE_BUTTON_LEFT, 0)
	tool.on_mouse_press(Vector2i(6, 1), MOUSE_BUTTON_LEFT, 0)
	tool.on_mouse_press(Vector2i(1, 6), MOUSE_BUTTON_LEFT, 0)
	tool.on_mouse_press(Vector2i(1, 6), MOUSE_BUTTON_RIGHT, 0)

	assert_eq(emitted.size(), 1)
	var selection: PFSelection = emitted[0]
	assert_false(selection.is_empty())
	assert_eq(selection.get_bbox().position, Vector2i(1, 1))


func _make_two_color_image() -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for y in range(4):
		for x in range(4):
			image.set_pixel(x, y, Color.WHITE if x < 2 else Color.RED)
	return image
