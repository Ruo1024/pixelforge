extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


func test_middle_button_pan_moves_then_stops_on_release() -> void:
	var canvas := await _make_canvas()
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE))
	canvas._gui_input(_motion(Vector2(18, -7), MOUSE_BUTTON_MASK_MIDDLE))
	assert_ne(canvas.camera_center, Vector2.ZERO)
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_MIDDLE, false, 0))
	var stopped_at: Vector2 = canvas.camera_center
	canvas._gui_input(_motion(Vector2(9, 4), 0))
	assert_eq(canvas.camera_center, stopped_at)


func test_space_left_pan_stops_when_left_releases_first() -> void:
	var canvas := await _make_canvas()
	canvas._gui_input(_space_key(true))
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT))
	canvas._gui_input(_motion(Vector2(12, 0), MOUSE_BUTTON_MASK_LEFT))
	assert_true(canvas._is_panning)
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, false, 0))
	assert_false(canvas._is_panning)


func test_space_left_pan_stops_when_space_releases_before_left() -> void:
	var canvas := await _make_canvas()
	canvas._gui_input(_space_key(true))
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT))
	canvas._gui_input(_space_key(false))
	assert_true(canvas._is_panning)
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, false, 0))
	assert_false(canvas._is_panning)


func test_zero_button_motion_self_heals_without_moving() -> void:
	var canvas := await _make_canvas()
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE))
	var before: Vector2 = canvas.camera_center
	canvas._gui_input(_motion(Vector2(40, 20), 0))
	assert_eq(canvas.camera_center, before)
	assert_false(canvas._is_panning)


func test_focus_loss_cancels_left_and_middle_pan() -> void:
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		var canvas := await _make_canvas()
		if button == MOUSE_BUTTON_LEFT:
			canvas._gui_input(_space_key(true))
		canvas._gui_input(_mouse_button(button, true, _button_mask(button)))
		assert_true(canvas._is_panning)
		canvas._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		assert_false(canvas._is_panning)


func test_modal_boundary_cancels_pan() -> void:
	var canvas := await _make_canvas()
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_MIDDLE, true, MOUSE_BUTTON_MASK_MIDDLE))
	assert_true(canvas._is_panning)
	canvas.call("cancel_pointer_gestures")
	assert_false(canvas._is_panning)


func test_text_focus_prevents_space_left_pan() -> void:
	var canvas := await _make_canvas()
	var edit := LineEdit.new()
	canvas.add_child(edit)
	edit.grab_focus()
	await wait_process_frames(1)
	canvas._gui_input(_space_key(true))
	canvas._gui_input(_mouse_button(MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT))
	assert_false(canvas._is_panning)


func _make_canvas() -> Control:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(640, 480)
	add_child_autofree(canvas)
	await wait_process_frames(1)
	return canvas


func _mouse_button(button: int, pressed: bool, mask: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.button_mask = mask
	event.position = Vector2(200, 160)
	return event


func _motion(relative: Vector2, mask: int) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.position = Vector2(220, 170)
	event.button_mask = mask
	return event


func _space_key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = pressed
	return event


func _button_mask(button: int) -> int:
	return MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_MIDDLE
