extends "res://addons/gut/test.gd"

const ControllerScript := preload("res://ui/canvas/output_card_controller.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_state_tiles_and_empty_reason() -> void:
	var controller := await _controller(_output(_mixed_slots()))
	assert_eq(controller.get_node("SlotGrid").slot_ids(), ["q", "r", "s", "f", "c"])
	assert_eq(controller.tile_states(), ["queued", "running", "succeeded", "failed", "canceled"])
	controller.configure(_output([]))
	assert_eq(controller.empty_reason(), "not_run")


func test_busy_action_gate_and_terminal_actions() -> void:
	var controller := await _controller(_output(_mixed_slots(), "Running"))
	assert_true(controller.is_action_allowed("preview", "s"))
	assert_true(controller.is_action_allowed("download", "s"))
	assert_false(controller.is_action_allowed("detach", "s"))
	assert_false(controller.is_action_allowed("edit", "s"))
	controller.configure(_output(_mixed_slots(), "Partial"))
	assert_true(controller.is_action_allowed("detach", "s"))


func test_top_rail_exact_order_and_history() -> void:
	var controller := await _controller(_output(_mixed_slots(), "Partial", "history"))
	assert_eq(
		controller.top_rail_ids(), ["title", "count", "state", "download", "detach_all", "port"]
	)
	assert_string_contains(controller.get_node("TopRail/State").text, "History")
	assert_string_contains(controller.get_node("TopRail/State").text, "Partial")


func test_retry_visibility_all_preconditions() -> void:
	var valid := {
		"role": "current",
		"source_node_id": "generate",
		"source_exists": true,
		"source_type_matches": true,
		"snapshot_valid": true,
		"wait_seconds": 0,
		"error": {"retryable": true},
	}
	assert_true(ControllerScript.retry_visible(valid))
	for key in ["source_exists", "source_type_matches", "snapshot_valid"]:
		var invalid := valid.duplicate(true)
		invalid[key] = false
		assert_false(ControllerScript.retry_visible(invalid), key)
	var standalone := valid.duplicate(true)
	standalone["source_node_id"] = ""
	assert_false(ControllerScript.retry_visible(standalone))


func _controller(output: Dictionary) -> Node:
	var controller: Node = ControllerScript.new()
	controller.size = Vector2(600, 488)
	add_child_autofree(controller)
	controller.configure(output)
	await wait_process_frames(1)
	return controller


func _output(slots: Array, state: String = "Ready", role: String = "current") -> Dictionary:
	return {
		"title": "Results",
		"state": state,
		"role": role,
		"source_node_id": "generate",
		"result_slots": slots,
	}


func _mixed_slots() -> Array:
	return [
		{"slot_id": "q", "status": "queued", "asset_id": null, "detached": false},
		{"slot_id": "r", "status": "running", "asset_id": null, "detached": false},
		{"slot_id": "s", "status": "succeeded", "asset_id": "asset-s", "detached": false},
		{"slot_id": "f", "status": "failed", "asset_id": null, "detached": false},
		{"slot_id": "c", "status": "canceled", "asset_id": null, "detached": false},
	]
