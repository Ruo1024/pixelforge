extends "res://addons/gut/test.gd"

const Planner := preload("res://services/generation_request_planner.gd")
const DeliveryPolicy := preload("res://services/generation_delivery_policy.gd")
const PromptBuilder := preload("res://services/generation_prompt_builder.gd")
const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")


class ReferenceSource:
	extends RefCounted

	var images := {}

	func get_image(asset_id: String) -> Image:
		var image: Variant = images.get(asset_id)
		return image.duplicate() if image is Image else null


func test_prompt_builder_is_the_single_ordered_prefix_path() -> void:
	assert_eq(PromptBuilder.build("pixel art", "forest", "barrel"), "pixel art, forest, barrel")
	assert_eq(PromptBuilder.build("  pixel art  ", "", "barrel"), "pixel art, barrel")
	var input := _planner_input()
	input["prefix"] = "pixel art"
	input["prompt"] = "forest"
	input["rows"] = [{"id": "barrel", "text": "barrel", "count": 2}]
	var result: Dictionary = Planner.plan(input, [_descriptor()])
	assert_true(result["ok"])
	assert_eq(result["requests"][0]["prompt"], "pixel art, forest, barrel")
	assert_eq(result["slots"][0]["input_snapshot"]["prompt"], "pixel art, forest, barrel")
	assert_eq(result["requests"][0]["prompt"].count("pixel art"), 1)


func test_fixed_delivery_request_matrix_and_center_crop() -> void:
	var expected := {
		"720p":
		{
			"landscape": [[1280, 720], [1280, 720]],
			"portrait": [[720, 1280], [720, 1280]],
			"square": [[720, 720], [720, 720]],
		},
		"1080p":
		{
			"landscape": [[1920, 1080], [1920, 1088]],
			"portrait": [[1080, 1920], [1088, 1920]],
			"square": [[1080, 1080], [1088, 1088]],
		},
		"2K":
		{
			"landscape": [[2560, 1440], [2560, 1440]],
			"portrait": [[1440, 2560], [1440, 2560]],
			"square": [[1440, 1440], [1440, 1440]],
		},
		"4K":
		{
			"landscape": [[3840, 2160], [3840, 2160]],
			"portrait": [[2160, 3840], [2160, 3840]],
			"square": [[2160, 2160], [2160, 2160]],
		},
	}
	for preset in DeliveryPolicy.RESOLUTION_PRESETS:
		for orientation in DeliveryPolicy.ORIENTATIONS:
			var input := _planner_input()
			input["resolution_preset"] = preset
			input["orientation"] = orientation
			var planned: Dictionary = Planner.plan(input, [_descriptor()])
			var pair: Array = expected[preset][orientation]
			assert_true(planned["ok"], "%s/%s" % [preset, orientation])
			assert_eq(DeliveryPolicy.delivery_size(preset, orientation), pair[0])
			assert_eq(DeliveryPolicy.request_size(preset, orientation), pair[1])
			assert_eq(planned["requests"][0]["target_width"], pair[0][0])
			assert_eq(planned["requests"][0]["target_height"], pair[0][1])
			assert_eq(planned["requests"][0]["provider_output_size"], pair[1])
			assert_eq(planned["slots"][0]["planned_size"], pair[0])
			assert_eq(int(pair[1][0]) % 16, 0)
			assert_eq(int(pair[1][1]) % 16, 0)

	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			source.set_pixel(x, y, Color8(x, y, 0, 255))
	var cropped := DeliveryPolicy.center_crop_to_delivery(source, [6, 6])
	assert_eq(cropped.get_size(), Vector2i(6, 6))
	assert_eq(cropped.get_pixel(0, 0), source.get_pixel(1, 1))
	assert_eq(cropped.get_pixel(5, 5), source.get_pixel(6, 6))


func test_count_limit_validation_and_descriptor_batch_splitting_preserve_order() -> void:
	var input := _planner_input()
	input["batch_size"] = 10
	var planned: Dictionary = Planner.plan(input, [_descriptor()])
	assert_true(planned["ok"])
	assert_eq(planned["total_slots"], 10)
	assert_eq(
		planned["requests"].map(func(request: Dictionary) -> int: return request["batch"]),
		[4, 4, 2]
	)
	assert_eq(
		planned["slots"].map(func(slot: Dictionary) -> String: return slot["slot_id"]),
		[
			"run-1-slot-000",
			"run-1-slot-001",
			"run-1-slot-002",
			"run-1-slot-003",
			"run-1-slot-004",
			"run-1-slot-005",
			"run-1-slot-006",
			"run-1-slot-007",
			"run-1-slot-008",
			"run-1-slot-009",
		]
	)
	for invalid_count in [0, 17]:
		var rejected_input := _planner_input()
		rejected_input["batch_size"] = invalid_count
		var rejected: Dictionary = Planner.plan(rejected_input, [_descriptor()])
		assert_false(rejected["ok"])
		assert_eq(rejected["requests"], [])
		assert_eq(rejected["slots"], [])


func test_seed_and_extra_are_frozen() -> void:
	var input := _planner_input()
	input["seed"] = 7
	var rejected_seed: Dictionary = Planner.plan(input, [_descriptor()])
	assert_false(rejected_seed["ok"])
	assert_eq(rejected_seed["issue"]["code"], "invalid_seed")
	input = _planner_input()
	input["extra"] = {"quality": "high"}
	var rejected_extra: Dictionary = Planner.plan(input, [_descriptor()])
	assert_false(rejected_extra["ok"])
	assert_eq(rejected_extra["issue"]["code"], "invalid_dynamic_param")


func test_reference_assets_resolve_rgba8_ids_hashes_in_order() -> void:
	var first := Image.create(2, 1, false, Image.FORMAT_RGB8)
	first.fill(Color("#ff0000"))
	var second := Image.create(1, 2, false, Image.FORMAT_RGBA8)
	second.fill(Color("#00ff0080"))
	var source := ReferenceSource.new()
	source.images = {"asset-b": second, "asset-a": first}
	var resolved: Dictionary = Planner.resolve_reference_assets(["asset-a", "asset-b"], source)
	assert_true(resolved["ok"])
	assert_eq(resolved["reference_asset_ids"], ["asset-a", "asset-b"])
	assert_eq(resolved["ref_images"][0].get_format(), Image.FORMAT_RGBA8)
	assert_eq(
		resolved["reference_content_sha256s"],
		[
			GraphContextScript.image_content_sha256(resolved["ref_images"][0]),
			GraphContextScript.image_content_sha256(resolved["ref_images"][1]),
		]
	)
	var missing: Dictionary = Planner.resolve_reference_assets(["asset-missing"], source)
	assert_false(missing["ok"])
	assert_eq(missing["ref_images"], [])


func test_random_seed_retry_slots_can_regroup_without_changing_snapshots() -> void:
	var input := _planner_input()
	input["batch_size"] = 3
	var planned: Dictionary = Planner.plan(input, [_descriptor()])
	var failed := []
	for slot in planned["slots"]:
		var copy: Dictionary = slot.duplicate(true)
		copy["status"] = "failed"
		copy["error"] = _retryable_error(String(copy["request_id"]), 3)
		failed.append(copy)
	var retried: Dictionary = Planner.plan_retry_slots(failed, 4, "retry-run")
	assert_true(retried["ok"])
	assert_eq(retried["requests"].size(), 1)
	assert_eq(retried["requests"][0]["batch"], 3)
	assert_eq(retried["requests"][0]["seed"], -1)
	assert_null(ProviderContractV2.validate_gen_request(retried["requests"][0]))


func _planner_input() -> Dictionary:
	return {
		"run_id": "run-1",
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"resolution_preset": "1080p",
		"orientation": "square",
		"batch_size": 1,
		"seed": -1,
		"prefix": "",
		"prompt": "barrel",
		"rows": [],
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
		"extra": {},
	}


func _descriptor() -> Dictionary:
	return {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"display_name": "GPT Image 2",
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"max_reference_images": 4,
			"max_batch": 4,
		},
		"dynamic_params": [],
	}


func _retryable_error(request_id: String, expected_count: int) -> Dictionary:
	return {
		"code": "result_count_mismatch",
		"stage": "decode",
		"provider_id": "openai_image",
		"retryable": true,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": expected_count,
		"received_count": 0,
	}
