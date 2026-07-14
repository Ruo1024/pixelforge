class_name PFGenerationRequestPlanner
extends RefCounted

## Pure B7-3 planner. It validates every input before returning requests or slots.

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const MAX_RESULTS_PER_RUN := 999
const SEED_MODULUS := 2147483648
const TECHNICAL_SUFFIX := "pixel art designed for a %dx%d true-pixel target, flat colors, crisp edges"


static func plan(input: Dictionary, descriptors: Array) -> Dictionary:
	var descriptor := _descriptor(descriptors, input)
	if descriptor.is_empty():
		return _failure("invalid_provider_model", "model_id")
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var target_width_value: Variant = input.get("target_width")
	var target_height_value: Variant = input.get("target_height")
	if not (target_width_value is int) or not (target_height_value is int):
		return _failure("invalid_target_size", "target_width")
	var target_width := int(target_width_value)
	var target_height := int(target_height_value)
	if not _target_is_valid(target_width, target_height, capabilities):
		return _failure("invalid_target_size", "target_width")
	var seed_value: Variant = input.get("seed", -1)
	if not (seed_value is int) or int(seed_value) < -1 or int(seed_value) > 2147483647:
		return _failure("invalid_seed", "seed")
	var extra_value: Variant = input.get("extra", {})
	if not (extra_value is Dictionary):
		return _failure("invalid_dynamic_param", "extra")
	var extra: Dictionary = extra_value
	var extra_issue: Variant = ContractV2._validate_dynamic_params(
		extra, descriptor.get("dynamic_params", [])
	)
	if extra_issue != null:
		return {"ok": false, "issue": extra_issue, "requests": [], "slots": []}
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
		return _failure("too_many_results", "batch_size")
	var provider_output_size := _provider_output_size(target_width, target_height, capabilities)
	if provider_output_size.is_empty():
		return _failure("invalid_provider_output_size", "provider_output_size")
	var run_id := String(input.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return _failure("invalid_request_field", "run_id")
	var supports_seed := bool(capabilities.get("seed", false))
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
		if not bool(capabilities.get("native_pixel", false)):
			final_prompt = (
				"%s, %s" % [semantic_prompt, TECHNICAL_SUFFIX % [target_width, target_height]]
			)
		var remaining := int(group["count"])
		while remaining > 0:
			var request_seed := -1
			var chunk := mini(max_batch, remaining)
			if supports_seed and int(seed_value) >= 0:
				request_seed = int((int(seed_value) + logical_index) % SEED_MODULUS)
				chunk = mini(chunk, SEED_MODULUS - request_seed)
			var request_id := "%s-request-%03d" % [run_id, request_index]
			for offset in range(chunk):
				var slot_id := "%s-slot-%03d" % [run_id, logical_index + offset]
				var requested_seed := -1
				if supports_seed and int(seed_value) >= 0:
					requested_seed = int((int(seed_value) + logical_index + offset) % SEED_MODULUS)
				slots.append(
					_slot(
						input,
						descriptor,
						slot_id,
						request_id,
						String(group["id"]),
						final_prompt,
						provider_output_size,
						requested_seed,
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
		var seed := int(slot.get("requested_seed", -1))
		var snapshot: Dictionary = Dictionary(slot.get("input_snapshot", {})).duplicate(true)
		var can_append := false
		if not groups.is_empty() and seed >= 0:
			var current: Dictionary = groups[-1]
			can_append = (
				current["slot_ids"].size() < maxi(1, max_batch)
				and String(current["source_row_id"]) == String(slot.get("source_row_id", ""))
				and int(current["last_seed"]) < 2147483647
				and seed == int(current["last_seed"]) + 1
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
	var parts: Array[String] = []
	for value in [prefix, prompt, row_text]:
		var text := String(value).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return ", ".join(parts)


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
	for index in range(ids.size()):
		if String(ids[index]).is_empty() or String(hashes[index]).length() != 64:
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


static func _target_is_valid(width: int, height: int, capabilities: Dictionary) -> bool:
	var constraints: Dictionary = capabilities.get("target_size_constraints", {})
	var allowed: Array = constraints.get("allowed_sizes", [])
	if not allowed.is_empty():
		return allowed.has([width, height])
	return (
		width >= int(constraints.get("min_width", 1))
		and width <= int(constraints.get("max_width", 0))
		and height >= int(constraints.get("min_height", 1))
		and height <= int(constraints.get("max_height", 0))
		and (
			(
				(width - int(constraints.get("min_width", 1)))
				% maxi(1, int(constraints.get("width_step", 1)))
			)
			== 0
		)
		and (
			(
				(height - int(constraints.get("min_height", 1)))
				% maxi(1, int(constraints.get("height_step", 1)))
			)
			== 0
		)
	)


static func _provider_output_size(
	target_width: int, target_height: int, capabilities: Dictionary
) -> Array:
	if bool(capabilities.get("native_pixel", false)):
		return [target_width, target_height]
	var sizes: Array = capabilities.get("provider_output_sizes", [])
	if sizes.is_empty():
		return []
	var best: Array = sizes[0]
	var best_error := absi(int(best[0]) * target_height - target_width * int(best[1]))
	for index in range(1, sizes.size()):
		var candidate: Array = sizes[index]
		var candidate_error := absi(
			int(candidate[0]) * target_height - target_width * int(candidate[1])
		)
		if candidate_error * int(best[1]) < best_error * int(candidate[1]):
			best = candidate
			best_error = candidate_error
	return best.duplicate()


static func _slot(
	input: Dictionary,
	descriptor: Dictionary,
	slot_id: String,
	request_id: String,
	row_id: String,
	prompt: String,
	provider_output_size: Array,
	requested_seed: int,
	extra: Dictionary
) -> Dictionary:
	return {
		"slot_id": slot_id,
		"request_id": request_id,
		"source_row_id": row_id,
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
			"target_width": int(input["target_width"]),
			"target_height": int(input["target_height"]),
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
