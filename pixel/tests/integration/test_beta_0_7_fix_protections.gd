extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GridScript := preload("res://ui/canvas/output_slot_grid.gd")


func test_internal_scroll_owns_wheel_at_both_boundaries() -> void:
	var grid: Control = GridScript.new()
	grid.size = Vector2(600, 424)
	add_child_autofree(grid)
	grid.configure(_slots(50))
	await wait_process_frames(1)
	grid.set_scroll_offset(grid.max_scroll_offset())
	assert_true(grid.handle_wheel(-1, false))
	grid.set_scroll_offset(0.0)
	assert_true(grid.handle_wheel(1, false))


func test_generation_card_is_fixed_and_uses_only_presets_orientation_and_count() -> void:
	var source := _source("res://ui/canvas/generation_card_view.gd")
	for retired in ["BodyScroll", "TargetWidth", "TargetHeight", "RatioLock", "_cost_text"]:
		assert_false(source.contains(retired), retired)
	for required in ["ResolutionPreset", "Orientation", "BatchSize", "DeveloperPromptPreview"]:
		assert_true(source.contains(required), required)


func test_api_settings_and_developer_mode_are_top_bar_actions() -> void:
	var source := _source("res://ui/shell/main.gd")
	assert_true(source.contains("ApiSettingsButton"))
	assert_true(source.contains("DeveloperModeToggle"))


func test_prompt_editor_wraps_without_horizontal_scroll() -> void:
	var source := _source("res://ui/canvas/canvas_node_card.gd")
	assert_true(source.contains("TextEdit.LINE_WRAPPING_BOUNDARY"))
	assert_true(source.contains("scroll_horizontal = 0"))


func test_style_prompt_has_copy_edit_save_delete_flow() -> void:
	var source := _source("res://ui/canvas/prompt_preset_card_view.gd")
	for control_name in ["PresetOption", "PresetCopy", "PresetEdit", "PresetSave", "PresetDelete"]:
		assert_true(source.contains(control_name), control_name)


func test_reference_and_output_share_media_tile_grid_with_drag_reorder() -> void:
	assert_true(ResourceLoader.exists("res://ui/canvas/media_tile_grid.gd"))
	var reference_source := _source("res://ui/canvas/canvas_node_card.gd")
	var output_source := _source("res://ui/canvas/output_slot_grid.gd")
	assert_true(reference_source.contains("MediaTileGridScript"))
	assert_true(output_source.contains("MediaTileGridScript"))
	assert_true(reference_source.contains("reference_reorder_requested"))


func test_cleanup_card_is_compact_and_routes_settings_to_inspector() -> void:
	var source := _source("res://ui/canvas/cleanup_card_view.gd")
	assert_false(source.contains("BodyScroll"))
	assert_true(source.contains("SettingsButton"))
	assert_true(source.contains('action_requested.emit("open_settings")'))


func test_reference_passthrough_is_an_explicit_local_coordinator_path() -> void:
	var source := _source("res://services/generation_run_coordinator.gd")
	assert_true(source.contains("run_reference_passthrough"))
	assert_true(source.contains("local_passthrough"))


func test_clicked_card_uses_ephemeral_selected_item_layer() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(640, 480)
	add_child_autofree(canvas)
	await wait_process_frames(1)
	assert_not_null(canvas.get_node_or_null("ItemLayer/SelectedItemLayer"))


func test_cost_product_path_is_absent_but_hidden_provider_audit_is_preserved() -> void:
	var combined := (
		_source("res://ui/canvas/generation_card_view.gd")
		+ _source("res://ui/shell/main.gd")
		+ _source("res://ui/dialogs/provider_settings_dialog.gd")
		+ _source("res://services/provider_service.gd")
		+ _source("res://core/provider/pf_provider.gd")
	)
	assert_false(combined.contains("CostService"))
	assert_false(combined.contains("estimate_cost"))
	assert_false(combined.contains("MonthlyBudget"))
	assert_false(FileAccess.file_exists("res://services/cost_service.gd"))
	var coordinator := _source("res://services/generation_run_coordinator.gd")
	assert_true(coordinator.contains('record["actual_cost_usd"]'))
	assert_true(coordinator.contains('record["charge_id"]'))


func _source(path: String) -> String:
	assert_true(FileAccess.file_exists(path), path)
	return FileAccess.get_file_as_string(path)


func _slots(count: int) -> Array:
	var result := []
	for index in range(count):
		(
			result
			. append(
				{
					"slot_id": "slot-%d" % index,
					"status": "queued",
					"detached": false,
					"planned_size": [32, 32],
				}
			)
		)
	return result
