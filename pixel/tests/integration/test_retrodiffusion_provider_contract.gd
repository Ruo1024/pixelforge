extends "res://addons/gut/test.gd"

const ProviderScript := preload("res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const GenerationRunCoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const ProviderResultMapperScript := preload("res://services/provider_result_mapper.gd")

const FIXTURE_PATH := "res://tests/fixtures/providers/retrodiffusion_success.json"
const TEST_SECRET := "rdpk-fixture-secret"

var _provider: PFRetroDiffusionProvider
var _host: Node
var _queue: Node


func before_each() -> void:
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_host = Node.new()
	add_child_autofree(_host)
	_provider = ProviderScript.new()
	_provider.attach_request_host(_host)
	assert_null(
		(
			_provider
			. configure(
				{
					"api_key": TEST_SECRET,
					"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/retrodiffusion-success",
				}
			)
		)
	)


func after_each() -> void:
	_provider.clear_session_config()
	ProviderService.delete_provider_credentials("retrodiffusion")


func test_capabilities_and_schema_match_provider_contract() -> void:
	assert_eq(_provider.get_api_version(), 2)
	var descriptors := _provider.get_model_descriptors()
	assert_eq(descriptors.size(), 3)
	assert_eq(
		descriptors.map(func(descriptor: Dictionary) -> String: return descriptor["model_id"]),
		["rd_plus", "rd_pro", "rd_fast"]
	)
	assert_eq(
		descriptors.map(func(descriptor: Dictionary) -> String: return descriptor["display_name"]),
		["Retro Diffusion Plus", "Retro Diffusion Pro", "Retro Diffusion Fast"]
	)
	var capabilities: Dictionary = descriptors[0]["capabilities"]
	assert_true(capabilities["txt2img"])
	assert_true(capabilities["img2img"])
	assert_true(capabilities["transparent_bg"])
	assert_true(capabilities["native_pixel"])
	assert_eq(capabilities["provider_output_sizes"], [])
	assert_eq(capabilities["target_size_constraints"]["min_width"], 16)
	assert_eq(capabilities["target_size_constraints"]["max_width"], 128)
	assert_eq(_provider.get_config_schema()[0]["kind"], "password")


func test_credential_save_and_validation_are_offline_until_user_generation() -> void:
	assert_false(
		bool(_provider.get_model_descriptors()[0]["capabilities"].get("safe_validation", true))
	)
	assert_null(_provider.validate_credentials())
	assert_eq(ProviderScript.MAX_RETRIES, 0)


func test_request_uses_current_official_fields_and_style_hints() -> void:
	var request := _request("request-body", "rd_plus", 4, [32, 32])
	request["seed"] = 123
	request["extra"] = {"remove_bg": false, "strength": 0.8}
	var hinted := _provider.build_request_body(request)

	assert_eq(hinted["prompt_style"], "rd_plus__low_res")
	assert_eq(hinted["num_images"], 4)
	assert_eq(hinted["seed"], 123)
	assert_false(hinted["remove_bg"])
	assert_false(
		hinted.has("strength"), "txt2img keeps canonical extra but omits conditional transport"
	)
	assert_false(JSON.stringify(hinted).contains(TEST_SECRET))
	var pro := _provider.build_request_body(_request("request-pro", "rd_pro", 1, [64, 64]))
	assert_eq(pro["prompt_style"], "rd_pro__default")


func test_recorded_four_image_fixture_decodes_raw_pixels_cost_and_seeds() -> void:
	var request := _request("decode", "rd_plus", 4, [1, 1])
	request["seed"] = 50
	var fixture := _load_fixture()
	var result := _provider.decode_success_payload(fixture, request)

	assert_eq(result["request_id"], "decode")
	assert_eq(result["items"].size(), 4)
	assert_eq(
		result["items"].map(func(item: Dictionary) -> Variant: return item["actual_seed"]),
		[null, null, null, null],
		"requested seed must never be guessed as the Provider's actual seed",
	)
	assert_eq(result["actual_cost_usd"], "1.000000")
	assert_eq(result["provider_meta"], {})
	for item in result["items"]:
		assert_null(item["error"])
		var image: Image = item["image"]
		assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	var numeric_cost := fixture.duplicate(true)
	numeric_cost["balance_cost"] = 1.0
	assert_null(_provider.decode_success_payload(numeric_cost, request)["actual_cost_usd"])


func test_error_mapping_covers_auth_quota_rate_limit_and_internal() -> void:
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 401)["code"], "auth_failed")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 429)["code"], "rate_limited")
	assert_eq(
		(
			_provider
			. map_error(HTTPRequest.RESULT_SUCCESS, 400, {"provider_code": "insufficient_balance"})["code"]
		),
		"quota_exceeded"
	)
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 500)["code"], "provider_internal")


func test_generate_uses_real_http_task_and_worker_decodes_result() -> void:
	var task: PFProviderTaskV2 = _provider.generate(
		_request("network-generate", "rd_plus", 1, [1, 1])
	)
	var outcome := {"status": "pending", "value": null}
	task.completed.connect(
		func(result: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = result
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = error
	)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))

	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["value"]["items"].size(), 1)
	assert_true(outcome["value"]["items"][0]["image"] is Image)
	assert_eq(outcome["value"]["actual_cost_usd"], "0.250000")
	assert_false(JSON.stringify(outcome["value"]).contains(TEST_SECRET))


func test_result_materializes_complete_provenance_and_hidden_actual_billing() -> void:
	var request := _request("materialize", "rd_pro", 2, [1, 1])
	request["seed"] = 3
	var decoded := _provider.decode_success_payload(_load_fixture(), request)
	assert_eq(decoded["actual_cost_usd"], "1.000000")
	for item in decoded["items"]:
		item["image"].resize(32, 32, Image.INTERPOLATE_NEAREST)
	request["provider_output_size"] = [32, 32]
	var graph := GraphScript.new()
	graph.id = "graph_retrodiffusion_contract"
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "retrodiffusion",
				"model_id": "rd_pro",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 2,
				"seed": -1,
				"extra": {},
			}
		)
	)
	var metadata := []
	for index in range(decoded["items"].size()):
		(
			metadata
			. append(
				{
					"name": "retro_%d" % index,
					"actual_seed": decoded["items"][index]["actual_seed"],
					"generation_snapshot":
					{
						"provider_id": "retrodiffusion",
						"model_id": "rd_pro",
						"mode": "txt2img",
						"prompt": "barrel",
						"prompt_preset_id": "",
						"prompt_prefix": "",
						"target_width": 32,
						"target_height": 32,
						"provider_output_size": [32, 32],
						"requested_seed": 3 + index,
						"reference_asset_ids": [],
						"reference_content_sha256s": [],
						"source_row_id": "",
						"extra": {"remove_bg": true, "strength": 0.8},
					},
				}
			)
		)
	var planned_slots := []
	for index in range(int(request["batch"])):
		var snapshot: Dictionary = metadata[index]["generation_snapshot"].duplicate(true)
		snapshot["kind"] = "generation"
		snapshot["graph_id"] = graph.id
		snapshot["source_node_id"] = "generate"
		(
			planned_slots
			. append(
				{
					"slot_id": "slot-retro-%d" % index,
					"request_id": request["request_id"],
					"source_row_id": "",
					"input_snapshot": snapshot,
				}
			)
		)
	var plan := {
		"ok": true,
		"requests": [request],
		"slots": planned_slots,
		"total_slots": planned_slots.size(),
	}
	var coordinator := GenerationRunCoordinatorScript.new()
	var result: Dictionary = coordinator.prepare_full_run(graph, "generate", "batch_1", plan)
	assert_true(result["ok"])
	var mapped: Dictionary = ProviderResultMapperScript.map_result(request, planned_slots, decoded)
	result = coordinator.apply_provider_mapping(graph, "batch_1", request, mapped, AssetLibrary)
	assert_true(result["ok"])
	var asset_ids := BatchNodeScript.get_visible_asset_ids(graph.get_node_params("batch_1"))
	var provenance: Dictionary = AssetLibrary.get_asset_meta(asset_ids[0])["provenance"]
	assert_eq(provenance["generation_snapshot"]["provider_id"], "retrodiffusion")
	assert_eq(provenance["generation_snapshot"]["source_node_id"], "generate")
	assert_false(provenance.has("provider_meta"))
	assert_false(JSON.stringify(provenance).contains(TEST_SECRET))


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary)
	return parsed


func _request(request_id: String, model_id: String, batch: int, output_size: Array) -> Dictionary:
	return {
		"run_id": "run-%s" % request_id,
		"request_id": request_id,
		"idempotency_key": "idem-%s" % request_id,
		"provider_id": "retrodiffusion",
		"mode": "txt2img",
		"model_id": model_id,
		"prompt": "barrel",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": output_size,
		"batch": batch,
		"seed": 7,
		"ref_images": [],
		"extra": {"remove_bg": true, "strength": 0.8},
	}


func _successful_images(result: Dictionary) -> Array:
	return result["items"].map(func(item: Dictionary) -> Image: return item["image"])


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
