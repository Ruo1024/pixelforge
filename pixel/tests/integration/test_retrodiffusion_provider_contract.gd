extends "res://addons/gut/test.gd"

const ProviderScript := preload("res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd")
const MainScript := preload("res://ui/shell/main.gd")
const Strings := preload("res://ui/shell/strings.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")

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
	ProviderService.clear_session("retrodiffusion")
	ProviderService._set_validation_state("retrodiffusion", "unconfigured", "")
	CostService.set_monthly_budget(0.0)
	CostService.reset_month_for_tests(CostService.get_month_key())


func test_capabilities_and_schema_match_provider_contract() -> void:
	assert_eq(_provider.get_id(), "retrodiffusion")
	assert_eq(_provider.get_api_version(), 1)
	var capabilities := _provider.get_capabilities()
	assert_true(capabilities["txt2img"])
	assert_true(capabilities["img2img"])
	assert_true(capabilities["transparent_bg"])
	assert_true(capabilities["native_pixel"])
	assert_eq(capabilities["sizes"], [[16, 16], [384, 384]])
	assert_eq(_provider.get_config_schema()[0]["kind"], "password")


func test_request_uses_current_official_fields_and_style_hints() -> void:
	var hinted := (
		_provider
		. build_request_body(
			{
				"prompt": "stone tile",
				"width": 32,
				"height": 32,
				"batch": 8,
				"seed": 123,
				"style": {"provider_hints": {"retrodiffusion": {"style": "rd_tile__single_tile"}}},
				"extra": {"remove_bg": false},
			}
		)
	)

	assert_eq(hinted["prompt_style"], "rd_tile__single_tile")
	assert_eq(hinted["num_images"], 4)
	assert_eq(hinted["seed"], 123)
	assert_false(hinted["remove_bg"])
	assert_false(JSON.stringify(hinted).contains(TEST_SECRET))
	var low_res := _provider.build_request_body(
		{"prompt": "barrel", "width": 16, "height": 16, "style": {}}
	)
	assert_eq(low_res["prompt_style"], "rd_plus__low_res")


func test_recorded_four_image_fixture_decodes_raw_pixels_cost_and_seeds() -> void:
	var result := _provider.decode_success_payload(
		_load_fixture(), {"seed": 50, "width": 128, "height": 128, "style": {}}
	)

	assert_true(result["ok"])
	assert_eq(result["images"].size(), 4)
	assert_true(result["raw_pixel"])
	assert_eq(result["seeds"], [50, 51, 52, 53])
	assert_eq(result["cost"], 1.0)
	assert_eq(result["provider_meta"]["model"], "rd_plus")
	for image in result["images"]:
		assert_eq(image.get_format(), Image.FORMAT_RGBA8)


func test_error_mapping_covers_auth_quota_rate_limit_and_internal() -> void:
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 401)["code"], "auth_failed")
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 429)["code"], "rate_limited")
	assert_eq(
		(
			_provider
			. map_error(
				HTTPRequest.RESULT_SUCCESS,
				400,
				{"response": {"detail": {"code": "insufficient_balance", "message": "low"}}}
			)["code"]
		),
		"quota_exceeded"
	)
	assert_eq(_provider.map_error(HTTPRequest.RESULT_SUCCESS, 500)["code"], "provider_internal")


func test_generate_uses_real_http_task_and_worker_decodes_result() -> void:
	var task: Variant = _provider.generate(
		{"prompt": "barrel", "width": 32, "height": 32, "batch": 1, "seed": 7, "style": {}}
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
	assert_eq(outcome["value"]["images"].size(), 1)
	assert_eq(outcome["value"]["cost"], 0.25)
	assert_true(outcome["value"]["raw_pixel"])
	assert_false(JSON.stringify(task.payload).contains(TEST_SECRET))


func test_result_materializes_complete_provenance_and_documented_estimate() -> void:
	var request := {"batch": 2, "width": 256, "height": 256, "style": {}, "seed": 3}
	assert_eq(_provider.estimate_cost(request), 0.5)
	var decoded := _provider.decode_success_payload(_load_fixture(), request)
	var graph := GraphScript.new()
	graph.id = "graph_retrodiffusion_contract"
	graph.add_node(BatchNodeScript.new(), "batch_1", {"label": "Retro"}, Vector2.ZERO)
	var metadata := []
	for index in range(decoded["images"].size()):
		(
			metadata
			. append(
				{
					"provider": "retrodiffusion",
					"model": decoded["provider_meta"]["model"],
					"prompt": "barrel",
					"seed": decoded["seeds"][index],
					"cost": decoded["cost"] / decoded["images"].size(),
					"provider_meta": decoded["provider_meta"],
					"name": "retro_%d" % index,
				}
			)
		)
	var result := GraphRunnerScript.new().materialize_provider_batch(
		graph, "batch_1", decoded["images"], metadata, AssetLibrary
	)
	assert_true(result["ok"])
	var provenance: Dictionary = AssetLibrary.get_asset_meta(result["asset_ids"][0])["provenance"]
	assert_eq(provenance["provider"], "retrodiffusion")
	assert_eq(provenance["provider_meta"]["prompt_style"], "rd_pro__default")
	assert_false(JSON.stringify(provenance).contains(TEST_SECRET))


func test_verified_graph_runs_through_ui_cloud_provider_flow() -> void:
	ProjectService.new_project("RetroDiffusion UI")
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
	var generate_node := _node_data_for_id(graph_data["nodes"], "generate")
	generate_node["params"]["provider_id"] = "retrodiffusion"
	generate_node["params"]["batch_size"] = 4
	var size_node := _node_data_for_id(graph_data["nodes"], "size")
	size_node["params"]["width"] = 256
	size_node["params"]["height"] = 256
	ProjectService.set_graph_data(graph_id, graph_data, true)
	assert_null(
		(
			ProviderService
			. configure_session(
				"retrodiffusion",
				{
					"api_key": "rdpk-ui-fixture",
					"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/retrodiffusion-success",
				}
			)
		)
	)
	ProviderService._set_validation_state("retrodiffusion", "verified", "Fixture verified")
	CostService.set_monthly_budget(0.1)

	var canvas_items: Array = canvas.export_canvas_data()["items"]
	var batch_item_id := _item_id_for_node(canvas_items, "batch_1")
	var generate_item_id := _item_id_for_node(canvas_items, "generate")
	canvas.select_ids([batch_item_id])
	controller.run_selected_mock_graph()
	var budget_dialog: ConfirmationDialog = controller._openai_flow.get_budget_dialog()
	assert_true(budget_dialog.visible)
	assert_string_contains(budget_dialog.dialog_text, "$1.00")
	assert_eq(
		canvas._items_by_id[generate_item_id]._status_badge, Strings.text("CONTENT_STATUS_WAITING")
	)
	assert_eq(
		canvas._items_by_id[generate_item_id].get_content_control("ExecutionDetail").text,
		budget_dialog.dialog_text
	)
	assert_true(TaskQueue.is_idle())
	budget_dialog.confirmed.emit()
	assert_true(
		await _wait_until(
			func() -> bool: return _status_label(main).text == Strings.STATUS_GRAPH_RUN_DONE % 4,
			3.0
		)
	)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id).size(), 4)
	assert_eq(
		canvas._items_by_id[generate_item_id].get_content_control("ExecutionDetail").text,
		Strings.text("CONTENT_DETAIL_COMPLETE_FORMAT") % 4
	)
	var first_asset_id := String(canvas._get_batch_asset_ids(batch_item_id)[0])
	var provenance: Dictionary = AssetLibrary.get_asset_meta(first_asset_id)["provenance"]
	assert_eq(provenance["provider"], "retrodiffusion")
	assert_eq(provenance["model"], "rd_plus")


func test_cloud_graph_cancel_updates_transient_card_status_without_replacing_results() -> void:
	ProjectService.new_project("RetroDiffusion cancel")
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
	_node_data_for_id(graph_data["nodes"], "generate")["params"]["provider_id"] = ("retrodiffusion")
	var size_node := _node_data_for_id(graph_data["nodes"], "size")
	size_node["params"]["width"] = 256
	size_node["params"]["height"] = 256
	ProjectService.set_graph_data(graph_id, graph_data, true)
	assert_null(
		(
			ProviderService
			. configure_session(
				"retrodiffusion",
				{
					"api_key": "rdpk-cancel-fixture",
					"endpoint": OS.get_environment("PF_HTTP_MOCK_URL") + "/retrodiffusion-slow",
				}
			)
		)
	)
	ProviderService._set_validation_state("retrodiffusion", "verified", "Fixture verified")
	CostService.set_monthly_budget(10.0)
	var items: Array = canvas.export_canvas_data()["items"]
	var batch_item_id := _item_id_for_node(items, "batch_1")
	var generate_item_id := _item_id_for_node(items, "generate")
	var stable_asset_ids: Array = canvas._get_batch_asset_ids(batch_item_id).duplicate()
	canvas.select_ids([batch_item_id])

	controller.run_selected_mock_graph()
	assert_eq(
		canvas._items_by_id[generate_item_id]._status_badge, Strings.text("CONTENT_STATUS_RUNNING")
	)
	assert_eq(
		canvas._items_by_id[generate_item_id].get_content_control("ExecutionDetail").text,
		Strings.text("CONTENT_DETAIL_COST_ESTIMATE_FORMAT") % 0.5
	)
	assert_true(controller.cancel_graph_run(graph_id))
	var canceled_status := Strings.STATUS_PROVIDER_GENERATE_CANCELED_FORMAT % "RetroDiffusion"
	assert_true(
		await _wait_until(func() -> bool: return _status_label(main).text == canceled_status)
	)
	assert_eq(
		canvas._items_by_id[generate_item_id]._status_badge, Strings.text("CONTENT_STATUS_CANCELED")
	)
	assert_eq(
		canvas._items_by_id[generate_item_id].get_content_control("ExecutionDetail").text,
		Strings.text("CONTENT_DETAIL_CANCELED")
	)
	assert_eq(canvas._get_batch_asset_ids(batch_item_id), stable_asset_ids)
	assert_false(canvas.export_canvas_data()["items"][2].has("execution_status"))


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary)
	return parsed


func _node_data_for_id(nodes: Array, node_id: String) -> Dictionary:
	for node in nodes:
		var data: Dictionary = node
		if String(data.get("id", "")) == node_id:
			return data
	return {}


func _item_id_for_node(items: Array, node_id: String) -> String:
	for item in items:
		var data: Dictionary = item
		if String(data.get("node_id", "")) == node_id:
			return String(data.get("id", ""))
	return ""


func _status_label(main: Control) -> Label:
	return main.get_node("Root/BottomBar").get_child(0)


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false
