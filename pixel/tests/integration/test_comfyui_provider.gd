extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")
const ProviderScript := preload("res://plugins/bridge_comfyui/comfyui_provider.gd")
const BridgePluginScript := preload("res://plugins/bridge_comfyui/main.gd")
const Templates := preload("res://plugins/bridge_comfyui/workflow_template.gd")


class LegacyComfyRegistrationProbe:
	extends PFProvider

	func get_api_version() -> int:
		return 1


class RegistrationRecorder:
	extends RefCounted
	var provider_calls := 0
	var node_calls := 0

	func register_provider(_provider: Variant) -> void:
		provider_calls += 1

	func register_node_type(_type_id: String, _script: Script) -> void:
		node_calls += 1


func test_template_discovery_and_fill_support_complex_workflows() -> void:
	var complex := {}
	for index in range(35):
		complex[str(index)] = {"class_type": "Passthrough", "inputs": {"value": index}}
	complex["40"] = {"class_type": "KSampler", "inputs": {"seed": 1}}
	complex["41"] = {"class_type": "CLIPTextEncode", "inputs": {"text": "old"}}
	complex["42"] = {
		"class_type": "EmptyLatentImage", "inputs": {"width": 512, "height": 512, "batch_size": 1}
	}
	var slots := Templates.discover_slots(complex)
	assert_eq(slots.size(), 5)
	var template := (
		Templates
		. import_api_workflow(
			complex,
			"community_complex",
			"Community Complex",
			{
				"seed": "40.inputs.seed",
				"prompt": "41.inputs.text",
				"width": "42.inputs.width",
				"height": "42.inputs.height",
				"batch": "42.inputs.batch_size",
			}
		)
	)
	var filled := Templates.fill(
		template, {"prompt": "barrel", "seed": 77, "width": 64, "height": 32, "batch": 3}
	)
	assert_eq(filled["40"]["inputs"]["seed"], 77)
	assert_eq(filled["41"]["inputs"]["text"], "barrel")
	assert_eq(filled["42"]["inputs"]["width"], 64)


func test_ws_progress_parser_and_capabilities_are_stable() -> void:
	var provider: Variant = ProviderScript.new()
	assert_null(provider.call("configure", {"endpoint": "http://127.0.0.1:8188"}))
	assert_eq(
		(
			provider
			. call(
				"parse_ws_message",
				{"type": "progress", "data": {"prompt_id": "p", "value": 5, "max": 10}},
				"p"
			)["progress"]
		),
		0.5
	)
	assert_true(
		(
			provider
			. call(
				"parse_ws_message",
				{"type": "executing", "data": {"prompt_id": "p", "node": null}},
				"p"
			)["done"]
		)
	)
	var capabilities: Dictionary = provider.call("get_capabilities")
	assert_eq(capabilities["max_batch"], 1)
	assert_false(capabilities["native_pixel"])


func test_mock_comfyui_queue_history_view_and_cancel_paths() -> void:
	var endpoint := OS.get_environment("PF_HTTP_MOCK_URL")
	assert_false(endpoint.is_empty())
	var host := Node.new()
	add_child_autofree(host)
	var provider: Variant = ProviderScript.new()
	provider.call("attach_request_host", host)
	assert_null(provider.call("configure", {"endpoint": endpoint}))
	var task: Variant = (
		provider
		. call(
			"generate",
			{
				"prompt": "pixel barrel",
				"negative_prompt": "blur",
				"width": 64,
				"height": 64,
				"batch": 1,
				"seed": 42,
				"extra": {"template_id": "sdxl_pixel_txt2img"},
			}
		)
	)
	var finished := []
	task.finished.connect(func(result: Variant) -> void: finished.append(result))
	TaskQueue.submit(task)
	for _frame in range(120):
		if not finished.is_empty():
			break
		await wait_process_frames(1)
	assert_eq(finished.size(), 1)
	assert_eq(finished[0]["images"].size(), 1)
	assert_false(finished[0]["raw_pixel"])
	assert_eq(finished[0]["seeds"], [42])

	var slow: Variant = provider.call(
		"generate", {"prompt": "slow generation", "width": 64, "height": 64, "seed": 1, "extra": {}}
	)
	var canceled := []
	slow.canceled.connect(func() -> void: canceled.append(true))
	TaskQueue.submit(slow)
	await wait_process_frames(3)
	TaskQueue.cancel(slow.id)
	for _frame in range(30):
		if not canceled.is_empty():
			break
		await wait_process_frames(1)
	assert_eq(canceled.size(), 1)


func test_v1_comfy_provider_is_rejected_and_absent_from_v2_catalog() -> void:
	var service := ProviderServiceScript.new()
	service.load_builtin_plugins = false
	add_child_autofree(service)
	await wait_process_frames(1)
	var provider: PFProvider = LegacyComfyRegistrationProbe.new()
	var result: Dictionary = service.register_provider(provider)
	assert_false(result["ok"])
	assert_eq(result["error"]["code"], "unsupported_provider_api_version")
	assert_false(service.get_provider_ids().has("comfyui"))
	assert_false(service.get_selectable_provider_ids().has("comfyui"))
	assert_false(
		ProviderServiceScript.BUILTIN_PROVIDER_PLUGINS.has("res://plugins/bridge_comfyui/main.gd")
	)
	var dormant_provider: Variant = ProviderScript.new()
	assert_false(dormant_provider is PFProvider)
	assert_eq(dormant_provider.get_api_version(), 1)
	var recorder := RegistrationRecorder.new()
	BridgePluginScript.new()._enter_app(recorder)
	assert_eq(recorder.provider_calls, 0)
	assert_eq(recorder.node_calls, 0)
