extends "res://addons/gut/test.gd"

const AdapterScript := preload("res://services/cleanup_operation_adapter.gd")
const ManualSchedulerScript := preload("res://tests/fixtures/providers/manual_deadline_scheduler.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")


func before_each() -> void:
	AssetLibrary.clear()
	TaskQueue.clear()
	TaskQueue.set_max_concurrency(1)


func test_real_pipeline_uses_frozen_palette_and_returns_contract_report() -> void:
	var image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.RED)
	image.set_pixel(1, 0, Color.BLUE)
	AssetLibrary.register_image(image, "source", {"id": "source"})
	var snapshot := _snapshot()
	snapshot["palette_snapshot"] = {
		"palette_id": "frozen",
		"content_sha256": "0".repeat(64),
		"colors_rgba8": ["#000000FF", "#FFFFFFFF"],
	}
	snapshot["settings"]["quantize"]["palette_id"] = "frozen"
	var adapter: Variant = AdapterScript.new(TaskQueue, AssetLibrary)
	var task: PFTask = adapter.submit({"request_id": "request", "input_snapshot": snapshot})
	var results := []
	task.finished.connect(func(value: Variant) -> void: results.append(value))
	assert_true(await _wait_until(func() -> bool: return TaskQueue.is_idle()))
	assert_eq(results.size(), 1)
	assert_true(results[0]["image"] is Image)
	assert_eq(results[0]["report"]["effective_target_size"], [0, 0])
	assert_true(results[0]["report"]["steps"] is Dictionary)
	assert_true(results[0]["report"].has("input_color_count"))
	assert_true(results[0]["report"].has("output_color_count"))


func test_cancel_is_deduped_and_resolves_only_after_worker_canceled_terminal() -> void:
	var scheduler := ManualSchedulerScript.new()
	var adapter: Variant = AdapterScript.new(TaskQueue, AssetLibrary, scheduler)
	var task := PFTask.new("cleanup", {}, func(_task: Variant) -> Variant:
		OS.delay_msec(80)
		return {})
	adapter.track("request", task)
	TaskQueue.submit(task)
	assert_true(await _wait_until(func() -> bool: return TaskQueue.get_running_count() == 1))
	var events := []
	task.canceled.connect(func() -> void: events.append("operation"))
	var first: PFCancelTaskV2 = adapter.cancel("request")
	var second: PFCancelTaskV2 = adapter.cancel("request")
	assert_same(first, second)
	first.resolved.connect(func(_result: Dictionary) -> void: events.append("wrapper"))
	assert_false(first.is_terminal())
	assert_true(await _wait_until(func() -> bool: return TaskQueue.is_idle()))
	assert_eq(events, ["operation", "wrapper"])


func _snapshot() -> Dictionary:
	var settings: Dictionary = CleanupNodeScript.DEFAULT_SETTINGS.duplicate(true)
	settings["detect_grid"]["enabled"] = true
	settings["detect_grid"]["mode"] = "manual"
	settings["detect_grid"]["scale"] = 1.0
	settings["resample"]["scale"] = 1.0
	settings["resample"]["enabled"] = false
	settings["quantize"]["mode"] = "fixed_palette"
	return {
		"kind": "cleanup", "graph_id": "graph", "source_node_id": "cleanup",
		"input_source_kind": "image_input", "input_source_node_id": "input",
		"source_batch_node_id": "", "source_slot_id": "", "source_asset_id": "source",
		"effective_target_size": [0, 0], "preset_id": "", "settings": settings,
		"palette_snapshot": null,
	}


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
