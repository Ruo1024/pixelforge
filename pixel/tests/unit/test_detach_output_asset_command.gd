extends "res://addons/gut/test.gd"

const CommandScript := preload("res://ui/canvas/detach_output_asset_command.gd")


func test_single_all_restore_and_locate() -> void:
	var slots := _slots(3)
	var single: Dictionary = CommandScript.detach_single(
		slots, "slot-1", _origin(), Vector2(900, 200)
	)
	assert_true(single["ok"])
	assert_true(single["slots"][1]["detached"])
	assert_eq(single["sprites"][0]["asset_id"], "asset-1")
	assert_eq(single["sprites"][0]["origin_slot_id"], "slot-1")
	var all: Dictionary = CommandScript.detach_all(slots, _origin(), Vector2(900, 200), true)
	assert_eq(all["sprites"].size(), 3)
	assert_eq(all["sprites"][1]["position"], [1100, 200])
	var restored: Array = CommandScript.restore_all_detached(all["slots"])
	assert_true(restored.all(func(slot: Dictionary) -> bool: return not slot["detached"]))
	assert_eq(CommandScript.empty_action(all["slots"], ["slot-0"]), "locate")
	assert_eq(CommandScript.empty_action(all["slots"], []), "restore")


func test_drag_threshold_identity_and_cancel_paths() -> void:
	assert_false(CommandScript.crossed_drag_threshold(Vector2.ZERO, Vector2(7.99, 0)))
	assert_true(CommandScript.crossed_drag_threshold(Vector2.ZERO, Vector2(8.01, 0)))
	var slots := _slots(1)
	var canceled: Dictionary = CommandScript.cancel_preview(slots)
	assert_eq(canceled["slots"], slots)
	assert_true(canceled["sprites"].is_empty())


func test_all_layout_confirmation_and_last_slot() -> void:
	var thirteen := _slots(13)
	assert_true(
		CommandScript.detach_all(thirteen, _origin(), Vector2.ZERO, false)["confirmation_required"]
	)
	var one: Dictionary = CommandScript.detach_all(_slots(1), _origin(), Vector2.ZERO, true)
	assert_true(one["slots"][0]["detached"])
	assert_eq(one["sprites"].size(), 1)


func _slots(count: int) -> Array:
	var slots := []
	for index in range(count):
		(
			slots
			. append(
				{
					"slot_id": "slot-%d" % index,
					"status": "succeeded",
					"asset_id": "asset-%d" % index,
					"detached": false,
				}
			)
		)
	return slots


func _origin() -> Dictionary:
	return {"origin_graph_id": "graph", "origin_batch_node_id": "output"}
