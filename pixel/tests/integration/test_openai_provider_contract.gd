extends "res://addons/gut/test.gd"

const ProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const MainScript := preload("res://ui/shell/main.gd")
const Strings := preload("res://ui/shell/strings.gd")
const CloudControllerScript := preload("res://ui/shell/openai_generation_controller.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")

const FIXTURE_PATH := "res://tests/fixtures/providers/openai_image_success.json"
const SECRET_SENTINEL := "sk-pf-m4-v1-contract-secret"

var _provider: PFOpenAIImageProvider
var _host: Node
var _queue: Node


func before_each() -> void:
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_host = Node.new()
	add_child_autofree(_host)
	_provider = ProviderScript.new()
	_provider.attach_request_host(_host)
	get_tree().root.get_node("ProjectService").new_project("M4 V1 Contract")


func after_each() -> void:
	_provider.clear_session_config()
	get_tree().root.get_node("ProviderService").clear_session("openai_image")


func test_ui_provider_catalog_declares_reference_support_without_network_request() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	var registered: PFProvider = ProviderService.get_provider("openai_image")
	assert_true(registered.get_model_descriptor()["capabilities"]["img2img"])
	assert_true(TaskQueue.is_idle())


func test_generation_post_has_no_automatic_network_retry() -> void:
	assert_eq(ProviderScript.MAX_NETWORK_RETRIES, 0)


func test_capabilities_and_persistent_schema_match_contract() -> void:
	assert_eq(_provider.get_id(), "openai_image")
	assert_eq(_provider.get_api_version(), 1)
	var capabilities := _provider.get_capabilities()
	assert_true(capabilities["txt2img"])
	assert_false(capabilities["transparent_bg"])
	assert_true(capabilities["img2img"])
	assert_false(capabilities["native_pixel"])
	assert_eq(capabilities["max_batch"], 4)
	assert_false(capabilities["cost_estimate"])
	var schema := _provider.get_config_schema()
	assert_eq(schema.size(), 1)
	assert_eq(schema[0]["kind"], "password")
	assert_false(schema[0].has("session_only"))


func test_request_body_is_sanitized_and_adapts_target_size() -> void:
	assert_null(_provider.configure({"api_key": SECRET_SENTINEL}))
	var request := {
		"prompt": "wooden barrel",
		"width": 32,
		"height": 32,
		"batch": 9,
	}
	var body := _provider.build_request_body(request)
	assert_eq(body["model"], "gpt-image-2")
	assert_eq(body["quality"], "low")
	assert_eq(body["size"], "1024x1024")
	assert_eq(body["n"], 4)
	assert_eq(body["background"], "opaque")
	assert_eq(body["output_format"], "png")
	assert_string_contains(body["prompt"], "wooden barrel")
	assert_string_contains(body["prompt"], "32x32 true-pixel target")
	assert_false(JSON.stringify(body).contains(SECRET_SENTINEL))

	var task: PFTask = _provider.generate(request)
	assert_false(JSON.stringify(task.payload).contains(SECRET_SENTINEL))
	assert_false(JSON.stringify(ProjectService.current_project.manifest).contains(SECRET_SENTINEL))
	assert_false(JSON.stringify(ProjectService.current_project.graphs).contains(SECRET_SENTINEL))
	assert_ne(SettingsService.get_setting("provider", "api_key", "missing"), SECRET_SENTINEL)


func test_recorded_success_fixture_decodes_to_rgba_result() -> void:
	var payload := _load_fixture()
	var result := _provider.decode_success_payload(payload, {"width": 32, "height": 24})
	assert_true(result["ok"])
	assert_eq(result["images"].size(), 1)
	var image: Image = result["images"][0]
	assert_eq(image.get_size(), Vector2i(1, 1))
	assert_eq(image.get_format(), Image.FORMAT_RGBA8)
	assert_false(result["raw_pixel"])
	assert_eq(result["cost"], -1.0)
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
		graph.add_node(
			ObjectListNodeScript.new(),
			"prompt_%s" % suffix,
			{"items": "subject_%s" % suffix},
			Vector2.ZERO
		)
		graph.add_node(
			SizeSpecNodeScript.new(),
			"size_%s" % suffix,
			{"width": 32 if suffix == "a" else 48, "height": 32, "per_subject": 1},
			Vector2.ZERO
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
					"batch_size": 1,
					"seed": 10,
				},
				Vector2.ZERO
			)
		)
		graph.add_node(BatchNodeScript.new(), "batch_%s" % suffix, {}, Vector2.ZERO)
		graph.add_edge("prompt_%s" % suffix, "items", "generate_%s" % suffix, "items")
		graph.add_edge("size_%s" % suffix, "spec", "generate_%s" % suffix, "spec")
		graph.add_edge("reference_%s" % suffix, "image", "generate_%s" % suffix, "image")
		graph.add_edge("generate_%s" % suffix, "images", "batch_%s" % suffix, "in")

	var controller := CloudControllerScript.new()
	add_child_autofree(controller)
	var first := controller._request_for_graph(graph, "generate_a")
	var second := controller._request_for_graph(graph, "generate_b")
	assert_eq(first["prompt"], "subject_a")
	assert_eq(second["prompt"], "subject_b")
	assert_eq(first["reference_asset_ids"], [first_id])
	assert_eq(second["reference_asset_ids"], [second_id])
	assert_eq(first["width"], 32)
	assert_eq(second["width"], 48)
	assert_eq(first["source_generate_node_id"], "generate_a")
	first["run_id"] = "run-a"
	first["api_key"] = SECRET_SENTINEL
	var snapshot: Dictionary = controller._generation_snapshot(
		first, "openai_image", "gpt-image-2", null, -1.0
	)
	assert_eq(snapshot["run_id"], "run-a")
	assert_eq(snapshot["source_generate_node_id"], "generate_a")
	assert_eq(snapshot["reference_asset_ids"], [first_id])
	assert_false(JSON.stringify(snapshot).contains(SECRET_SENTINEL))


func test_structured_rows_split_at_model_limit_and_retry_only_failed_rows() -> void:
	var graph := GraphScript.new()
	graph.id = "structured_cloud"
	(
		graph
		. add_node(
			ObjectListNodeScript.new(),
			"rows",
			{
				"items": "legacy ignored",
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
	graph.add_node(
		SizeSpecNodeScript.new(),
		"size",
		{"width": 32, "height": 32, "per_subject": 1},
		Vector2.ZERO
	)
	(
		graph
		. add_node(
			AiGenerateNodeScript.new(),
			"generate",
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"batch_size": 9,
				"seed": 50,
			},
			Vector2.ZERO
		)
	)
	graph.add_edge("rows", "items", "generate", "items")
	graph.add_edge("size", "spec", "generate", "spec")
	var controller := CloudControllerScript.new()
	add_child_autofree(controller)

	var all := controller._requests_for_graph(graph, "generate", "openai_image")
	assert_true(all["ok"])
	assert_eq(all["result_count"], 7)
	assert_eq(
		all["requests"].map(func(request: Dictionary) -> int: return request["batch"]), [4, 1, 2]
	)
	assert_eq(
		all["requests"].map(func(request: Dictionary) -> String: return request["source_row_id"]),
		["row-a", "row-a", "row-b"]
	)
	assert_true(
		all["requests"].all(
			func(request: Dictionary) -> bool: return request["source_node_id"] == "rows"
		)
	)
	var retry := controller._requests_for_graph(graph, "generate", "openai_image", ["row-b"])
	assert_eq(retry["requests"].size(), 1)
	assert_eq(retry["requests"][0]["prompt"], "barrel")
	assert_eq(retry["requests"][0]["batch"], 2)


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
	var decoded := _provider.decode_success_payload(_load_fixture(), {"width": 32, "height": 32})
	var graph := GraphScript.new()
	graph.id = "graph_openai_contract"
	graph.add_node(BatchNodeScript.new(), "batch_1", {"label": "OpenAI"}, Vector2.ZERO)
	var metadata := [
		{
			"provider": "openai_image",
			"model": "gpt-image-2",
			"prompt": "wooden barrel",
			"seed": null,
			"cost": decoded["cost"],
			"provider_meta": decoded["provider_meta"],
			"name": "openai_001",
		}
	]
	var result := GraphRunnerScript.new().materialize_provider_batch(
		graph, "batch_1", decoded["images"], metadata, AssetLibrary
	)
	assert_true(result["ok"])
	var meta: Dictionary = AssetLibrary.get_asset_meta(result["asset_ids"][0])
	var provenance: Dictionary = meta["provenance"]
	assert_eq(provenance["provider"], "openai_image")
	assert_eq(provenance["model"], "gpt-image-2")
	assert_eq(provenance["prompt"], "wooden barrel")
	assert_eq(provenance["cost"], -1.0)
	assert_eq(provenance["provider_meta"], {})
	assert_false(JSON.stringify(meta).contains(SECRET_SENTINEL))


func test_generate_uses_shared_http_worker_decode_and_official_response_metadata() -> void:
	assert_null(
		(
			_provider
			. configure(
				{
					"api_key": SECRET_SENTINEL,
					"generation_url":
					OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-success",
					"validation_url": OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-model",
				}
			)
		)
	)
	var task: Variant = _provider.generate(
		{"prompt": "barrel", "width": 32, "height": 32, "batch": 2}
	)
	var outcome := {"status": "pending", "value": null}
	task.finished.connect(
		func(result: Variant) -> void:
			outcome["status"] = "finished"
			outcome["value"] = result
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = error
	)
	_queue.submit(task)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))

	assert_eq(outcome["status"], "finished")
	assert_eq(outcome["value"]["images"].size(), 2)
	assert_eq(outcome["value"]["provider_meta"], {})
	assert_false(JSON.stringify(task.payload).contains(SECRET_SENTINEL))


func test_two_references_use_ordered_official_multipart_edit_fields() -> void:
	assert_null(
		(
			_provider
			. configure(
				{
					"api_key": SECRET_SENTINEL,
					"edit_url": OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-image-edit",
					"validation_url": OS.get_environment("PF_HTTP_MOCK_URL") + "/openai-model",
				}
			)
		)
	)
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var request := {
		"mode": "img2img",
		"model_id": "gpt-image-2",
		"prompt": "combine references",
		"width": 32,
		"height": 32,
		"batch": 2,
		"ref_images": [blue, red],
	}
	var multipart := _provider.build_edit_request(request)
	assert_gt(
		multipart.size(),
		blue.save_png_to_buffer().size() + red.save_png_to_buffer().size(),
		"Multipart framing must include both ordered reference images and form fields."
	)
	assert_false(multipart.get_string_from_ascii().contains(SECRET_SENTINEL))

	var task: PFTask = _provider.generate(request)
	var outcome := {"status": "pending", "value": null}
	task.finished.connect(
		func(result: Variant) -> void:
			outcome["status"] = "finished"
			outcome["value"] = result
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = error
	)
	_queue.submit(task)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "finished")
	assert_eq(outcome["value"]["images"].size(), 2)
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


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
