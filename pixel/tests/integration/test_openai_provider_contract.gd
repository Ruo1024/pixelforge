extends "res://addons/gut/test.gd"

const ProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const MainScript := preload("res://ui/shell/main.gd")
const Strings := preload("res://ui/shell/strings.gd")

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


func test_ui_rejects_reference_graph_when_provider_lacks_img2img() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 800)
	add_child_autofree(main)
	await wait_process_frames(2)
	var controller: Node = main.get_node("M21UiController")
	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
	controller.generate_mock_batch()
	await wait_process_frames(2)
	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
	_node_data_for_id(graph_data["nodes"], "generate")["params"]["provider_id"] = "openai_image"
	ProjectService.set_graph_data(graph_id, graph_data, true)
	assert_null(ProviderService.configure_session("openai_image", {"api_key": "sk-local-only"}))
	var canvas_items: Array = canvas.export_canvas_data()["items"]
	canvas.select_ids([_item_id_for_node(canvas_items, "batch_1")])
	controller.run_selected_mock_graph()
	var expected := (
		Strings.text("CONTENT_DETAIL_REFERENCE_UNSUPPORTED_FORMAT") % "OpenAI GPT Image 2"
	)
	assert_string_contains((main.get_node("Root/BottomBar").get_child(0) as Label).text, expected)
	assert_true(TaskQueue.is_idle())


func _node_data_for_id(nodes: Array, node_id: String) -> Dictionary:
	for node_value in nodes:
		if node_value is Dictionary and String(node_value.get("id", "")) == node_id:
			return node_value
	return {}


func _item_id_for_node(items: Array, node_id: String) -> String:
	for item_value in items:
		if item_value is Dictionary and String(item_value.get("node_id", "")) == node_id:
			return String(item_value.get("id", ""))
	return ""


func test_capabilities_and_persistent_schema_match_contract() -> void:
	assert_eq(_provider.get_id(), "openai_image")
	assert_eq(_provider.get_api_version(), 1)
	var capabilities := _provider.get_capabilities()
	assert_true(capabilities["txt2img"])
	assert_true(capabilities["transparent_bg"])
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
	assert_eq(body["background"], "transparent")
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
	assert_eq(result["provider_meta"]["model"], "gpt-image-2")
	assert_eq(result["provider_meta"]["target_size"], [32, 24])


func test_error_mapping_and_single_retry_policy_are_stable() -> void:
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 401)["code"], "auth_failed")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 429)["code"], "rate_limited")
	assert_eq(
		(
			_provider
			. map_error(
				HTTPRequest.RESULT_SUCCESS, 400, {"error": {"code": "content_policy_violation"}}
			)["code"]
		),
		"content_policy"
	)
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 500)["code"], "provider_internal")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_TIMEOUT, 0)["code"], "timeout")
	assert_true(_provider.should_retry(HTTPRequest.RESULT_CANT_CONNECT, 0, 0))
	assert_true(_provider.should_retry(HTTPRequest.RESULT_SUCCESS, 503, 0))
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
	assert_eq(int(provenance["provider_meta"]["usage"]["total_tokens"]), 42)
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
	assert_eq(outcome["value"]["provider_meta"]["background"], "transparent")
	assert_eq(outcome["value"]["provider_meta"]["output_format"], "png")
	assert_false(JSON.stringify(task.payload).contains(SECRET_SENTINEL))


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary)
	return parsed


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
