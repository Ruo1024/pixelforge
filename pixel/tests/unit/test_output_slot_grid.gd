extends "res://addons/gut/test.gd"

const GridScript := preload("res://ui/canvas/output_slot_grid.gd")


func test_internal_scroll_and_hit_mapping() -> void:
	var grid := await _grid(_slots(50), 600, 424)
	assert_gt(grid.max_scroll_offset(), 0.0)
	grid.set_scroll_offset(grid.max_scroll_offset())
	assert_eq(grid.visible_slot_ids()[-1], "slot-49")
	var rect: Rect2 = grid.slot_rect(49)
	assert_eq(grid.slot_id_at(rect.get_center()), "slot-49")


func test_refill_does_not_reset_scroll() -> void:
	var slots := _slots(13)
	var grid := await _grid(slots, 600, 424)
	grid.set_scroll_offset(100.0)
	slots[9]["status"] = "succeeded"
	slots[9]["asset_id"] = "asset-9"
	grid.update_slots(slots)
	assert_eq(grid.scroll_offset, 100.0)
	assert_eq(grid.slot_ids()[9], "slot-9")


func test_wheel_boundary_and_zoom_modifier_priority() -> void:
	var grid := await _grid(_slots(50), 600, 424)
	assert_false(grid.handle_wheel(-1, true))
	assert_true(grid.handle_wheel(-1, false))
	grid.set_scroll_offset(grid.max_scroll_offset())
	assert_false(grid.handle_wheel(-1, false))
	assert_true(grid.handle_wheel(1, false))


func test_out_of_order_results_keep_slot_order() -> void:
	var slots := _slots(5)
	var grid := await _grid(slots, 600, 280)
	for index in [4, 1, 3]:
		slots[index]["status"] = "succeeded"
		slots[index]["asset_id"] = "asset-%d" % index
		grid.update_slots(slots)
	assert_eq(grid.slot_ids(), ["slot-0", "slot-1", "slot-2", "slot-3", "slot-4"])


func _grid(slots: Array, width: int, height: int) -> Control:
	var grid: Control = GridScript.new()
	grid.size = Vector2(width, height)
	add_child_autofree(grid)
	grid.configure(slots)
	await wait_process_frames(1)
	return grid


func _slots(count: int) -> Array:
	var result := []
	for index in range(count):
		result.append(
			{
				"slot_id": "slot-%d" % index,
				"status": "queued",
				"asset_id": null,
				"detached": false,
				"planned_size": [32, 32],
			}
		)
	return result
