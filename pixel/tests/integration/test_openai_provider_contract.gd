extends "res://addons/gut/test.gd"

const ProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const GenerationRunCoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const ProviderResultMapperScript := preload("res://services/provider_result_mapper.gd")
const CLOUD_CONTROLLER_PATH := "res://ui/shell/generation_run_controller.gd"
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")

const FIXTURE_PATH := "res://tests/fixtures/providers/openai_image_success.json"
const SECRET_SENTINEL := "sk-pf-m4-v1-contract-secret"

var _provider: PFOpenAIImageProvider
var _host: Node
var _queue: Node


class RecordingCanvas:
	extends Control

	var status_updates := []
	var refreshed_batches := []

	func _set_graph_node_status(
		graph_id: String, node_id: String, status_key: String, detail: String
	) -> void:
		status_updates.append([graph_id, node_id, status_key, detail])

	func _refresh_graph_batch_card(graph_id: String, node_id: String) -> void:
		refreshed_batches.append([graph_id, node_id])


func before_each() -> void:
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_host = Node.new()
	add_child_autofree(_host)
	_provider = ProviderScript.new(
		OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-success",
		OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-edit",
		OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-model"
	)
	_provider.attach_request_host(_host)
	get_tree().root.get_node("ProjectService").new_project("M4 V1 Contract")


func after_each() -> void:
	_provider.clear_session_config()


func test_ui_provider_catalog_declares_reference_support_without_network_request() -> void:
	var main: Control = load("res://ui/shell/main.gd").new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	var descriptor := ProviderService.get_model_descriptor("openai_image", "gpt-image-2")
	assert_false(descriptor.is_empty())
	assert_true(descriptor["capabilities"]["img2img"])
	assert_eq(descriptor["capabilities"]["max_reference_images"], 4)
	assert_eq(ProviderService.get_provider_ids(), ["openai_image", "retrodiffusion"])
	assert_false(ProviderService.get_selectable_provider_ids().has("comfyui"))
	var settings_dialog: Node = main.get_node("M21UiController/ProviderSettingsDialog")
	assert_eq(settings_dialog.get_current_provider_id(), "openai_image")
	assert_true(TaskQueue.is_idle())


func test_generation_post_has_no_automatic_network_retry() -> void:
	assert_eq(ProviderScript.MAX_NETWORK_RETRIES, 0)


func test_capabilities_and_persistent_schema_match_contract() -> void:
	assert_eq(_provider.get_api_version(), 2)
	var descriptors := _provider.get_model_descriptors()
	assert_eq(descriptors.size(), 1)
	var descriptor: Dictionary = descriptors[0]
	assert_eq(descriptor["provider_id"], "openai_image")
	assert_eq(descriptor["model_id"], "gpt-image-2")
	var capabilities: Dictionary = descriptor["capabilities"]
	assert_true(capabilities["txt2img"])
	assert_false(capabilities["transparent_bg"])
	assert_true(capabilities["img2img"])
	assert_false(capabilities["native_pixel"])
	assert_eq(capabilities["max_batch"], 4)
	assert_false(capabilities.has("cost_estimate"))
	assert_eq(capabilities["target_size_constraints"]["allowed_sizes"].size(), 12)
	assert_has(capabilities["target_size_constraints"]["allowed_sizes"], [1920, 1080])
	assert_eq(capabilities["provider_output_sizes"].size(), 12)
	assert_has(capabilities["provider_output_sizes"], [1920, 1088])
	assert_eq(descriptor["dynamic_params"], [])
	var schema := _provider.get_config_schema()
	assert_eq(schema.size(), 4)
	assert_eq(schema[0]["key"], "base_url")
	assert_eq(schema[0]["default"], "https://api.openai.com/v1")
	assert_eq(schema[1]["kind"], "password")
	assert_false(schema[1].has("session_only"))
	assert_eq(schema[2]["key"], "remote_model")
	assert_eq(schema[3]["key"], "api_mode")


func test_request_body_is_sanitized_and_adapts_target_size() -> void:
	assert_null(_provider.configure({"api_key": SECRET_SENTINEL}))
	var request := _request("request-body", 4, [1920, 1088])
	request["prompt"] = "wooden barrel"
	var body := _provider.build_request_body(request)
	assert_eq(body["model"], "gpt-image-2")
	assert_false(body.has("quality"))
	assert_eq(body["size"], "1920x1088")
	assert_eq(body["n"], 4)
	assert_eq(body["background"], "opaque")
	assert_eq(body["output_format"], "png")
	assert_eq(body["prompt"], "wooden barrel")
	assert_false(body.has("seed"), "seed=false omits only the remote transport field")
	assert_false(
		body.has("idempotency_key"), "native_idempotency=false never claims remote idempotency"
	)
	assert_false(JSON.stringify(body).contains(SECRET_SENTINEL))
	assert_false(JSON.stringify(request).contains(SECRET_SENTINEL))
	assert_false(JSON.stringify(ProjectService.current_project.manifest).contains(SECRET_SENTINEL))
	assert_false(JSON.stringify(ProjectService.current_project.graphs).contains(SECRET_SENTINEL))
	assert_ne(SettingsService.get_setting("provider", "api_key", "missing"), SECRET_SENTINEL)


func test_recorded_success_fixture_decodes_to_rgba_result() -> void:
	var payload := _load_fixture()
	var result := _provider.decode_success_payload(payload, _request("decode", 1, [1, 1]))
	assert_eq(result["request_id"], "decode")
	assert_eq(result["items"].size(), 1)
	assert_null(result["items"][0]["error"])
	var image: Image = result["items"][0]["image"]
	assert_eq(image.get_size(), Vector2i(1, 1))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	assert_null(result["actual_cost_usd"])
	assert_eq(result["provider_meta"], {})


func test_targeted_request_uses_only_the_requested_generate_branch() -> void:
	var first_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	first_image.fill(Color.RED)
	var second_image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	second_image.fill(Color.BLUE)
	var first_id := AssetLibrary.register_image(first_image, "first")
	var second_id := AssetLibrary.register_image(second_image, "second")
	var graph := GraphScript.new()
	graph.id = "two_cloud_branches"
	for suffix in ["a", "b"]:
		var reference_id := first_id if suffix == "a" else second_id
		(
			graph
			. add_node(
				ObjectListNodeScript.new(),
				"subjects_%s" % suffix,
				{
					"rows":
					[
						{
							"id": "row_%s" % suffix,
							"text": "subject_%s" % suffix,
							"count": 1,
							"enabled": true,
						}
					]
				},
				Vector2.ZERO
			)
		)
		graph.add_node(
			ImageInputNodeScript.new(),
			"reference_%s" % suffix,
			{"asset_id": reference_id},
			Vector2.ZERO
		)
		(
			graph
			. add_node(
				AiGenerateNodeScript.new(),
				"generate_%s" % suffix,
				{
					"provider_id": "openai_image",
					"model_id": "gpt-image-2",
					"resolution_preset": "720p",
					"orientation": "square" if suffix == "a" else "landscape",
					"batch_size": 1,
					"seed": -1,
					"extra": {},
				},
				Vector2.ZERO
			)
		)
		graph.add_node(BatchNodeScript.new(), "batch_%s" % suffix, {}, Vector2.ZERO)
		graph.add_edge("subjects_%s" % suffix, "subjects", "generate_%s" % suffix, "subjects")
		graph.add_edge("reference_%s" % suffix, "assets", "generate_%s" % suffix, "references")
		graph.add_edge("generate_%s" % suffix, "assets", "batch_%s" % suffix, "in")

	var controller: Node = load(CLOUD_CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var first_plan: Dictionary = controller._requests_for_graph(graph, "generate_a", "openai_image")
	var second_plan: Dictionary = controller._requests_for_graph(
		graph, "generate_b", "openai_image"
	)
	assert_true(first_plan["ok"])
	assert_true(second_plan["ok"])
	var first: Dictionary = first_plan["requests"][0]
	var second: Dictionary = second_plan["requests"][0]
	assert_eq(first["prompt"], "subject_a")
	assert_eq(second["prompt"], "subject_b")
	assert_eq(first["target_width"], 720)
	assert_eq(second["target_width"], 1280)
	assert_eq(first["provider_output_size"], [720, 720])
	assert_eq(second["provider_output_size"], [1280, 720])
	assert_eq(first_plan["provenance_inputs"]["reference_asset_ids"], [first_id])
	assert_eq(second_plan["provenance_inputs"]["reference_asset_ids"], [second_id])
	assert_eq(first_plan["provenance_inputs"]["source_node_id"], "generate_a")
	first["api_key"] = SECRET_SENTINEL
	var snapshot: Dictionary = first_plan["slots"][0]["input_snapshot"]
	assert_false(snapshot.has("run_id"))
	assert_eq(snapshot["source_node_id"], "generate_a")
	assert_eq(snapshot["reference_asset_ids"], [first_id])
	assert_false(JSON.stringify(snapshot).contains(SECRET_SENTINEL))


func test_structured_rows_split_at_model_limit_without_legacy_graph_fields() -> void:
	var graph := GraphScript.new()
	graph.id = "structured_cloud"
	(
		graph
		. add_node(
			ObjectListNodeScript.new(),
			"rows",
			{
				"rows":
				[
					{"id": "row-a", "text": "tower", "count": 5, "enabled": true},
					{"id": "row-b", "text": "barrel", "count": 2, "enabled": true},
					{"id": "row-off", "text": "well", "count": 9, "enabled": false},
				],
			},
			Vector2.ZERO
		)
	)
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 9,
				"seed": -1,
				"extra": {},
			},
			Vector2.ZERO
		)
	)
	graph.add_edge("rows", "subjects", "generate", "subjects")
	var controller: Node = load(CLOUD_CONTROLLER_PATH).new()
	add_child_autofree(controller)

	var all: Dictionary = controller._requests_for_graph(graph, "generate", "openai_image")
	assert_true(all["ok"])
	assert_eq(all["result_count"], 7)
	assert_eq(
		all["requests"].map(func(request: Dictionary) -> int: return request["batch"]), [4, 1, 2]
	)
	assert_eq(
		all["requests"].map(func(request: Dictionary) -> String: return request["prompt"]),
		["tower", "tower", "barrel"]
	)
	for request in all["requests"]:
		assert_eq(request.keys().size(), 14)
		assert_eq(request["target_width"], 1080)
		assert_eq(request["target_height"], 1080)
		assert_eq(request["provider_output_size"], [1088, 1088])
	var graph_data := graph.to_json()
	assert_false(JSON.stringify(graph_data).contains('"items"'))
	assert_false(JSON.stringify(graph_data).contains('"spec"'))
	assert_false(JSON.stringify(graph_data).contains('"images"'))


func test_production_planner_rejects_empty_model_and_prompt_without_defaulting() -> void:
	var graph := GraphScript.new()
	graph.id = "invalid-cloud-input"
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 1,
				"seed": -1,
				"extra": {},
			},
			Vector2.ZERO,
		)
	)
	var controller: Node = load(CLOUD_CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var missing_model: Dictionary = controller._requests_for_graph(
		graph, "generate", "openai_image"
	)
	assert_false(missing_model["ok"])
	assert_eq(
		missing_model["issue"], {"code": "invalid_provider_model", "field": "model_id", "args": {}}
	)
	assert_eq(missing_model["requests"], [])
	var params := graph.get_node_params("generate")
	params["model_id"] = "gpt-image-2"
	assert_true(graph.set_node_params("generate", params))
	var missing_prompt: Dictionary = controller._requests_for_graph(
		graph, "generate", "openai_image"
	)
	assert_false(missing_prompt["ok"])
	assert_eq(missing_prompt["issue"]["code"], "missing_prompt_input")
	assert_eq(missing_prompt["issue"]["field"], "prompt")
	assert_eq(missing_prompt["requests"], [])


func test_real_queue_validates_fields_before_credentials_or_state_changes() -> void:
	var graph := GraphScript.new()
	graph.id = "invalid-cloud-queue"
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 1,
				"seed": -1,
				"extra": {},
			},
			Vector2.ZERO,
		)
	)
	graph.add_node(BatchNodeScript.new(), "batch", {}, Vector2(280, 0))
	var controller: Node = load(CLOUD_CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var status_label := Label.new()
	controller.add_child(status_label)
	controller._status_label = status_label
	controller._queue_graph(graph, "batch", "", "generate", "openai_image")
	assert_string_contains(status_label.text, "invalid_provider_model")
	assert_eq(controller._pending_runs, {})
	assert_eq(graph.get_node_params("batch")["result_slots"], [])
	assert_eq(graph.get_node_params("batch")["request_records"], [])


func test_real_task_failure_materializes_structured_slot_and_request_audit() -> void:
	var graph := GraphScript.new()
	graph.id = "structured-provider-failure"
	(
		graph
		. add_node(
			ObjectListNodeScript.new(),
			"objects",
			{"rows": [{"id": "row", "text": "barrel", "count": 2, "enabled": true}]},
			Vector2.ZERO,
		)
	)
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 1,
				"seed": -1,
				"extra": {},
			},
			Vector2(280, 0),
		)
	)
	graph.add_edge("objects", "subjects", "generate", "subjects")
	var controller: Node = load(CLOUD_CONTROLLER_PATH).new()
	add_child_autofree(controller)
	var canvas := RecordingCanvas.new()
	add_child_autofree(canvas)
	var status_label := Label.new()
	controller.add_child(status_label)
	controller._canvas = canvas
	controller._status_label = status_label
	var planned: Dictionary = controller._requests_for_graph(graph, "generate", "openai_image")
	assert_true(planned["ok"])
	var request: Dictionary = planned["requests"][0]
	var coordinator := GenerationRunCoordinatorScript.new()
	assert_true(coordinator.prepare_full_run(graph, "generate", "batch", planned)["ok"])
	assert_true(coordinator.mark_submitting(graph, "batch", request["request_id"])["ok"])
	controller._coordinator = coordinator
	controller._pending_runs[request["request_id"]] = {
		"graph": graph,
		"request": request,
		"provider_id": "openai_image",
		"provider_name": "GPT Image 2",
		"batch_node_id": "batch",
		"batch_card_id": "",
		"generate_node_id": "generate",
		"planned_slots": planned["slots"],
	}
	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
	var timeout_error: Dictionary = _provider.map_error(
		HTTPRequest.RESULT_TIMEOUT, 0, {"attempts": 1}, request
	)
	controller._on_failed(timeout_error, request["request_id"])
	var saved := GraphScript.from_json(ProjectService.get_graph_data(graph.id))
	var params: Dictionary = saved.get_node_params("batch")
	assert_eq(params["result_slots"].size(), 2)
	assert_eq(
		params["result_slots"].map(func(slot: Dictionary) -> String: return slot["status"]),
		["failed", "failed"],
	)
	assert_eq(params["request_records"][0]["error"], timeout_error)
	assert_string_contains(status_label.text, "timeout")


func test_error_mapping_and_no_generation_retry_policy_are_stable() -> void:
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 401)["code"], "auth_failed")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 429)["code"], "rate_limited")
	assert_eq(
		(
			_provider
			. map_error(
				HTTPRequest.RESULT_SUCCESS, 400, {"provider_code": "content_policy_violation"}
			)["code"]
		),
		"content_policy"
	)
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 500)["code"], "provider_internal")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_TIMEOUT, 0)["code"], "timeout")
	assert_false(_provider.should_retry(HTTPRequest.RESULT_CANT_CONNECT, 0, 0))
	assert_false(_provider.should_retry(HTTPRequest.RESULT_SUCCESS, 503, 0))
	assert_false(_provider.should_retry(HTTPRequest.RESULT_SUCCESS, 503, 1))
	assert_false(_provider.should_retry(HTTPRequest.RESULT_SUCCESS, 429, 0))


func test_provider_result_materializes_complete_provenance_without_secret() -> void:
	var decoded := _provider.decode_success_payload(
		_load_fixture(), _request("materialize", 1, [1, 1])
	)
	decoded["items"][0]["image"].resize(1088, 1088, Image.INTERPOLATE_NEAREST)
	var graph := GraphScript.new()
	graph.id = "graph_openai_contract"
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"resolution_preset": "1080p",
				"orientation": "square",
				"batch_size": 1,
				"seed": -1,
				"extra": {},
			}
		)
	)
	var metadata := [
		{
			"name": "openai_001",
			"actual_seed": null,
			"generation_snapshot":
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"mode": "txt2img",
				"prompt": "wooden barrel",
				"prompt_preset_id": "",
				"prompt_prefix": "",
				"target_width": 1080,
				"target_height": 1080,
				"provider_output_size": [1088, 1088],
				"requested_seed": -1,
				"reference_asset_ids": [],
				"reference_content_sha256s": [],
				"source_row_id": "",
				"extra": {},
			},
		}
	]
	var snapshot: Dictionary = metadata[0]["generation_snapshot"].duplicate(true)
	snapshot["kind"] = "generation"
	snapshot["graph_id"] = graph.id
	snapshot["source_node_id"] = "generate"
	var planned_slots := [
		{
			"slot_id": "slot-openai",
			"request_id": decoded["request_id"],
			"source_row_id": "",
			"input_snapshot": snapshot,
		}
	]
	var plan := {
		"ok": true,
		"requests": [_request("materialize", 1, [1088, 1088])],
		"slots": planned_slots,
		"total_slots": 1,
	}
	var coordinator := GenerationRunCoordinatorScript.new()
	var result: Dictionary = coordinator.prepare_full_run(graph, "generate", "batch_1", plan)
	assert_true(result["ok"])
	var mapped: Dictionary = ProviderResultMapperScript.map_result(
		plan["requests"][0], planned_slots, decoded
	)
	result = coordinator.apply_provider_mapping(
		graph, "batch_1", plan["requests"][0], mapped, AssetLibrary
	)
	assert_true(result["ok"])
	var asset_ids := BatchNodeScript.get_visible_asset_ids(graph.get_node_params("batch_1"))
	var meta: Dictionary = AssetLibrary.get_asset_meta(asset_ids[0])
	var provenance: Dictionary = meta["provenance"]
	var provenance_snapshot: Dictionary = provenance["generation_snapshot"]
	assert_eq(AssetLibrary.get_image(asset_ids[0]).get_size(), Vector2i(1080, 1080))
	assert_eq(provenance_snapshot["provider_id"], "openai_image")
	assert_eq(provenance_snapshot["model_id"], "gpt-image-2")
	assert_eq(provenance_snapshot["prompt"], "wooden barrel")
	assert_eq(provenance_snapshot["source_node_id"], "generate")
	assert_false(provenance.has("cost"))
	assert_false(provenance.has("provider_meta"))
	assert_false(JSON.stringify(meta).contains(SECRET_SENTINEL))


func test_generate_uses_shared_http_worker_decode_and_official_response_metadata() -> void:
	assert_null(_provider.configure({"api_key": SECRET_SENTINEL}))
	var task: PFProviderTaskV2 = _provider.generate(_request("network-generate", 2, [1, 1]))
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
	assert_eq(outcome["value"]["items"].size(), 2)
	assert_true(
		outcome["value"]["items"].all(func(item: Dictionary) -> bool: return item["image"] is Image)
	)
	assert_eq(outcome["value"]["provider_meta"], {})
	assert_false(JSON.stringify(outcome["value"]).contains(SECRET_SENTINEL))


func test_two_references_use_ordered_official_multipart_edit_fields() -> void:
	assert_null(_provider.configure({"api_key": SECRET_SENTINEL}))
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var request := _request("multipart-edit", 2, [1, 1])
	request["mode"] = "img2img"
	request["prompt"] = "combine references"
	request["ref_images"] = [blue, red]
	var multipart := _provider.build_edit_request(request)
	assert_gt(
		multipart.size(),
		blue.save_png_to_buffer().size() + red.save_png_to_buffer().size(),
		"Multipart framing must include both ordered reference images and form fields."
	)
	assert_false(multipart.get_string_from_ascii().contains(SECRET_SENTINEL))

	var task: PFProviderTaskV2 = _provider.generate(request)
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
	assert_eq(outcome["value"]["items"].size(), 2)
	assert_true(
		outcome["value"]["items"].all(func(item: Dictionary) -> bool: return item["image"] is Image)
	)
	assert_eq(outcome["value"]["provider_meta"], {})


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary)
	return parsed


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _request(request_id: String, batch: int, provider_output_size: Array) -> Dictionary:
	return {
		"run_id": "run-%s" % request_id,
		"request_id": request_id,
		"idempotency_key": "idem-%s" % request_id,
		"provider_id": "openai_image",
		"mode": "txt2img",
		"model_id": "gpt-image-2",
		"prompt": "barrel",
		"target_width": 1080,
		"target_height": 1080,
		"provider_output_size": provider_output_size,
		"batch": batch,
		"seed": -1,
		"ref_images": [],
		"extra": {},
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
