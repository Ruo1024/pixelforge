extends "res://addons/gut/test.gd"

const PLANNER_PATH := "res://services/generation_request_planner.gd"
const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")


class ReferenceSource:
	extends RefCounted

	var images := {}

	func get_image(asset_id: String) -> Image:
		var image: Variant = images.get(asset_id)
		return image.duplicate() if image is Image else null


func test_prompt_order_and_999_limit() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var input := _planner_input()
	input["target_height"] = 16
	input["prefix"] = "pixel art"
	input["prompt"] = "game prop"
	input["rows"] = [{"id": "barrel", "text": "wooden barrel", "count": 2}]
	var result: Dictionary = planner.plan(input, [_openai_descriptor()])
	assert_true(result["ok"])
	assert_eq(result["total_slots"], 2)
	assert_eq(
		result["requests"][0]["prompt"],
		(
			"pixel art, game prop, wooden barrel, "
			+ "pixel art designed for a 32x16 true-pixel target, flat colors, crisp edges"
		)
	)
	var too_many := _planner_input()
	too_many["batch_size"] = 1000
	var rejected: Dictionary = planner.plan(too_many, [_openai_descriptor()])
	assert_false(rejected["ok"])
	assert_eq(rejected["issue"]["code"], "result_limit_exceeded")
	assert_eq(rejected["requests"], [])
	assert_eq(rejected["slots"], [])


func test_native_and_non_native_output_size() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var openai := _planner_input()
	openai["target_width"] = 32
	openai["target_height"] = 16
	var remote: Dictionary = planner.plan(openai, [_openai_descriptor()])
	assert_true(remote["ok"])
	assert_eq(remote["requests"][0]["provider_output_size"], [1536, 1024])
	var retro := _planner_input()
	retro["provider_id"] = "retrodiffusion"
	retro["model_id"] = "rd_pro"
	retro["seed"] = 7
	retro["extra"] = {"remove_bg": true, "strength": 0.8}
	var native: Dictionary = planner.plan(retro, [_retro_descriptor()])
	assert_true(native["ok"])
	assert_eq(native["requests"][0]["provider_output_size"], [32, 32])
	assert_eq(native["requests"][0]["prompt"], "barrel")


func test_seed_capability_wrap_splitting_and_retry_groups() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var retro := _planner_input()
	retro["provider_id"] = "retrodiffusion"
	retro["model_id"] = "rd_pro"
	retro["batch_size"] = 5
	retro["seed"] = 42
	retro["extra"] = {"remove_bg": true, "strength": 0.8}
	var split: Dictionary = planner.plan(retro, [_retro_descriptor()])
	assert_true(split["ok"])
	assert_eq(split["requests"].map(func(value: Dictionary) -> int: return value["batch"]), [4, 1])
	assert_eq(split["requests"].map(func(value: Dictionary) -> int: return value["seed"]), [42, 46])
	retro["batch_size"] = 2
	retro["seed"] = 2147483647
	var wrapped: Dictionary = planner.plan(retro, [_retro_descriptor()])
	assert_eq(
		wrapped["requests"].map(func(value: Dictionary) -> int: return value["batch"]), [1, 1]
	)
	assert_eq(
		wrapped["requests"].map(func(value: Dictionary) -> int: return value["seed"]),
		[2147483647, 0]
	)
	var retry_slots := [split["slots"][0].duplicate(true), split["slots"][2].duplicate(true)]
	retry_slots[0]["slot_id"] = "s0"
	retry_slots[1]["slot_id"] = "s2"
	for slot in retry_slots:
		slot["status"] = "failed"
		slot["error"] = _retryable_error(String(slot["request_id"]), 4)
	var retries: Array = planner.group_retry_slots(retry_slots, 4)
	assert_eq(retries.size(), 2)
	assert_eq(retries[0]["slot_ids"], ["s0"])
	assert_eq(retries[1]["slot_ids"], ["s2"])
	var retry_plan: Dictionary = planner.plan_retry_slots(retry_slots, 4, "retry-run")
	assert_true(retry_plan["ok"])
	assert_eq(retry_plan["requests"].size(), 2)
	assert_eq(
		retry_plan["requests"].map(func(request: Dictionary) -> int: return request["seed"]),
		[42, 44],
	)
	assert_eq(
		retry_plan["slots"].map(func(slot: Dictionary) -> String: return slot["slot_id"]),
		["s0", "s2"],
	)
	var non_failed: Dictionary = retry_slots[0].duplicate(true)
	non_failed["status"] = "succeeded"
	non_failed["error"] = null
	assert_false(planner.plan_retry_slots([non_failed], 4, "retry-run-bad")["ok"])


func test_extra_exact_descriptor_shape_and_reference_boundary() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var input := _planner_input()
	input["provider_id"] = "retrodiffusion"
	input["model_id"] = "rd_pro"
	input["seed"] = 1
	input["extra"] = {"remove_bg": true, "strength": 0.8}
	input["reference_asset_ids"] = ["asset-a"]
	input["reference_content_sha256s"] = ["a".repeat(64)]
	input["ref_images"] = [Image.create(2, 2, false, Image.FORMAT_RGBA8)]
	var result: Dictionary = planner.plan(input, [_retro_descriptor()])
	assert_true(result["ok"])
	assert_eq(result["requests"][0]["mode"], "img2img")
	assert_eq(result["requests"][0]["extra"], {"remove_bg": true, "strength": 0.8})
	assert_null(
		ProviderContractV2.validate_gen_request(result["requests"][0]),
		"planner output remains the exact PFGenRequest shape",
	)
	assert_false(result["requests"][0].has("reference_asset_ids"))
	assert_eq(result["slots"][0]["input_snapshot"]["reference_asset_ids"], ["asset-a"])
	var invalid := input.duplicate(true)
	invalid["extra"]["unknown"] = true
	var rejected: Dictionary = planner.plan(invalid, [_retro_descriptor()])
	assert_false(rejected["ok"])
	assert_eq(rejected["issue"]["code"], "invalid_dynamic_param")
	assert_eq(rejected["requests"], [])
	var invalid_hash := input.duplicate(true)
	invalid_hash["reference_content_sha256s"] = ["G".repeat(64)]
	var bad_reference: Dictionary = planner.plan(invalid_hash, [_retro_descriptor()])
	assert_false(bad_reference["ok"])
	assert_eq(bad_reference["issue"]["code"], "invalid_reference_image")
	assert_eq(bad_reference["requests"], [])


func test_reference_assets_resolve_rgba8_ids_hashes_in_order() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var first := Image.create(2, 1, false, Image.FORMAT_RGB8)
	first.fill(Color("#ff0000"))
	var second := Image.create(1, 2, false, Image.FORMAT_RGBA8)
	second.fill(Color("#00ff0080"))
	var source := ReferenceSource.new()
	source.images = {"asset-b": second, "asset-a": first}
	var resolved: Dictionary = planner.resolve_reference_assets(["asset-a", "asset-b"], source)
	assert_true(resolved["ok"])
	assert_eq(resolved["reference_asset_ids"], ["asset-a", "asset-b"])
	assert_eq(resolved["ref_images"].size(), 2)
	assert_eq(resolved["ref_images"][0].get_format(), Image.FORMAT_RGBA8)
	assert_eq(
		resolved["reference_content_sha256s"],
		[
			GraphContextScript.image_content_sha256(resolved["ref_images"][0]),
			GraphContextScript.image_content_sha256(resolved["ref_images"][1]),
		]
	)
	var missing: Dictionary = planner.resolve_reference_assets(["asset-missing"], source)
	assert_false(missing["ok"])
	assert_eq(missing["issue"]["code"], "missing_reference")
	assert_eq(missing["ref_images"], [])


func test_run_request_attempt_row_chunks_and_output_tiebreak() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var rows := _planner_input()
	rows["provider_id"] = "retrodiffusion"
	rows["model_id"] = "rd_pro"
	rows["seed"] = 10
	rows["extra"] = {"remove_bg": true, "strength": 0.8}
	rows["rows"] = [
		{"id": "row-a", "text": "a", "count": 5},
		{"id": "row-b", "text": "b", "count": 5},
	]
	var planned: Dictionary = planner.plan(rows, [_retro_descriptor()])
	assert_true(planned["ok"])
	assert_eq(
		planned["requests"].map(func(request: Dictionary) -> int: return request["batch"]),
		[4, 1, 4, 1]
	)
	assert_eq(
		planned["slots"].map(func(slot: Dictionary) -> String: return slot["source_row_id"]),
		["row-a", "row-a", "row-a", "row-a", "row-a", "row-b", "row-b", "row-b", "row-b", "row-b"]
	)
	var tie := _planner_input()
	tie["target_width"] = 32
	tie["target_height"] = 32
	var tie_descriptor := _openai_descriptor().duplicate(true)
	tie_descriptor["capabilities"]["provider_output_sizes"] = [[96, 64], [32, 64]]
	var tie_result: Dictionary = planner.plan(tie, [tie_descriptor])
	assert_eq(tie_result["requests"][0]["provider_output_size"], [96, 64])


func test_temporary_production_path_uses_planner_and_reference_resolver() -> void:
	var source := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	var builder_source := FileAccess.get_file_as_string(
		"res://services/graph_generation_plan_builder.gd"
	)
	assert_string_contains(source, "GraphGenerationPlanBuilderScript.build(")
	assert_string_contains(builder_source, "GenerationRequestPlannerScript.plan(")
	assert_string_contains(
		builder_source, "GenerationRequestPlannerScript.resolve_reference_assets("
	)
	assert_lt(
		source.find("var request_result := _requests_for_graph"),
		source.find("_coordinator.preflight_plan("),
	)
	assert_lt(source.find("_coordinator.preflight_plan("), source.find("_prepare_pending_output"))


func test_all_local_validation_precedes_side_effects() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var cases := []
	var missing_provider := _planner_input()
	missing_provider["provider_id"] = "missing"
	cases.append([missing_provider, "invalid_provider_model"])
	var invalid_size := _planner_input()
	invalid_size["target_width"] = 0
	cases.append([invalid_size, "invalid_target_size"])
	var missing_prompt := _planner_input()
	missing_prompt["prompt"] = ""
	cases.append([missing_prompt, "missing_prompt_input"])
	var invalid_references := _planner_input()
	invalid_references["reference_asset_ids"] = ["asset-a"]
	cases.append([invalid_references, "invalid_reference_images"])
	var too_many := _planner_input()
	too_many["batch_size"] = 1000
	cases.append([too_many, "result_limit_exceeded"])
	for item in cases:
		var rejected: Dictionary = planner.plan(item[0], [_openai_descriptor()])
		assert_false(rejected["ok"])
		assert_eq(rejected["issue"]["code"], item[1])
		assert_eq(rejected["requests"], [])
		assert_eq(rejected["slots"], [])


func test_output_size_matrix_and_random_seed_snapshots() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	for dimensions in [
		[32, 32, [1024, 1024]],
		[32, 16, [1536, 1024]],
		[16, 32, [1024, 1536]],
	]:
		var input := _planner_input()
		input["target_width"] = dimensions[0]
		input["target_height"] = dimensions[1]
		input["batch_size"] = 2
		input["seed"] = -1
		var planned: Dictionary = planner.plan(input, [_openai_descriptor()])
		assert_true(planned["ok"])
		assert_eq(planned["requests"][0]["provider_output_size"], dimensions[2])
		assert_eq(
			planned["slots"].map(
				func(slot: Dictionary) -> int: return slot["input_snapshot"]["requested_seed"]
			),
			[-1, -1],
		)


func _planner_input() -> Dictionary:
	return {
		"run_id": "run-1",
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"target_width": 32,
		"target_height": 32,
		"batch_size": 1,
		"seed": -1,
		"prefix": "",
		"prompt": "barrel",
		"rows": [],
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
		"extra": {"quality": "low"},
	}


func _retryable_error(request_id: String, expected_count: int) -> Dictionary:
	return {
		"code": "result_count_mismatch",
		"stage": "decode",
		"provider_id": "retrodiffusion",
		"retryable": true,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": expected_count,
		"received_count": 0,
	}


func _openai_descriptor() -> Dictionary:
	return ProviderService.get_provider("openai_image").get_model_descriptors()[0]


func _retro_descriptor() -> Dictionary:
	return ProviderService.get_provider("retrodiffusion").get_model_descriptors()[1]
