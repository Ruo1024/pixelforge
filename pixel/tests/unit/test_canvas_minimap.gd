extends GutTest

const CanvasMinimap := preload("res://ui/canvas/canvas_minimap.gd")


func test_world_and_map_coordinates_round_trip_with_negative_origin() -> void:
	var world_bounds := Rect2(Vector2(-500, -250), Vector2(1000, 500))
	var map_rect := Rect2(Vector2(8, 12), Vector2(200, 100))
	var world_point := Vector2(125, -75)

	var mapped: Vector2 = CanvasMinimap.world_to_map(world_point, world_bounds, map_rect)
	var restored: Vector2 = CanvasMinimap.map_to_world(mapped, world_bounds, map_rect)

	assert_almost_eq(mapped.x, 133.0, 0.001)
	assert_almost_eq(mapped.y, 47.0, 0.001)
	assert_almost_eq(restored.x, world_point.x, 0.001)
	assert_almost_eq(restored.y, world_point.y, 0.001)


func test_map_to_world_clamps_navigation_to_content_bounds() -> void:
	var bounds := Rect2(Vector2(100, 200), Vector2(400, 200))
	var map_rect := Rect2(Vector2(10, 10), Vector2(100, 50))

	assert_eq(CanvasMinimap.map_to_world(Vector2(-40, 200), bounds, map_rect), Vector2(100, 400))


func test_viewport_rect_mapping_preserves_relative_position_and_size() -> void:
	var world_bounds := Rect2(Vector2(-100, -100), Vector2(1000, 500))
	var viewport := Rect2(Vector2(100, 0), Vector2(400, 200))
	var map_rect := Rect2(Vector2.ZERO, Vector2(200, 100))

	var mapped: Rect2 = CanvasMinimap.world_rect_to_map(viewport, world_bounds, map_rect)

	assert_eq(mapped, Rect2(Vector2(40, 20), Vector2(80, 40)))


func test_item_world_rect_reads_frame_and_explicit_exported_bounds() -> void:
	var frame := {"type": "frame", "position": [-40, 20], "size": [320, 240]}
	var card := {
		"type": "node",
		"position": [0, 0],
		"bounds": {"position": [12, 16], "size": [260, 330]},
	}

	assert_eq(CanvasMinimap.item_world_rect(frame), Rect2(Vector2(-40, 20), Vector2(320, 240)))
	assert_eq(CanvasMinimap.item_world_rect(card), Rect2(Vector2(12, 16), Vector2(260, 330)))


func test_control_snapshot_exposes_viewport_rect_and_click_drag_targets() -> void:
	var minimap := CanvasMinimap.new()
	add_child_autofree(minimap)
	minimap.size = Vector2(216, 116)
	(
		minimap
		. set_canvas_snapshot(
			[
				{"type": "frame", "position": [0, 0], "size": [1000, 500]},
				{"type": "node", "position": [100, 100]},
			],
			Rect2(Vector2.ZERO, Vector2(1000, 500)),
			Rect2(Vector2(250, 125), Vector2(500, 250))
		)
	)
	var requested: Array[Vector2] = []
	minimap.world_center_requested.connect(func(center: Vector2) -> void: requested.append(center))

	assert_eq(minimap.get_map_rect(), Rect2(Vector2(8, 8), Vector2(200, 100)))
	assert_eq(minimap.get_viewport_map_rect(), Rect2(Vector2(58, 33), Vector2(100, 50)))

	minimap._gui_input(_mouse_button(true, Vector2(108, 58)))
	minimap._gui_input(_mouse_motion(Vector2(208, 108)))
	minimap._gui_input(_mouse_button(false, Vector2(208, 108)))

	assert_eq(requested, [Vector2(500, 250), Vector2(1000, 500)])


func _mouse_button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func _mouse_motion(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event
