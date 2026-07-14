class_name PFProviderContractV2
extends RefCounted

## Pure shape validation for the Provider API v2 boundary.
## Invalid inputs return a safe PFValidationIssue and never preserve provider text.

const REQUEST_KEYS := [
	"batch",
	"extra",
	"idempotency_key",
	"mode",
	"model_id",
	"prompt",
	"provider_id",
	"provider_output_size",
	"ref_images",
	"request_id",
	"run_id",
	"seed",
	"target_height",
	"target_width",
]
const PROGRESS_KEYS := ["completed_items", "determinate", "phase", "ratio", "total_items"]
const RESULT_KEYS := ["actual_cost_usd", "charge_id", "items", "provider_meta", "request_id"]
const RESULT_ITEM_KEYS := ["actual_seed", "error", "image", "index"]
const ERROR_REQUIRED_KEYS := [
	"attempts",
	"code",
	"expected_count",
	"provider_id",
	"received_count",
	"request_id",
	"retry_after_seconds",
	"retryable",
	"stage",
	"status_code",
]
const ERROR_CODES := [
	"auth_failed",
	"rate_limited",
	"quota_exceeded",
	"invalid_request",
	"network",
	"timeout",
	"content_policy",
	"provider_internal",
	"cancel_failed",
	"ambiguous_result",
	"malformed_response",
	"result_count_mismatch",
	"interrupted",
	"cleanup_failed",
]
const ERROR_STAGES := ["queue", "http", "provider", "decode", "materialize", "cleanup", "cancel"]
const PROVIDER_PHASES := ["submitting", "provider_processing", "downloading", "decoding"]
const CANCEL_RESULT_KEYS := [
	"billing_update", "local_stopped", "remote_cancel_confirmed", "request_id"
]
const BILLING_KEYS := ["actual_cost_usd", "charge_id", "provider_meta"]
const SAFE_CODE_PATTERN := "^[A-Za-z0-9._:-]{1,64}$"
const SAFE_REMOTE_ID_PATTERN := "^[A-Za-z0-9._:-]{1,128}$"
const USD_PATTERN := "^(0|[1-9][0-9]{0,8})[.][0-9]{6}$"


static func validate_gen_request(request: Dictionary) -> Variant:
	var key_issue: Variant = _validate_exact_keys(request, REQUEST_KEYS, "request")
	if key_issue != null:
		return key_issue
	for field in ["run_id", "request_id", "idempotency_key", "provider_id", "model_id"]:
		if not (request[field] is String) or String(request[field]).strip_edges().is_empty():
			return _issue("invalid_request_field", field)
	if not (request["prompt"] is String):
		return _issue("invalid_request_field", "prompt")
	if not (request["mode"] is String) or not String(request["mode"]) in ["txt2img", "img2img"]:
		return _issue("invalid_generation_mode", "mode")
	for field in ["target_width", "target_height", "batch", "seed"]:
		if not (request[field] is int):
			return _issue("invalid_request_field", field)
	if int(request["target_width"]) <= 0 or int(request["target_height"]) <= 0:
		return _issue("invalid_target_size", "target_width")
	if int(request["batch"]) <= 0:
		return _issue("invalid_batch", "batch")
	if int(request["seed"]) < -1 or int(request["seed"]) > 2147483647:
		return _issue("invalid_seed", "seed")
	var output_size: Variant = request["provider_output_size"]
	if not _is_positive_int_pair(output_size):
		return _issue("invalid_provider_output_size", "provider_output_size")
	if not (request["ref_images"] is Array):
		return _issue("invalid_reference_images", "ref_images")
	for image_value in request["ref_images"]:
		if not (image_value is Image):
			return _issue("invalid_reference_image", "ref_images")
		var image: Image = image_value
		if image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
			return _issue("invalid_reference_image", "ref_images")
	var expected_mode := "txt2img" if request["ref_images"].is_empty() else "img2img"
	if String(request["mode"]) != expected_mode:
		return _issue("invalid_generation_mode", "mode")
	if not (request["extra"] is Dictionary):
		return _issue("invalid_request_field", "extra")
	return null


static func validate_request_for_provider(
	request: Dictionary, provider_id: String, descriptors: Array[Dictionary]
) -> Variant:
	var shape_issue: Variant = validate_gen_request(request)
	if shape_issue != null:
		return shape_issue
	if String(request["provider_id"]) != provider_id:
		return _issue("invalid_provider", "provider_id")
	var descriptor := get_model_descriptor(descriptors, String(request["model_id"]))
	if descriptor.is_empty():
		return _issue("invalid_model", "model_id")
	var capabilities: Dictionary = descriptor["capabilities"]
	var mode := String(request["mode"])
	if not bool(capabilities.get(mode, false)):
		return _issue("unsupported_generation_mode", "mode")
	if int(request["batch"]) > int(capabilities.get("max_batch", 0)):
		return _issue("invalid_batch", "batch")
	if request["ref_images"].size() > int(capabilities.get("max_reference_images", 0)):
		return _issue("invalid_reference_count", "ref_images")
	var target_issue: Variant = _validate_target_size(request, capabilities)
	if target_issue != null:
		return target_issue
	var output_issue: Variant = _validate_provider_output_size(request, capabilities)
	if output_issue != null:
		return output_issue
	return _validate_dynamic_params(request["extra"], descriptor.get("dynamic_params", []))


static func resolve_model_id(descriptors: Array[Dictionary], model_id: String = "") -> String:
	var requested := model_id.strip_edges()
	var default_id := ""
	for descriptor in descriptors:
		var descriptor_id := String(descriptor.get("model_id", ""))
		if bool(descriptor.get("is_default", false)):
			default_id = descriptor_id
		if not requested.is_empty() and descriptor_id == requested:
			return descriptor_id
	return default_id if requested.is_empty() else ""


static func get_model_descriptor(
	descriptors: Array[Dictionary], model_id: String = ""
) -> Dictionary:
	var resolved := resolve_model_id(descriptors, model_id)
	for descriptor in descriptors:
		if String(descriptor.get("model_id", "")) == resolved:
			return descriptor.duplicate(true)
	return {}


static func validate_provider_progress(progress: Dictionary, expected_total: int) -> Variant:
	var key_issue: Variant = _validate_exact_keys(progress, PROGRESS_KEYS, "progress")
	if key_issue != null:
		return key_issue
	if not (progress["phase"] is String) or not String(progress["phase"]) in PROVIDER_PHASES:
		return _issue("invalid_progress_phase", "phase")
	if not (progress["determinate"] is bool):
		return _issue("invalid_progress", "determinate")
	if not (progress["completed_items"] is int) or not (progress["total_items"] is int):
		return _issue("invalid_progress", "completed_items")
	var completed := int(progress["completed_items"])
	var total := int(progress["total_items"])
	if total != expected_total or total <= 0 or completed < 0 or completed > total:
		return _issue("invalid_progress", "total_items")
	if bool(progress["determinate"]):
		if not (progress["ratio"] is float or progress["ratio"] is int):
			return _issue("invalid_progress", "ratio")
		var ratio := float(progress["ratio"])
		if not is_finite(ratio) or ratio < 0.0 or ratio > 1.0:
			return _issue("invalid_progress", "ratio")
	elif progress["ratio"] != null:
		return _issue("invalid_progress", "ratio")
	return null


static func validate_gen_result(
	result: Dictionary, expected_size: Array = [], allowed_meta_keys: Array = []
) -> Variant:
	var key_issue: Variant = _validate_exact_keys(result, RESULT_KEYS, "result")
	if key_issue != null:
		return key_issue
	if not (result["request_id"] is String) or String(result["request_id"]).is_empty():
		return _issue("invalid_result", "request_id")
	if not (result["items"] is Array):
		return _issue("invalid_result", "items")
	for index in range(result["items"].size()):
		var item_value: Variant = result["items"][index]
		if not (item_value is Dictionary):
			return _issue("invalid_result_item", "items", {"index": index})
		var item: Dictionary = item_value
		var item_issue: Variant = _validate_exact_keys(item, RESULT_ITEM_KEYS, "items")
		if item_issue != null or not (item["index"] is int) or int(item["index"]) != index:
			return _issue("invalid_result_item", "items", {"index": index})
		var success := item["image"] is Image and item["error"] == null
		var failure := item["image"] == null and item["error"] is Dictionary
		if not success and not failure:
			return _issue("invalid_result_item", "items", {"index": index})
		if success:
			var image: Image = item["image"]
			if image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
				return _issue("invalid_result_item", "items", {"index": index})
			if (
				not expected_size.is_empty()
				and (
					image.get_width() != int(expected_size[0])
					or image.get_height() != int(expected_size[1])
				)
			):
				return _issue("provider_output_size_mismatch", "items", {"index": index})
		elif validate_pf_error(item["error"]) != null:
			return _issue("invalid_result_item", "items", {"index": index})
		var actual_seed: Variant = item["actual_seed"]
		if failure and actual_seed != null:
			return _issue("invalid_result_item", "actual_seed", {"index": index})
		if (
			actual_seed != null
			and (not (actual_seed is int) or int(actual_seed) < 0 or int(actual_seed) > 2147483647)
		):
			return _issue("invalid_result_item", "actual_seed", {"index": index})
	var cost_issue: Variant = _validate_optional_usd(result["actual_cost_usd"], "actual_cost_usd")
	if cost_issue != null:
		return cost_issue
	if (
		not (result["charge_id"] is String)
		or not _matches("^[A-Za-z0-9._:-]{0,128}$", String(result["charge_id"]))
	):
		return _issue("invalid_result", "charge_id")
	return _validate_provider_meta(result["provider_meta"], allowed_meta_keys)


static func validate_pf_error(error: Dictionary) -> Variant:
	var allowed := ERROR_REQUIRED_KEYS.duplicate()
	allowed.append("provider_code")
	var key_issue: Variant = _validate_exact_keys(error, allowed, "error", ERROR_REQUIRED_KEYS)
	if key_issue != null:
		return key_issue
	if not (error["code"] is String) or not String(error["code"]) in ERROR_CODES:
		return _issue("invalid_error_code", "code")
	if not (error["stage"] is String) or not String(error["stage"]) in ERROR_STAGES:
		return _issue("invalid_error_stage", "stage")
	if (
		not (error["provider_id"] is String)
		or not (error["request_id"] is String)
		or String(error["request_id"]).is_empty()
	):
		return _issue("invalid_error_field", "provider_id")
	if not (error["retryable"] is bool):
		return _issue("invalid_error_field", "retryable")
	var attempts: Variant = error["attempts"]
	if not (attempts is int) or int(attempts) < 0 or int(attempts) > 3:
		return _issue("invalid_error_field", "attempts")
	if String(error["stage"]) == "queue" and int(attempts) != 0:
		return _issue("invalid_error_field", "attempts")
	if String(error["stage"]) != "queue" and int(attempts) < 1:
		return _issue("invalid_error_field", "attempts")
	for field in ["expected_count", "received_count"]:
		if not (error[field] is int) or int(error[field]) < 0:
			return _issue("invalid_error_field", field)
	var retry_after: Variant = error["retry_after_seconds"]
	if (
		retry_after != null
		and (
			not (retry_after is int or retry_after is float)
			or not is_finite(float(retry_after))
			or float(retry_after) < 0.0
			or float(retry_after) > 86400.0
		)
	):
		return _issue("invalid_error_field", "retry_after_seconds")
	var status: Variant = error["status_code"]
	if status != null and (not (status is int) or int(status) < 100 or int(status) > 599):
		return _issue("invalid_error_field", "status_code")
	if (
		error.has("provider_code")
		and (
			not (error["provider_code"] is String)
			or not _matches(SAFE_CODE_PATTERN, String(error["provider_code"]))
		)
	):
		return _issue("invalid_error_field", "provider_code")
	return null


static func validate_cancel_result(result: Dictionary) -> Variant:
	var key_issue: Variant = _validate_exact_keys(result, CANCEL_RESULT_KEYS, "cancel_result")
	if key_issue != null:
		return key_issue
	if not (result["request_id"] is String) or String(result["request_id"]).is_empty():
		return _issue("invalid_cancel_result", "request_id")
	if result["local_stopped"] != true or not (result["remote_cancel_confirmed"] is bool):
		return _issue("invalid_cancel_result", "local_stopped")
	var billing: Variant = result["billing_update"]
	if billing == null:
		return null
	if not (billing is Dictionary):
		return _issue("invalid_cancel_result", "billing_update")
	var billing_issue: Variant = _validate_exact_keys(billing, BILLING_KEYS, "billing_update")
	if billing_issue != null:
		return billing_issue
	if billing["actual_cost_usd"] == null:
		return _issue("invalid_cancel_result", "actual_cost_usd")
	var cost_issue: Variant = _validate_optional_usd(billing["actual_cost_usd"], "actual_cost_usd")
	if cost_issue != null:
		return cost_issue
	if (
		not (billing["charge_id"] is String)
		or not _matches("^[A-Za-z0-9._:-]{0,128}$", String(billing["charge_id"]))
	):
		return _issue("invalid_cancel_result", "charge_id")
	return _validate_provider_meta(billing["provider_meta"], ["remote_task_id"])


static func _validate_provider_meta(value: Variant, allowed_keys: Array) -> Variant:
	if not (value is Dictionary):
		return _issue("invalid_provider_meta", "provider_meta")
	for key_value in value.keys():
		var key := String(key_value)
		if not allowed_keys.has(key):
			return _issue("unknown_provider_meta_field", key)
		if (
			key == "remote_task_id"
			and (
				not (value[key_value] is String)
				or not _matches(SAFE_REMOTE_ID_PATTERN, String(value[key_value]))
			)
		):
			return _issue("invalid_provider_meta", key)
	return null


static func _validate_target_size(request: Dictionary, capabilities: Dictionary) -> Variant:
	var constraints: Dictionary = capabilities.get("target_size_constraints", {})
	if constraints.is_empty():
		return _issue("invalid_target_constraints", "target_width")
	var width := int(request["target_width"])
	var height := int(request["target_height"])
	var allowed_sizes: Array = constraints.get("allowed_sizes", [])
	if not allowed_sizes.is_empty():
		return (
			null
			if allowed_sizes.has([width, height])
			else _issue("invalid_target_size", "target_width")
		)
	if (
		width < int(constraints.get("min_width", 1))
		or width > int(constraints.get("max_width", 0))
		or height < int(constraints.get("min_height", 1))
		or height > int(constraints.get("max_height", 0))
		or (
			(
				(width - int(constraints.get("min_width", 1)))
				% maxi(1, int(constraints.get("width_step", 1)))
			)
			!= 0
		)
		or (
			(
				(height - int(constraints.get("min_height", 1)))
				% maxi(1, int(constraints.get("height_step", 1)))
			)
			!= 0
		)
	):
		return _issue("invalid_target_size", "target_width")
	return null


static func _validate_provider_output_size(
	request: Dictionary, capabilities: Dictionary
) -> Variant:
	var output_size: Array = request["provider_output_size"]
	var native_pixel := bool(capabilities.get("native_pixel", false))
	var provider_sizes: Array = capabilities.get("provider_output_sizes", [])
	if native_pixel:
		if output_size != [request["target_width"], request["target_height"]]:
			return _issue("invalid_provider_output_size", "provider_output_size")
	elif not provider_sizes.has(output_size):
		return _issue("invalid_provider_output_size", "provider_output_size")
	return null


static func _validate_dynamic_params(extra: Dictionary, params: Array) -> Variant:
	if extra.size() != params.size():
		return _issue("invalid_dynamic_param", "extra")
	for spec_value in params:
		var spec: Dictionary = spec_value
		var key := String(spec.get("key", ""))
		if not extra.has(key) or not _dynamic_value_is_valid(extra[key], spec):
			return _issue("invalid_dynamic_param", "extra.%s" % key)
	return null


static func _dynamic_value_is_valid(value: Variant, spec: Dictionary) -> bool:
	match String(spec.get("kind", "")):
		"bool":
			return value is bool
		"int":
			return (
				value is int and int(value) >= int(spec["min"]) and int(value) <= int(spec["max"])
			)
		"float":
			return (
				(value is float or value is int)
				and float(value) >= float(spec["min"])
				and float(value) <= float(spec["max"])
			)
		"enum":
			return value is String and spec.get("values", []).has(value)
		"string":
			return value is String
	return false


static func _validate_optional_usd(value: Variant, field: String) -> Variant:
	if value == null:
		return null
	if not (value is String) or not _matches(USD_PATTERN, String(value)):
		return _issue("invalid_usd_amount", field)
	return null


static func _validate_exact_keys(
	value: Dictionary, allowed_keys: Array, surface: String, required_keys: Array = []
) -> Variant:
	var required := allowed_keys if required_keys.is_empty() else required_keys
	for key_value in value.keys():
		var key := String(key_value)
		if not allowed_keys.has(key):
			return _issue("unknown_%s_field" % surface, key)
	for key in required:
		if not value.has(key):
			return _issue("missing_%s_field" % surface, String(key))
	return null


static func _is_positive_int_pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value[0] is int
		and value[1] is int
		and int(value[0]) > 0
		and int(value[1]) > 0
	)


static func _matches(pattern: String, value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(pattern) == OK and expression.search(value) != null


static func _issue(code: String, field: String, args: Dictionary = {}) -> Dictionary:
	return {"code": code, "field": field, "args": args.duplicate(true)}
