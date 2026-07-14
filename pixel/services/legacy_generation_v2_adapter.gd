class_name PFLegacyGenerationV2Adapter
extends RefCounted

## B7-4 DELETE: temporary bridge for the legacy single-terminal generation call.
## It only converts already-settled items into final v2 slots; it owns no run state machine.

const IdUtil := preload("res://core/util/id_util.gd")

const ALLOWED_ERROR_CODES := [
	"auth_failed",
	"rate_limited",
	"quota_exceeded",
	"invalid_request",
	"network",
	"timeout",
	"content_policy",
	"provider_internal",
	"ambiguous_result",
	"malformed_response",
	"result_count_mismatch",
	"interrupted",
]


func materialize_terminal(
	graph_id: String,
	source_node_id: String,
	existing_batch_params: Dictionary,
	terminal_items: Array,
	asset_library: Node
) -> Dictionary:
	if asset_library == null or not asset_library.has_method("register_image"):
		return _command_error("missing_asset_library")
	if terminal_items.is_empty():
		return _command_error("empty_terminal_result")

	var prepared_items: Array[Dictionary] = []
	var provider_id := ""
	for index in range(terminal_items.size()):
		var raw_item: Variant = terminal_items[index]
		if not (raw_item is Dictionary):
			return _command_error("invalid_terminal_item", {"index": index})
		var item: Dictionary = raw_item
		var metadata: Dictionary = (
			Dictionary(item.get("metadata", {})).duplicate(true)
			if item.get("metadata", {}) is Dictionary
			else {}
		)
		var image: Image = item.get("image", null) as Image
		var snapshot := _generation_input_snapshot(graph_id, source_node_id, metadata, image)
		if provider_id.is_empty():
			provider_id = String(snapshot["provider_id"])
		elif provider_id != String(snapshot["provider_id"]):
			return _command_error("mixed_terminal_providers")
		prepared_items.append(
			{
				"image": image,
				"metadata": metadata,
				"snapshot": snapshot,
				"error": item.get("error", null),
			}
		)

	var run_id := IdUtil.uuid_v4()
	var request_id := IdUtil.uuid_v4()
	var input_snapshots := {}
	var result_slots: Array[Dictionary] = []
	var failed_items: Array[Dictionary] = []
	var succeeded_count := 0
	for index in range(prepared_items.size()):
		var item: Dictionary = prepared_items[index]
		var metadata: Dictionary = item["metadata"]
		var image: Image = item["image"]
		var slot_id := IdUtil.uuid_v4()
		var snapshot_id := IdUtil.uuid_v4()
		var snapshot: Dictionary = item["snapshot"]
		input_snapshots[snapshot_id] = snapshot

		var terminal_error: Variant = item["error"]
		var succeeded := image != null and terminal_error == null
		var slot := {
			"slot_id": slot_id,
			"run_id": run_id,
			"request_id": request_id,
			"source_row_id": String(snapshot["source_row_id"]),
			"source_asset_id": "",
			"input_snapshot_id": snapshot_id,
			"planned_size": Array(snapshot["provider_output_size"]).duplicate(),
			"status": "succeeded" if succeeded else "failed",
			"detached": false,
			"unexpected": false,
			"error": null,
		}
		if succeeded:
			succeeded_count += 1
			var asset_id: String = asset_library.register_image(
				image,
				String(metadata.get("name", "mock_%03d" % index)),
				_asset_meta(graph_id, source_node_id, run_id, request_id, snapshot, metadata, image)
			)
			if asset_id.is_empty():
				return _command_error("asset_registration_failed", {"index": index})
			slot["asset_id"] = asset_id
		else:
			failed_items.append({"index": index, "error": terminal_error})
		result_slots.append(slot)

	var summary_error: Variant = null
	for failed_item in failed_items:
		var safe_error := _terminal_error(
			failed_item["error"],
			provider_id,
			request_id,
			terminal_items.size(),
			succeeded_count
		)
		result_slots[int(failed_item["index"])]["error"] = safe_error
		if summary_error == null:
			summary_error = safe_error.duplicate(true)
	var request_records: Array[Dictionary] = [
		_request_record(
			run_id,
			request_id,
			result_slots,
			provider_id,
			succeeded_count,
			summary_error
		)
	]

	var batch_params := {
		"label": String(existing_batch_params.get("label", "")),
		"source_node_id": source_node_id,
		"source_run_id": run_id,
		"role": "current",
		"input_snapshots": input_snapshots,
		"request_records": request_records,
		"result_slots": result_slots,
	}
	return {"ok": true, "batch_params": batch_params, "result_slots": result_slots.duplicate(true)}


func _generation_input_snapshot(
	graph_id: String, source_node_id: String, metadata: Dictionary, image: Image
) -> Dictionary:
	var legacy: Dictionary = (
		Dictionary(metadata.get("generation_snapshot", {})).duplicate(true)
		if metadata.get("generation_snapshot", {}) is Dictionary
		else {}
	)
	var reference_ids := _string_array(
		legacy.get("reference_asset_ids", metadata.get("reference_asset_ids", []))
	)
	var reference_hashes := _string_array(
		legacy.get(
			"reference_content_sha256s", metadata.get("reference_content_sha256s", [])
		)
	)
	var width := _positive_int(
		legacy.get("target_width", legacy.get("width", image.get_width() if image != null else 1)),
		1
	)
	var height := _positive_int(
		legacy.get(
			"target_height", legacy.get("height", image.get_height() if image != null else 1)
		),
		1
	)
	var provider_size := _positive_size(
		legacy.get("provider_output_size", [width, height]), [width, height]
	)
	return {
		"kind": "generation",
		"graph_id": graph_id,
		"source_node_id": source_node_id,
		"provider_id": String(
			legacy.get("provider_id", metadata.get("provider_id", metadata.get("provider", "mock")))
		),
		"model_id": String(
			legacy.get("model_id", metadata.get("model_id", metadata.get("model", "pixel_mock_v1")))
		),
		"mode": "img2img" if not reference_ids.is_empty() else "txt2img",
		"prompt": String(legacy.get("prompt", metadata.get("prompt", ""))),
		"source_row_id": String(legacy.get("source_row_id", metadata.get("source_row_id", ""))),
		"prompt_preset_id": String(legacy.get("prompt_preset_id", "")),
		"prompt_prefix": String(legacy.get("prompt_prefix", "")),
		"reference_asset_ids": reference_ids,
		"reference_content_sha256s": reference_hashes,
		"target_width": width,
		"target_height": height,
		"provider_output_size": provider_size,
		"requested_seed": _valid_seed(
			legacy.get("requested_seed", legacy.get("seed", metadata.get("seed", -1)))
		),
		"extra": (
			Dictionary(legacy.get("extra", {})).duplicate(true)
			if legacy.get("extra", {}) is Dictionary
			else {}
		),
	}


func _asset_meta(
	graph_id: String,
	source_node_id: String,
	run_id: String,
	request_id: String,
	snapshot: Dictionary,
	metadata: Dictionary,
	image: Image
) -> Dictionary:
	var generation_snapshot := {
		"provider_id": snapshot["provider_id"],
		"model_id": snapshot["model_id"],
		"mode": snapshot["mode"],
		"target_width": snapshot["target_width"],
		"target_height": snapshot["target_height"],
		"provider_output_size": Array(snapshot["provider_output_size"]).duplicate(),
		"actual_width": image.get_width(),
		"actual_height": image.get_height(),
		"requested_seed": snapshot["requested_seed"],
		"actual_seed": _actual_seed(metadata.get("actual_seed", metadata.get("seed", null))),
		"run_id": run_id,
		"request_id": request_id,
		"source_node_id": source_node_id,
		"source_row_id": snapshot["source_row_id"],
		"prompt_preset_id": snapshot["prompt_preset_id"],
		"prompt_prefix": snapshot["prompt_prefix"],
		"prompt": snapshot["prompt"],
		"reference_asset_ids": Array(snapshot["reference_asset_ids"]).duplicate(),
		"reference_content_sha256s": (
			Array(snapshot["reference_content_sha256s"]).duplicate()
		),
		"extra": Dictionary(snapshot["extra"]).duplicate(true),
	}
	return {
		"origin": "generated",
		"tags": [String(snapshot["provider_id"]), "graph"],
		"provenance": {
			"graph_id": graph_id,
			"created_at": IdUtil.utc_now_iso(),
			"generation_snapshot": generation_snapshot,
		},
	}


func _request_record(
	run_id: String,
	request_id: String,
	result_slots: Array[Dictionary],
	provider_id: String,
	succeeded_count: int,
	error: Variant
) -> Dictionary:
	var slot_ids: Array[String] = []
	for slot in result_slots:
		slot_ids.append(String(slot["slot_id"]))
	var requested_count := result_slots.size()
	var state := "succeeded"
	if succeeded_count == 0:
		state = "failed"
	elif succeeded_count < requested_count:
		state = "partial"
	return {
		"kind": "provider",
		"provider_id": provider_id,
		"run_id": run_id,
		"request_id": request_id,
		"source_row_id": "",
		"slot_ids": slot_ids,
		"requested_count": requested_count,
		"received_count": succeeded_count,
		"attempts": 1,
		"state": state,
		"actual_cost_usd": null,
		"charge_id": "",
		"provider_meta": {},
		"remote_cancel_confirmed": null,
		"error": error,
	}


func _terminal_error(
	value: Variant,
	provider_id: String,
	request_id: String,
	expected_count: int,
	received_count: int
) -> Dictionary:
	var raw: Dictionary = value if value is Dictionary else {}
	var code := String(raw.get("code", "ambiguous_result"))
	if code not in ALLOWED_ERROR_CODES:
		code = "ambiguous_result"
	return {
		"code": code,
		"stage": "materialize",
		"provider_id": provider_id,
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": expected_count,
		"received_count": received_count,
	}


func _positive_size(value: Variant, fallback: Array) -> Array:
	if value is Array and value.size() == 2:
		var width := _positive_int(value[0], 0)
		var height := _positive_int(value[1], 0)
		if width > 0 and height > 0:
			return [width, height]
	return fallback.duplicate()


func _positive_int(value: Variant, fallback: int) -> int:
	if value is int or value is float:
		var result := int(value)
		if result > 0:
			return result
	return fallback


func _valid_seed(value: Variant) -> int:
	if value is int or value is float:
		var seed := int(value)
		if seed >= -1 and seed <= 2147483647:
			return seed
	return -1


func _actual_seed(value: Variant) -> Variant:
	if value == null:
		return null
	var seed := _valid_seed(value)
	return seed if seed >= 0 else null


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array or value is PackedStringArray):
		return result
	for entry in value:
		var text := String(entry)
		if not text.is_empty():
			result.append(text)
	return result


func _command_error(code: String, args: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": {"code": code, "args": args.duplicate(true)}}
