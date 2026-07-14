extends "res://addons/gut/test.gd"

const PLANNER_PATH := "res://services/generation_request_planner.gd"


func test_prompt_order_and_999_limit() -> void:
	var planner: Script = load(PLANNER_PATH)
	assert_not_null(planner)
	if planner == null:
		return
	var input := _planner_input()
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
	assert_eq(rejected["issue"]["code"], "too_many_results")
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
	var retry_slots := [
		{
			"slot_id": "s0",
			"source_row_id": "",
			"requested_seed": 42,
			"input_snapshot": {"prompt": "barrel"}
		},
		{
			"slot_id": "s2",
			"source_row_id": "",
			"requested_seed": 44,
			"input_snapshot": {"prompt": "barrel"}
		},
	]
	var retries: Array = planner.group_retry_slots(retry_slots, 4)
	assert_eq(retries.size(), 2)
	assert_eq(retries[0]["slot_ids"], ["s0"])
	assert_eq(retries[1]["slot_ids"], ["s2"])


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
	assert_false(result["requests"][0].has("reference_asset_ids"))
	assert_eq(result["slots"][0]["input_snapshot"]["reference_asset_ids"], ["asset-a"])
	var invalid := input.duplicate(true)
	invalid["extra"]["unknown"] = true
	var rejected: Dictionary = planner.plan(invalid, [_retro_descriptor()])
	assert_false(rejected["ok"])
	assert_eq(rejected["issue"]["code"], "invalid_dynamic_param")
	assert_eq(rejected["requests"], [])


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


func _openai_descriptor() -> Dictionary:
	return ProviderService.get_provider("openai_image").get_model_descriptors()[0]


func _retro_descriptor() -> Dictionary:
	return ProviderService.get_provider("retrodiffusion").get_model_descriptors()[1]
