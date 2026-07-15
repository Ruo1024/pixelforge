extends "res://addons/gut/test.gd"

const PROVIDER_TASK_PATH := "res://core/provider/pf_provider_task_v2.gd"
const CANCEL_TASK_PATH := "res://services/pf_cancel_task_v2.gd"


func test_provider_wrapper_has_v2_signals_and_exactly_one_terminal() -> void:
	var script: Script = load(PROVIDER_TASK_PATH)
	assert_not_null(script)
	if script == null:
		return
	var task: Variant = script.new()
	var observed := {"progress": 0, "completed": 0, "failed": 0, "canceled": 0}
	task.progress.connect(func(_value: Dictionary) -> void: observed["progress"] += 1)
	task.completed.connect(func(_value: Dictionary) -> void: observed["completed"] += 1)
	task.failed.connect(func(_value: Dictionary) -> void: observed["failed"] += 1)
	task.canceled.connect(func(_value: String) -> void: observed["canceled"] += 1)

	assert_true(
		(
			task
			. emit_progress(
				{
					"phase": "submitting",
					"determinate": false,
					"ratio": null,
					"completed_items": 0,
					"total_items": 1,
				}
			)
		)
	)
	assert_true(
		(
			task
			. resolve(
				{
					"request_id": "request-1",
					"items": [],
					"actual_cost_usd": null,
					"charge_id": "",
					"provider_meta": {},
				}
			)
		)
	)
	assert_false(task.reject(_pf_error("provider_internal", "provider")))
	assert_false(task.mark_canceled("request-1"))
	assert_false(
		(
			task
			. emit_progress(
				{
					"phase": "decoding",
					"determinate": true,
					"ratio": 1.0,
					"completed_items": 1,
					"total_items": 1,
				}
			)
		)
	)
	assert_eq(observed, {"progress": 1, "completed": 1, "failed": 0, "canceled": 0})
	assert_true(task.is_terminal())


func test_cancel_wrapper_has_only_resolved_rejected_and_ignores_late_terminal() -> void:
	var script: Script = load(CANCEL_TASK_PATH)
	assert_not_null(script)
	if script == null:
		return
	var task: Variant = script.new()
	var observed := {"resolved": 0, "rejected": 0}
	task.resolved.connect(func(_value: Dictionary) -> void: observed["resolved"] += 1)
	task.rejected.connect(func(_value: Dictionary) -> void: observed["rejected"] += 1)
	assert_false(task.has_signal("progress"))
	assert_false(task.has_signal("canceled"))
	assert_true(
		(
			task
			. resolve(
				{
					"request_id": "request-1",
					"local_stopped": true,
					"remote_cancel_confirmed": false,
					"billing_update": null,
				}
			)
		)
	)
	assert_false(task.reject(_pf_error("cancel_failed", "cancel")))
	assert_eq(observed, {"resolved": 1, "rejected": 0})
	assert_true(task.is_terminal())


func test_progress_shape_phase_and_ratio_are_monotonic() -> void:
	var request := {
		"request_id": "request-1",
		"provider_id": "openai_image",
		"provider_output_size": [1, 1],
		"batch": 2,
	}
	var task := PFProviderTaskV2.new(request, ["remote_task_id"])
	var observed := []
	task.progress.connect(func(value: Dictionary) -> void: observed.append(value))
	assert_true(task.emit_progress(_progress("submitting", false, null, 0, 2)))
	assert_false(task.emit_progress(_progress("submitting", false, null, 0, 2)))
	assert_true(task.emit_progress(_progress("provider_processing", true, 0.5, 1, 2)))
	assert_false(task.emit_progress(_progress("provider_processing", true, 0.4, 1, 2)))
	assert_false(task.emit_progress(_progress("submitting", true, 0.6, 1, 2)))
	assert_false(task.emit_progress(_progress("downloading", true, 0.7, 0, 2)))
	var unknown := _progress("downloading", true, 0.7, 1, 2)
	unknown["raw"] = "forbidden"
	assert_false(task.emit_progress(unknown))
	assert_eq(observed.size(), 2)


func test_invalid_completed_shape_becomes_one_safe_failed_terminal() -> void:
	var request := {
		"request_id": "request-1",
		"provider_id": "openai_image",
		"provider_output_size": [2, 2],
		"batch": 1,
	}
	var task := PFProviderTaskV2.new(request, ["remote_task_id"])
	var observed := {"completed": 0, "failed": []}
	task.completed.connect(func(_value: Dictionary) -> void: observed["completed"] += 1)
	task.failed.connect(func(value: Dictionary) -> void: observed["failed"].append(value))
	var wrong_size := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	assert_true(
		(
			task
			. resolve(
				{
					"request_id": "request-1",
					"items":
					[{"index": 0, "image": wrong_size, "actual_seed": null, "error": null}],
					"actual_cost_usd": null,
					"charge_id": "",
					"provider_meta": {},
				}
			)
		)
	)
	assert_eq(observed["completed"], 0)
	assert_eq(observed["failed"].size(), 1)
	assert_eq(observed["failed"][0]["code"], "ambiguous_result")
	assert_false(task.resolve({}))


func test_provider_base_has_only_v2_five_method_surface_and_no_runtime_owners() -> void:
	var base_source := FileAccess.get_file_as_string("res://core/provider/pf_provider.gd")
	var expression := RegEx.new()
	assert_eq(expression.compile("(?m)^func ([a-z_]+)"), OK)
	var methods := []
	for match_result in expression.search_all(base_source):
		methods.append(match_result.get_string(1))
	assert_eq(
		methods,
		[
			"get_api_version",
			"get_config_schema",
			"get_model_descriptors",
			"generate",
			"cancel",
		]
	)
	for path in [
		"res://plugins/provider_openai/openai_image_provider.gd",
		"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		for forbidden in [
			"get_capabilities",
			"validate_generation_request",
			"get_reference_images",
			"resolve_model_id",
			"res://core/graph",
			"AssetRegistry",
			"GenerationRunCoordinator",
			"CostService",
		]:
			assert_false(source.contains(forbidden), "%s: %s" % [path, forbidden])


func _progress(
	phase: String, determinate: bool, ratio: Variant, completed_items: int, total_items: int
) -> Dictionary:
	return {
		"phase": phase,
		"determinate": determinate,
		"ratio": ratio,
		"completed_items": completed_items,
		"total_items": total_items,
	}


func _pf_error(code: String, stage: String) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": "openai_image",
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": "request-1",
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
