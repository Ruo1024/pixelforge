extends "res://addons/gut/test.gd"

const CONTRACT_PATH := "res://core/provider/pf_provider_contract_v2.gd"


func test_exact_shape_mode_and_removed_fields() -> void:
	var script: Script = load(CONTRACT_PATH)
	assert_not_null(script)
	if script == null:
		return
	var valid := _request()
	assert_null(script.validate_gen_request(valid))

	for removed_key in ["style", "negative_prompt", "ref_image", "mask", "width", "height"]:
		var invalid := valid.duplicate(true)
		invalid[removed_key] = null
		var issue: Dictionary = script.validate_gen_request(invalid)
		assert_eq(issue["code"], "unknown_request_field", removed_key)
		assert_eq(issue["field"], removed_key, removed_key)

	var bad_mode := valid.duplicate(true)
	bad_mode["mode"] = "img2img"
	assert_eq(script.validate_gen_request(bad_mode)["code"], "invalid_generation_mode")
	var image_mode := valid.duplicate(true)
	image_mode["mode"] = "img2img"
	image_mode["ref_images"] = [Image.create(1, 1, false, Image.FORMAT_RGBA8)]
	assert_null(script.validate_gen_request(image_mode))


func test_progress_result_error_and_cancel_shapes_are_strict() -> void:
	var script: Script = load(CONTRACT_PATH)
	assert_not_null(script)
	if script == null:
		return
	assert_null(
		(
			script
			. validate_provider_progress(
				{
					"phase": "submitting",
					"determinate": false,
					"ratio": null,
					"completed_items": 0,
					"total_items": 1,
				},
				1
			)
		)
	)
	var bad_progress := {
		"phase": "materializing",
		"determinate": false,
		"ratio": null,
		"completed_items": 0,
		"total_items": 1,
	}
	assert_eq(script.validate_provider_progress(bad_progress, 1)["code"], "invalid_progress_phase")

	var error := _pf_error()
	assert_null(script.validate_pf_error(error))
	var error_with_message := error.duplicate(true)
	error_with_message["message"] = "raw provider text"
	assert_eq(script.validate_pf_error(error_with_message)["code"], "unknown_error_field")

	assert_null(
		(
			script
			. validate_cancel_result(
				{
					"request_id": "request-1",
					"local_stopped": true,
					"remote_cancel_confirmed": false,
					"billing_update": null,
				}
			)
		)
	)
	var bad_cancel := {
		"request_id": "request-1",
		"local_stopped": false,
		"remote_cancel_confirmed": false,
		"billing_update": null,
	}
	assert_eq(script.validate_cancel_result(bad_cancel)["code"], "invalid_cancel_result")


func _request() -> Dictionary:
	return {
		"run_id": "run-1",
		"request_id": "request-1",
		"idempotency_key": "idem-1",
		"provider_id": "openai_image",
		"mode": "txt2img",
		"model_id": "gpt-image-2",
		"prompt": "tiny sprite",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [1024, 1024],
		"batch": 1,
		"seed": -1,
		"ref_images": [],
		"extra": {"quality": "low"},
	}


func _pf_error() -> Dictionary:
	return {
		"code": "provider_internal",
		"stage": "provider",
		"provider_id": "openai_image",
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": "request-1",
		"attempts": 1,
		"expected_count": 1,
		"received_count": 0,
	}
