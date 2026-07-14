extends "res://addons/gut/test.gd"

const ToolbarScript := preload("res://ui/canvas/output_selection_toolbar.gd")


func before_each() -> void:
	LocalizationService.set_language("en")


func test_selection_and_pointer_cancel() -> void:
	var toolbar := await _toolbar()
	toolbar.select_slot(_slot("succeeded"))
	assert_eq(toolbar.selected_slot_id, "slot-1")
	toolbar.pointer_cancel()
	assert_eq(toolbar.selected_slot_id, "")
	assert_false(toolbar.visible)


func test_exact_order_only_succeeded() -> void:
	var toolbar := await _toolbar()
	toolbar.select_slot(_slot("succeeded"))
	assert_eq(toolbar.action_ids(), ["preview", "edit", "detach", "download"])
	toolbar.select_slot(_slot("failed"))
	assert_false(toolbar.visible)
	toolbar.select_slot(_slot("succeeded"), true)
	assert_true(toolbar.get_node("Detach").disabled)
	assert_true(toolbar.get_node("Edit").disabled)


func _toolbar() -> Control:
	var toolbar: Control = ToolbarScript.new()
	add_child_autofree(toolbar)
	await wait_process_frames(1)
	return toolbar


func _slot(status: String) -> Dictionary:
	return {"slot_id": "slot-1", "status": status, "asset_id": "asset-1", "detached": false}
