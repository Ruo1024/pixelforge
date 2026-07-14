class_name PFCleanupOperationAdapter
extends RefCounted

## Runs one frozen cleanup snapshot at a time through TaskQueue. Cancellation only
## settles after TaskQueue proves that the worker reached its canceled terminal.

const TaskScript := preload("res://services/pf_task.gd")
const CancelTaskScript := preload("res://services/pf_cancel_task_v2.gd")
const DeadlineSchedulerScript := preload("res://infra/cancel_deadline_scheduler.gd")
const PipelineScript := preload("res://core/pixel/pipeline.gd")
const QuantizerScript := preload("res://core/pixel/quantizer.gd")
const TIMEOUT_MS := 5000

var _queue: Variant
var _asset_library: Variant
var _scheduler: Variant
var _operations := {}


func _init(queue: Variant = null, asset_library: Variant = null, scheduler: Variant = null) -> void:
	_queue = queue if queue != null else TaskQueue
	_asset_library = asset_library if asset_library != null else AssetLibrary
	_scheduler = scheduler if scheduler != null else DeadlineSchedulerScript.new()


func submit(operation: Dictionary) -> PFTask:
	var request_id := String(operation.get("request_id", ""))
	var snapshot: Dictionary = operation.get("input_snapshot", {}).duplicate(true)
	var source: Image = _asset_library.get_image(String(snapshot.get("source_asset_id", "")))
	var task := TaskScript.new(
		"pixel_cleanup", {"request_id": request_id}, _execute.bind(source, snapshot)
	)
	track(request_id, task)
	_queue.submit(task)
	return task


func track(request_id: String, task: PFTask) -> void:
	_operations[request_id] = {"task": task, "wrapper": null, "terminal": false}
	task.canceled.connect(_on_operation_canceled.bind(request_id), CONNECT_ONE_SHOT)
	task.finished.connect(_on_operation_finished.bind(request_id), CONNECT_ONE_SHOT)
	task.failed.connect(_on_operation_failed.bind(request_id), CONNECT_ONE_SHOT)


func cancel(request_id: String) -> PFCancelTaskV2:
	if not _operations.has(request_id):
		var missing := CancelTaskScript.new(request_id, "")
		missing.reject(_cancel_error(request_id))
		return missing
	var state: Dictionary = _operations[request_id]
	if state.get("wrapper") is PFCancelTaskV2:
		return state["wrapper"]
	var wrapper: PFCancelTaskV2 = CancelTaskScript.new(request_id, "")
	state["wrapper"] = wrapper
	_operations[request_id] = state
	_scheduler.schedule_ms(TIMEOUT_MS, _on_cancel_timeout.bind(request_id))
	_queue.cancel((state["task"] as PFTask).id)
	return wrapper


func _execute(_task: PFTask, source: Image, snapshot: Dictionary) -> Dictionary:
	if source == null:
		return {"error": _cleanup_error(String(snapshot.get("request_id", "")))}
	var started := Time.get_ticks_msec()
	var input_color_count := QuantizerScript.count_colors(source)
	var pipeline_result := PipelineScript.apply(source, _pipeline_params(snapshot))
	var output: Image = pipeline_result.get("image")
	var raw_report: Dictionary = pipeline_result.get("report", {})
	var settings: Dictionary = snapshot.get("settings", {})
	var detect: Dictionary = raw_report.get("detect_grid", raw_report.get("detect", {}))
	var scale_x := float(detect.get("scale_x", detect.get("scale", 0.0)))
	var scale_y := float(detect.get("scale_y", detect.get("scale", 0.0)))
	var offset: Variant = detect.get("offset", Vector2.ZERO)
	var offset_array := [float(offset.x), float(offset.y)] if offset is Vector2 else Array(offset).duplicate()
	var report := {
		"input_size": [source.get_width(), source.get_height()],
		"output_size": [output.get_width(), output.get_height()],
		"effective_target_size": Array(snapshot.get("effective_target_size", [0, 0])).duplicate(),
		"detected_grid": {"cell_size": [scale_x, scale_y], "offset": offset_array},
		"steps": {
			"detect_grid": bool(Dictionary(settings.get("detect_grid", {})).get("enabled", false)),
			"resample": bool(Dictionary(settings.get("resample", {})).get("enabled", false)),
			"quantize": bool(Dictionary(settings.get("quantize", {})).get("enabled", false)),
		},
		"input_color_count": input_color_count,
		"output_color_count": QuantizerScript.count_colors(output),
		"elapsed_ms": maxi(0, Time.get_ticks_msec() - started),
	}
	return {"image": output, "report": report}


func _pipeline_params(snapshot: Dictionary) -> Dictionary:
	var settings: Dictionary = Dictionary(snapshot.get("settings", {})).duplicate(true)
	for group in ["detect_grid", "resample"]:
		var values: Dictionary = settings.get(group, {})
		var offset: Variant = values.get("offset", [0.0, 0.0])
		if offset is Array and offset.size() == 2:
			values["offset"] = Vector2(float(offset[0]), float(offset[1]))
	var target: Variant = snapshot.get("effective_target_size", [0, 0])
	if bool(Dictionary(settings.get("resample", {})).get("enabled", false)) and _positive_pair(target):
		settings["resample"]["target_size"] = Vector2i(int(target[0]), int(target[1]))
	var palette: Variant = snapshot.get("palette_snapshot")
	if palette is Dictionary:
		settings["quantize"]["palette_colors"] = Array(palette.get("colors_rgba8", [])).duplicate()
	return settings


func _on_operation_canceled(request_id: String) -> void:
	if not _operations.has(request_id):
		return
	var state: Dictionary = _operations[request_id]
	state["terminal"] = true
	var wrapper: Variant = state.get("wrapper")
	if wrapper is PFCancelTaskV2 and not wrapper.is_terminal():
		wrapper.call_deferred("resolve", {
			"request_id": request_id,
			"local_stopped": true,
			"remote_cancel_confirmed": true,
			"billing_update": null,
		})


func _on_operation_finished(_result: Variant, request_id: String) -> void:
	_mark_terminal(request_id)


func _on_operation_failed(_error: Dictionary, request_id: String) -> void:
	_mark_terminal(request_id)


func _mark_terminal(request_id: String) -> void:
	if _operations.has(request_id):
		_operations[request_id]["terminal"] = true


func _on_cancel_timeout(request_id: String) -> void:
	if not _operations.has(request_id):
		return
	var state: Dictionary = _operations[request_id]
	var wrapper: Variant = state.get("wrapper")
	if wrapper is PFCancelTaskV2 and not wrapper.is_terminal():
		wrapper.reject(_cancel_error(request_id))


func _positive_pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and int(value[0]) > 0 and int(value[1]) > 0


func _cancel_error(request_id: String) -> Dictionary:
	return {
		"code": "cancel_failed", "stage": "cancel", "provider_id": "",
		"retryable": false, "retry_after_seconds": null, "status_code": null,
		"request_id": request_id, "attempts": 1, "expected_count": 0, "received_count": 0,
	}


func _cleanup_error(request_id: String) -> Dictionary:
	return {
		"code": "cleanup_failed", "stage": "cleanup", "provider_id": "",
		"retryable": false, "retry_after_seconds": null, "status_code": null,
		"request_id": request_id, "attempts": 1, "expected_count": 1, "received_count": 0,
	}
