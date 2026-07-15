class_name PFGenerationRequestPlanner
extends RefCounted

## Pure B7-3 planner. It validates every input before returning requests or slots.

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")
const DeliveryPolicy := preload("res://services/generation_delivery_policy.gd")
const PromptBuilder := preload("res://services/generation_prompt_builder.gd")
const MAX_RESULTS_PER_RUN := 16


static func resolve_reference_assets(asset_ids: Array, asset_source: Variant) -> Dictionary:
	if asset_source == null or not asset_source.has_method("get_image"):
		return _reference_failure("missing_reference")
	var resolved_ids: Array[String] = []
	var content_hashes: Array[String] = []
	var images: Array[Image] = []
	for asset_id_value in asset_ids:
		if not (asset_id_value is String):
			return _reference_failure("invalid_reference")
		var asset_id := String(asset_id_value)
		if asset_id.is_empty():
			return _reference_failure("invalid_reference")
		var image_value: Variant = asset_source.get_image(asset_id)
		if not (image_value is Image) or image_value.is_empty():
			return _reference_failure("missing_reference")
		var image: Image = image_value.duplicate()
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		var content_hash := GraphContextScript.image_content_sha256(image)
		if content_hash.length() != 64:
			return _reference_failure("invalid_reference")
		resolved_ids.append(asset_id)
		content_hashes.append(content_hash)
		images.append(image)
	return {
		"ok": true,
		"issue": null,
		"reference_asset_ids": resolved_ids,
		"reference_content_sha256s": content_hashes,
		"ref_images": images,
	}


static func plan(input: Dictionary, descriptors: Array) -> Dictionary:
	var descriptor := _descriptor(descriptors, input)
	if descriptor.is_empty():
		return _failure("invalid_provider_model", "model_id")
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var resolution_preset := String(input.get("resolution_preset", ""))
	var orientation := String(input.get("orientation", ""))
	var delivery_size := DeliveryPolicy.delivery_size(resolution_preset, orientation)
	var provider_output_size := DeliveryPolicy.request_size(resolution_preset, orientation)
	if delivery_size.is_empty() or provider_output_size.is_empty():
		return _failure("invalid_delivery_size", "resolution_preset")
	var target_width := int(delivery_size[0])
	var target_height := int(delivery_size[1])
	var seed_value: Variant = input.get("seed", -1)
	if not (seed_value is int) or int(seed_value) != -1:
		return _failure("invalid_seed", "seed")
	var extra_value: Variant = input.get("extra", {})
	if not (extra_value is Dictionary) or not Dictionary(extra_value).is_empty():
		return _failure("invalid_dynamic_param", "extra")
	var extra: Dictionary = extra_value
	var reference_issue := _reference_issue(input, capabilities)
	if not reference_issue.is_empty():
		return _failure(String(reference_issue["code"]), String(reference_issue["field"]))
	var groups := _groups(input)
	if groups.is_empty():
		return _failure("missing_prompt_input", "prompt")
	var total_slots := 0
	for group in groups:
		total_slots += int(group["count"])
	if total_slots > MAX_RESULTS_PER_RUN:
		return _failure("result_limit_exceeded", "batch_size")
	var run_id := String(input.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return _failure("invalid_request_field", "run_id")
	var max_batch := maxi(1, int(capabilities.get("max_batch", 1)))
	var prefix := String(input.get("prefix", "")).strip_edges()
	var prompt := String(input.get("prompt", "")).strip_edges()
	var request_index := 0
	var logical_index := 0
	var requests: Array[Dictionary] = []
	var slots: Array[Dictionary] = []
	for group in groups:
		var semantic_prompt := _semantic_prompt(prefix, prompt, String(group["text"]))
		if semantic_prompt.is_empty():
			return _failure("missing_prompt_input", "prompt")
		var final_prompt := semantic_prompt
		var remaining := int(group["count"])
		while remaining > 0:
			var request_seed := -1
			var chunk := mini(max_batch, remaining)
			var request_id := "%s-request-%03d" % [run_id, request_index]
			for offset in range(chunk):
				var slot_id := "%s-slot-%03d" % [run_id, logical_index + offset]
				slots.append(
					_slot(
						input,
						descriptor,
						slot_id,
						request_id,
						String(group["id"]),
						final_prompt,
						delivery_size,
						provider_output_size,
						-1,
						extra
					)
				)
			(
				requests
				. append(
					{
						"run_id": run_id,
						"request_id": request_id,
						"idempotency_key": "%s:%s" % [run_id, request_id],
						"provider_id": String(descriptor["provider_id"]),
						"mode": "txt2img" if input.get("ref_images", []).is_empty() else "img2img",
						"model_id": String(descriptor["model_id"]),
						"prompt": final_prompt,
						"target_width": target_width,
						"target_height": target_height,
						"provider_output_size": provider_output_size.duplicate(),
						"batch": chunk,
						"seed": request_seed,
						"ref_images": Array(input.get("ref_images", [])).duplicate(),
						"extra": extra.duplicate(true),
					}
				)
			)
			logical_index += chunk
			remaining -= chunk
			request_index += 1
	return {
		"ok": true,
		"issue": null,
		"requests": requests,
		"slots": slots,
		"total_slots": total_slots,
	}


static func group_retry_slots(slots: Array, max_batch: int) -> Array:
	var groups: Array = []
	for value in slots:
		if not (value is Dictionary):
			continue
		var slot: Dictionary = value
		var snapshot: Dictionary = Dictionary(slot.get("input_snapshot", {})).duplicate(true)
		var seed := int(snapshot.get("requested_seed", -1))
		var can_append := false
		if not groups.is_empty():
			var current: Dictionary = groups[-1]
			can_append = (
				current["slot_ids"].size() < maxi(1, max_batch)
				and String(current["source_row_id"]) == String(slot.get("source_row_id", ""))
				and (
					(seed == -1 and int(current["last_seed"]) == -1)
					or (
						seed >= 0
						and int(current["last_seed"]) < 2147483647
						and seed == int(current["last_seed"]) + 1
					)
				)
				and (
					_snapshot_without_seed(current["input_snapshot"])
					== _snapshot_without_seed(snapshot)
				)
			)
		if can_append:
			groups[-1]["slot_ids"].append(String(slot.get("slot_id", "")))
			groups[-1]["batch"] = int(groups[-1]["batch"]) + 1
			groups[-1]["last_seed"] = seed
		else:
			(
				groups
				. append(
					{
						"source_row_id": String(slot.get("source_row_id", "")),
						"slot_ids": [String(slot.get("slot_id", ""))],
						"batch": 1,
						"seed": seed,
						"last_seed": seed,
						"input_snapshot": snapshot,
					}
				)
			)
	for group in groups:
		group.erase("last_seed")
	return groups


static func plan_retry_slots(
	slots: Array, max_batch: int, run_id: String, reference_source: Variant = null
) -> Dictionary:
	if slots.is_empty() or max_batch <= 0 or run_id.strip_edges().is_empty():
		return _failure("invalid_request_field", "retry_slots")
	for value in slots:
		if not (value is Dictionary):
			return _failure("invalid_request_field", "retry_slots")
		var slot: Dictionary = value
		var error: Variant = slot.get("error")
		if (
			String(slot.get("status", "")) != "failed"
			or not (error is Dictionary)
			or ContractV2.validate_pf_error(error) != null
			or not bool(error.get("retryable", false))
		):
			return _failure("invalid_request_field", "retry_slots")
	var groups := group_retry_slots(slots, max_batch)
	if groups.is_empty():
		return _failure("invalid_request_field", "retry_slots")
	var requests: Array[Dictionary] = []
	var planned_slots: Array[Dictionary] = []
	for index in range(groups.size()):
		var group: Dictionary = groups[index]
		var snapshot: Dictionary = Dictionary(group.get("input_snapshot", {})).duplicate(true)
		var reference_ids: Array = snapshot.get("reference_asset_ids", [])
		var expected_hashes: Array = snapshot.get("reference_content_sha256s", [])
		var ref_images: Array = []
		if not reference_ids.is_empty():
			var resolved := resolve_reference_assets(reference_ids, reference_source)
			if (
				not bool(resolved.get("ok", false))
				or resolved.get("reference_content_sha256s", []) != expected_hashes
			):
				return _failure("invalid_reference_images", "references")
			ref_images = Array(resolved["ref_images"]).duplicate()
		var request_id := "%s-retry-request-%03d" % [run_id, index]
		var request := {
			"run_id": run_id,
			"request_id": request_id,
			"idempotency_key": "%s:%s" % [run_id, request_id],
			"provider_id": String(snapshot.get("provider_id", "")),
			"mode": String(snapshot.get("mode", "")),
			"model_id": String(snapshot.get("model_id", "")),
			"prompt": String(snapshot.get("prompt", "")),
			"target_width": int(snapshot.get("target_width", 0)),
			"target_height": int(snapshot.get("target_height", 0)),
			"provider_output_size": Array(snapshot.get("provider_output_size", [])).duplicate(),
			"batch": int(group["batch"]),
			"seed": int(group["seed"]),
			"ref_images": ref_images,
			"extra": Dictionary(snapshot.get("extra", {})).duplicate(true),
		}
		if ContractV2.validate_gen_request(request) != null:
			return _failure("invalid_request_field", "retry_slots")
		requests.append(request)
		for slot_id in group["slot_ids"]:
			var original: Dictionary = {}
			for value in slots:
				if value is Dictionary and String(value.get("slot_id", "")) == String(slot_id):
					original = Dictionary(value).duplicate(true)
					break
			if original.is_empty():
				return _failure("invalid_request_field", "retry_slots")
			original["request_id"] = request_id
			planned_slots.append(original)
	return {
		"ok": true,
		"issue": null,
		"requests": requests,
		"slots": planned_slots,
		"total_slots": planned_slots.size(),
	}


static func _descriptor(descriptors: Array, input: Dictionary) -> Dictionary:
	for descriptor in descriptors:
		if (
			String(descriptor.get("provider_id", "")) == String(input.get("provider_id", ""))
			and String(descriptor.get("model_id", "")) == String(input.get("model_id", ""))
		):
			return descriptor.duplicate(true)
	return {}


static func _groups(input: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rows_value: Variant = input.get("rows", [])
	if rows_value is Array:
		for row_value in rows_value:
			if not (row_value is Dictionary):
				continue
			var row: Dictionary = row_value
			if not bool(row.get("enabled", true)):
				continue
			var text := String(row.get("text", "")).strip_edges()
			var count_value: Variant = row.get("count")
			if text.is_empty() or not (count_value is int) or int(count_value) < 1:
				return []
			result.append({"id": String(row.get("id", "")), "text": text, "count": count_value})
	if not result.is_empty():
		return result
	var count_value: Variant = input.get("batch_size")
	if not (count_value is int) or int(count_value) < 1:
		return []
	return [{"id": "", "text": "", "count": count_value}]


static func _semantic_prompt(prefix: String, prompt: String, row_text: String) -> String:
	return PromptBuilder.build(prefix, prompt, row_text)


static func _reference_issue(input: Dictionary, capabilities: Dictionary) -> Dictionary:
	var ids_value: Variant = input.get("reference_asset_ids", [])
	var hashes_value: Variant = input.get("reference_content_sha256s", [])
	var images_value: Variant = input.get("ref_images", [])
	if not (ids_value is Array) or not (hashes_value is Array) or not (images_value is Array):
		return {"code": "invalid_reference_images", "field": "ref_images"}
	var ids: Array = ids_value
	var hashes: Array = hashes_value
	var images: Array = images_value
	if ids.size() != hashes.size() or ids.size() != images.size():
		return {"code": "invalid_reference_images", "field": "ref_images"}
	if ids.size() > int(capabilities.get("max_reference_images", 0)):
		return {"code": "invalid_reference_count", "field": "ref_images"}
	var sha256_pattern := RegEx.create_from_string("^[0-9a-f]{64}$")
	for index in range(ids.size()):
		if String(ids[index]).is_empty() or sha256_pattern.search(String(hashes[index])) == null:
			return {"code": "invalid_reference_image", "field": "ref_images"}
		if not (images[index] is Image):
			return {"code": "invalid_reference_image", "field": "ref_images"}
		var image: Image = images[index]
		if image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
			return {"code": "invalid_reference_image", "field": "ref_images"}
	var mode := "txt2img" if images.is_empty() else "img2img"
	if not bool(capabilities.get(mode, false)):
		return {"code": "unsupported_generation_mode", "field": "ref_images"}
	return {}


static func _slot(
	input: Dictionary,
	descriptor: Dictionary,
	slot_id: String,
	request_id: String,
	row_id: String,
	prompt: String,
	delivery_size: Array,
	provider_output_size: Array,
	requested_seed: int,
	extra: Dictionary
) -> Dictionary:
	return {
		"slot_id": slot_id,
		"request_id": request_id,
		"source_row_id": row_id,
		"planned_size": delivery_size.duplicate(),
		"input_snapshot":
		{
			"kind": "generation",
			"graph_id": String(input.get("graph_id", "graph-planner")),
			"source_node_id": String(input.get("source_node_id", "generate")),
			"provider_id": String(descriptor["provider_id"]),
			"model_id": String(descriptor["model_id"]),
			"mode": "txt2img" if input.get("ref_images", []).is_empty() else "img2img",
			"prompt": prompt,
			"source_row_id": row_id,
			"prompt_preset_id": String(input.get("prompt_preset_id", "")),
			"prompt_prefix": String(input.get("prefix", "")).strip_edges(),
			"reference_asset_ids": Array(input.get("reference_asset_ids", [])).duplicate(),
			"reference_content_sha256s":
			Array(input.get("reference_content_sha256s", [])).duplicate(),
			"target_width": int(delivery_size[0]),
			"target_height": int(delivery_size[1]),
			"provider_output_size": provider_output_size.duplicate(),
			"requested_seed": requested_seed,
			"extra": extra.duplicate(true),
		},
	}


static func _snapshot_without_seed(value: Dictionary) -> Dictionary:
	var snapshot := value.duplicate(true)
	snapshot.erase("requested_seed")
	return snapshot


static func _failure(code: String, field: String) -> Dictionary:
	return {
		"ok": false,
		"issue": {"code": code, "field": field, "args": {}},
		"requests": [],
		"slots": [],
	}


static func _reference_failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"issue": {"code": code, "field": "references", "args": {}},
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
	}
