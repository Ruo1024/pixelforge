extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const ExportFlowScript := preload("res://ui/shell/export_flow_controller.gd")
const FileIOScript := preload("res://infra/file_io.gd")

const VALID_IMAGE_PATH := "user://tests/ar2_valid.png"
const INVALID_IMAGE_PATH := "user://tests/ar2_invalid.txt"
const EXPORT_PATH := "user://tests/ar2_export.png"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var image := _solid_image(Vector2i(32, 24), Color.CORNFLOWER_BLUE)
	assert_eq(image.save_png(VALID_IMAGE_PATH), OK)
	var invalid := FileAccess.open(INVALID_IMAGE_PATH, FileAccess.WRITE)
	invalid.store_string("not an image")
	invalid.close()


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("AR2 UI")
	get_tree().root.get_node("AssetLibrary").clear()
	for path in [EXPORT_PATH, EXPORT_PATH.get_basename() + ".json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_empty_canvas_hint_and_dialog_import_are_stable_and_atomic() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var import_flow: Node = main.get_node("M21UiController/ImportFlowController")
	var hint: Control = canvas.get_node("EmptyCanvasImportHint")
	assert_true(hint.visible)

	var asset_count_before: int = AssetLibrary.get_all_meta().size()
	var failed: Dictionary = import_flow.import_files_from_dialog(
		PackedStringArray([VALID_IMAGE_PATH, INVALID_IMAGE_PATH])
	)
	assert_true(bool(failed["ok"]))
	assert_eq(failed["failed_files"], [INVALID_IMAGE_PATH])
	assert_eq(AssetLibrary.get_all_meta().size(), asset_count_before + 1)
	assert_eq(canvas.get_item_count(), 1)
	assert_eq(canvas.export_canvas_data()["items"][0]["type"], "node")
	assert_true(UndoService.undo())
	assert_eq(canvas.get_item_count(), 0)
	assert_true(ProjectService.current_project.graphs.is_empty())

	var expected_anchor: Vector2 = import_flow.stable_import_anchor()
	var imported: Dictionary = import_flow.import_files_from_dialog(
		PackedStringArray([VALID_IMAGE_PATH])
	)
	assert_true(bool(imported["ok"]))
	assert_true(bool(imported["auto_focused"]))
	assert_eq(Vector2(imported["anchor"]), expected_anchor)
	assert_eq(canvas.get_item_count(), 1)
	assert_false(hint.visible)
	var item_data: Dictionary = canvas.export_canvas_data()["items"][0]
	assert_eq(item_data["position"], [int(expected_anchor.x), int(expected_anchor.y)])


func test_existing_workspace_import_stays_in_view_without_forced_focus() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var import_flow: Node = main.get_node("M21UiController/ImportFlowController")
	var first: Dictionary = import_flow.import_files_from_dialog(
		PackedStringArray([VALID_IMAGE_PATH])
	)
	assert_true(bool(first["ok"]))
	var zoom_after_first: float = canvas.camera_zoom

	var second: Dictionary = import_flow.import_files_from_dialog(
		PackedStringArray([VALID_IMAGE_PATH])
	)
	assert_true(bool(second["ok"]))
	assert_false(bool(second["auto_focused"]))
	assert_eq(canvas.camera_zoom, zoom_after_first)
	assert_string_contains(_status_label(main).text, "Focus Last Import")
	import_flow.focus_last_import()
	assert_eq(_status_label(main).text, "Focused the last import")


func test_multi_image_import_creates_reference_grid_as_one_undo_action() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var import_flow: Node = main.get_node("M21UiController/ImportFlowController")
	var anchor: Vector2 = import_flow.stable_import_anchor()
	var result: Dictionary = import_flow.import_files_from_dialog(
		PackedStringArray([VALID_IMAGE_PATH, VALID_IMAGE_PATH, VALID_IMAGE_PATH, VALID_IMAGE_PATH])
	)

	assert_true(result["ok"])
	assert_eq(canvas.get_item_count(), 4)
	var positions := []
	for item in canvas.export_canvas_data()["items"]:
		positions.append(Vector2(item["position"][0], item["position"][1]))
	assert_has(positions, anchor)
	assert_has(positions, anchor + Vector2(300, 0))
	assert_has(positions, anchor + Vector2(600, 0))
	assert_has(positions, anchor + Vector2(0, 370))
	assert_true(UndoService.undo())
	assert_eq(canvas.get_item_count(), 0)
	assert_true(ProjectService.current_project.graphs.is_empty())
	assert_true(UndoService.redo())
	assert_eq(canvas.get_item_count(), 4)


func test_1254_preview_reaches_running_and_done_instead_of_stale_queued() -> void:
	var main := await _make_main()
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	var image := _solid_image(Vector2i(1254, 1254), Color(0.2, 0.4, 0.7, 1.0))
	var asset_id: String = AssetLibrary.register_image(image, "large", {"origin": "imported"})
	canvas.add_sprite_item(image, asset_id, Vector2.ZERO)

	main.call("_request_cleanup_preview", {"steps": []})
	await wait_process_frames(1)
	assert_ne(_status_label(main).text, "Preview queued")
	var deadline := Time.get_ticks_msec() + 10000
	while not TaskQueue.is_idle() and Time.get_ticks_msec() < deadline:
		await wait_process_frames(1)
	assert_true(TaskQueue.is_idle())
	assert_eq(_status_label(main).text, "Cleanup preview ready")
	var source_data: Dictionary = canvas.export_canvas_data()["items"][0]
	(
		main
		. call(
			"_on_cleanup_finished",
			{
				"canceled": false,
				"items":
				[
					{
						"source_data": source_data,
						"image": _solid_image(Vector2i(16, 16), Color.BLUE),
						"report": {},
						"params": {},
					},
				],
			}
		)
	)
	await wait_seconds(0.4)
	assert_eq(_status_label(main).text, "Cleanup complete")

	main.call("_on_cleanup_preview_canceled", int(main.get("_preview_token")))
	assert_eq(_status_label(main).text, "Cleanup preview canceled")
	main.get("_m2_actions")._on_task_canceled()
	assert_eq(_status_label(main).text, "Processing canceled")


func test_export_overwrite_choices_and_result_summary() -> void:
	var main := await _make_main()
	var export_flow: Node = main.get_node("ExportFlowController")
	var first_image := _solid_image(Vector2i(3, 3), Color.RED)
	var first_snapshots := [{"data": {"asset_id": "red"}, "image": first_image}]
	export_flow.request_export(first_snapshots, "ar2_export.png")
	export_flow.choose_path(EXPORT_PATH)
	assert_true(FileAccess.file_exists(EXPORT_PATH))
	assert_string_contains(_status_label(main).text, ProjectSettings.globalize_path(EXPORT_PATH))
	assert_true(main.get_node("Root/BottomBar/OpenExportFolderButton").visible)
	var original_bytes := FileAccess.get_file_as_bytes(EXPORT_PATH)

	var blue_snapshots := [
		{"data": {"asset_id": "blue"}, "image": _solid_image(Vector2i(3, 3), Color.BLUE)}
	]
	export_flow.request_export(blue_snapshots, "ar2_export.png")
	export_flow.choose_path(EXPORT_PATH)
	var overwrite_dialog: ConfirmationDialog = main.get_node("ExportOverwriteDialog")
	assert_true(overwrite_dialog.visible)
	export_flow.cancel_overwrite()
	assert_eq(FileAccess.get_file_as_bytes(EXPORT_PATH), original_bytes)
	assert_string_contains(_status_label(main).text, "not changed")

	export_flow.request_export(blue_snapshots, "ar2_export.png")
	export_flow.choose_path(EXPORT_PATH)
	export_flow.call("_perform_pending_export")
	assert_ne(FileAccess.get_file_as_bytes(EXPORT_PATH), original_bytes)


func test_export_failure_summary_names_created_and_missing_outputs() -> void:
	var summary := ExportFlowScript.format_failure_summary(
		["sheet.png", "sheet.json"], ["sheet.png"], ERR_CANT_CREATE
	)
	assert_string_contains(summary, "Created: sheet.png")
	assert_string_contains(summary, "Not created: sheet.json")
	assert_string_contains(summary, "retry")


func _make_main() -> Control:
	var main: Control = MainScript.new()
	add_child_autofree(main)
	await wait_process_frames(2)
	main.get_node("RecoveryDialog").hide()
	return main


func _status_label(main: Control) -> Label:
	return main.get_node("Root/BottomBar").get_child(0)


func _solid_image(size: Vector2i, color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image
