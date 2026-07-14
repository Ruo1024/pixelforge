extends "res://addons/gut/test.gd"

const MainScript := preload("res://ui/shell/main.gd")
const GenerationCardViewScript := preload("res://ui/canvas/generation_card_view.gd")
const OutputCardControllerScript := preload("res://ui/canvas/output_card_controller.gd")
const CleanupCardViewScript := preload("res://ui/canvas/cleanup_card_view.gd")
const ErrorPresenterScript := preload("res://ui/dialogs/generation_error_dialog_presenter.gd")
const ErrorPolicyScript := preload("res://services/generation_error_dialog_policy.gd")

const TERMINAL_STEPS := [
	"edge_stopped",
	"successes_saved",
	"failed_slots_updated",
	"safe_errors_recorded",
	"dialog_ready",
]

var _original_language := "en"


func before_each() -> void:
	_original_language = LocalizationService.current_preference
	LocalizationService.set_language("en")
	SettingsService.set_setting("onboarding", "v1_complete", true, false)
	ProjectService.new_project("Runtime language switch")
	AssetLibrary.clear()


func after_each() -> void:
	LocalizationService.set_language(_original_language)


func test_en_zh_en_all_surfaces() -> void:
	var main: Control = MainScript.new()
	main.size = Vector2(1280, 720)
	add_child_autofree(main)
	await wait_process_frames(2)
	main.get_node("RecoveryDialog").hide()
	var shell_id := main.get_instance_id()
	var controller: Node = main.get_node("M21UiController")
	controller.generate_mock_batch()
	await wait_process_frames(2)

	var provider_dialog: ConfirmationDialog = controller.get_node("ProviderSettingsDialog")
	var generation := await _generation_view()
	var output := await _output_view()
	var cleanup := await _cleanup_view()
	var presenter: Node = ErrorPresenterScript.new()
	add_child_autofree(presenter)
	await wait_process_frames(1)
	assert_true(presenter.present(_terminal_summary())["show"])
	var surface_ids := [
		provider_dialog.get_instance_id(),
		generation.get_instance_id(),
		output.get_instance_id(),
		cleanup.get_instance_id(),
		presenter.get_dialog().get_instance_id(),
	]
	var english := _surface_snapshot(main, provider_dialog, generation, output, cleanup, presenter)
	_assert_expected_surface_text(english, "en")

	LocalizationService.set_language("zh_CN")
	await wait_process_frames(2)
	var chinese := _surface_snapshot(main, provider_dialog, generation, output, cleanup, presenter)
	assert_eq(
		main.get_instance_id(), shell_id, "language switching must not rebuild the main scene"
	)
	assert_eq(
		[
			provider_dialog.get_instance_id(),
			generation.get_instance_id(),
			output.get_instance_id(),
			cleanup.get_instance_id(),
			presenter.get_dialog().get_instance_id(),
		],
		surface_ids,
		"all mounted surfaces must refresh in place",
	)
	_assert_expected_surface_text(chinese, "zh_CN")
	for key in english:
		assert_ne(chinese[key], english[key], "%s must visibly refresh in zh_CN" % key)

	LocalizationService.set_language("en")
	await wait_process_frames(2)
	assert_eq(
		_surface_snapshot(main, provider_dialog, generation, output, cleanup, presenter),
		english,
		"the second switch must restore every English surface exactly",
	)


func test_data_stores_code_args_only() -> void:
	var policy := ErrorPolicyScript.new()
	var decision: Dictionary = policy.evaluate(_terminal_summary())
	assert_true(decision["show"])
	var safe_model: Dictionary = decision["model"].duplicate(true)
	for rendered_key in ["title", "reason", "next_step", "label", "text", "locale"]:
		assert_false(safe_model.has(rendered_key), "stored error model leaked %s" % rendered_key)
	assert_eq(safe_model["reason_code"], "auth_failed")

	var persisted := {
		"error": {"code": "auth_failed", "args": {"provider_id": "openai_image"}},
		"run_state": {"code": "Failed", "args": {"affected_count": 1}},
		"project": {"status_code": "generation_failed", "args": {"graph_id": "graph-v2"}},
		"provenance":
		{
			"operation_code": "generation",
			"args": {"provider_id": "openai_image", "model_id": "gpt-image-1"},
		},
	}
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(persisted))
	assert_eq(roundtrip["error"]["code"], "auth_failed")
	assert_eq(roundtrip["error"]["args"]["provider_id"], "openai_image")
	assert_eq(roundtrip["run_state"]["code"], "Failed")
	assert_eq(roundtrip["project"]["status_code"], "generation_failed")
	assert_eq(roundtrip["provenance"]["operation_code"], "generation")
	assert_eq(roundtrip["provenance"]["args"]["model_id"], "gpt-image-1")
	var stored_json := JSON.stringify(roundtrip)
	for locale in ["en", "zh_CN"]:
		for key in ["GEN_ERROR_AUTH_FAILED_REASON", "GEN_ERROR_AUTH_FAILED_NEXT"]:
			var rendered := _catalog_text(locale, key)
			assert_false(
				stored_json.contains(rendered), "%s rendered text leaked into data" % locale
			)

	var english_rendered: Dictionary = policy.render(safe_model, "en")
	var chinese_rendered: Dictionary = policy.render(safe_model, "zh_CN")
	assert_ne(english_rendered["reason"], chinese_rendered["reason"])
	assert_eq(decision["model"], safe_model, "rendering must not mutate the code-only model")


func test_official_names_surrounded_by_localized_copy() -> void:
	var generation := await _generation_view()
	var provider_option: OptionButton = generation.find_child("ProviderOption", true, false)
	var model_option: OptionButton = generation.find_child("ModelOption", true, false)
	assert_eq(provider_option.get_item_text(0), "OpenAI Image · gpt-image-1")
	assert_eq(model_option.get_item_text(0), "OpenAI Image · gpt-image-1")
	var english := _visible_text(generation)
	assert_string_contains(english, "Provider")
	assert_string_contains(english, "Model")

	LocalizationService.set_language("zh_CN")
	await wait_process_frames(1)
	provider_option = generation.find_child("ProviderOption", true, false)
	model_option = generation.find_child("ModelOption", true, false)
	assert_eq(provider_option.get_item_text(0), "OpenAI Image · gpt-image-1")
	assert_eq(model_option.get_item_text(0), "OpenAI Image · gpt-image-1")
	var chinese := _visible_text(generation)
	assert_string_contains(chinese, "提供方")
	assert_string_contains(chinese, "模型")
	assert_ne(chinese, english, "only official names may remain unchanged")


func _surface_snapshot(
	main: Control,
	provider_dialog: ConfirmationDialog,
	generation: Control,
	output: Control,
	cleanup: Control,
	presenter: Node,
) -> Dictionary:
	var file_menu: MenuButton = null
	for child in main.get_node("Root/TopBar/GlobalActions").get_children():
		if child is MenuButton:
			file_menu = child
			break
	assert_not_null(file_menu)
	return {
		"menu": file_menu.text if file_menu != null else "",
		"generation": generation.get_node("Footer/PrimaryAction").text,
		"output": output.get_node("TopRail/Download").text,
		"cleanup": cleanup.get_node("Footer/PrimaryAction").text,
		"provider_settings": provider_dialog.title,
		"error_dialog": presenter.get_dialog().title,
		"example": (main.get_node("Root/BottomBar").get_child(0) as Label).text,
		"tooltip":
		generation.get_node("BodyScroll/BodyGroups/InputSummaryGroup/InputSource0").tooltip_text,
	}


func _assert_expected_surface_text(snapshot: Dictionary, locale: String) -> void:
	assert_eq(snapshot["menu"], _catalog_text(locale, "MENU_FILE"), locale)
	assert_eq(snapshot["generation"], _catalog_text(locale, "GEN_CARD_ACTION_GENERATE"), locale)
	assert_eq(snapshot["output"], _catalog_text(locale, "OUTPUT_ACTION_DOWNLOAD_ALL"), locale)
	assert_eq(snapshot["cleanup"], _catalog_text(locale, "CLEANUP_CARD_ACTION_START"), locale)
	assert_eq(
		snapshot["provider_settings"],
		_catalog_text(locale, "DIALOG_PROVIDER_SETTINGS_TITLE"),
		locale,
	)
	assert_eq(snapshot["error_dialog"], _catalog_text(locale, "GEN_ERROR_TITLE_FAILED"), locale)
	assert_eq(snapshot["example"], _catalog_text(locale, "STATUS_EXAMPLE_OPENED"), locale)
	assert_eq(snapshot["tooltip"], _catalog_text(locale, "GEN_CARD_INPUT_JUMP_HINT"), locale)


func _generation_view() -> Control:
	var descriptor := {
		"provider_id": "openai_image",
		"model_id": "gpt-image-1",
		"display_name": "OpenAI Image · gpt-image-1",
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"native_pixel": false,
			"max_reference_images": 4,
			"max_batch": 4,
			"target_size_constraints":
			{
				"min_width": 1,
				"max_width": 4096,
				"width_step": 1,
				"min_height": 1,
				"max_height": 4096,
				"height_step": 1,
			},
			"supported_modes": ["txt2img", "img2img"],
			"supports_seed": true,
		},
		"dynamic_params": [],
		"is_default": true,
	}
	var snapshot := {
		"params":
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-1",
			"target_width": 32,
			"target_height": 32,
			"batch_size": 4,
			"seed": 7,
			"extra": {},
		},
		"descriptor": descriptor,
		"descriptors": [descriptor],
		"prompt": "forest shrine",
		"prefix": "",
		"rows": [],
		"input_sources": [{"id": "prompt", "summary": "forest shrine"}],
		"run": {"state": "Ready", "errors": []},
	}
	var view: Control = GenerationCardViewScript.new()
	view.size = Vector2(400, 520)
	add_child_autofree(view)
	view.configure(snapshot)
	await wait_process_frames(1)
	return view


func _output_view() -> Control:
	var slots := []
	for index in range(4):
		(
			slots
			. append(
				{
					"slot_id": "slot-%d" % index,
					"status": "succeeded",
					"asset_id": "asset-%d" % index,
					"detached": false,
				}
			)
		)
	var view: Control = OutputCardControllerScript.new()
	view.size = Vector2(600, 488)
	add_child_autofree(view)
	(
		view
		. configure(
			{
				"state": "Complete",
				"role": "current",
				"source_node_id": "generate",
				"result_slots": slots,
			}
		)
	)
	await wait_process_frames(1)
	return view


func _cleanup_view() -> Control:
	var view: Control = CleanupCardViewScript.new()
	view.size = Vector2(420, 680)
	add_child_autofree(view)
	(
		view
		. configure(
			{
				"params": {"preset_id": "cleanup-16bit-db32", "settings": {}},
				"run": {"state": "Ready"},
				"input": {"kind": "Output", "count": 2, "target": "32×32"},
			}
		)
	)
	await wait_process_frames(1)
	return view


func _terminal_summary() -> Dictionary:
	return {
		"mode": "terminal",
		"run_id": "runtime-language-%d" % Time.get_ticks_usec(),
		"settled": true,
		"succeeded_count": 0,
		"failed_slots":
		[
			{
				"slot_id": "slot-auth",
				"status": "failed",
				"error":
				{
					"code": "auth_failed",
					"stage": "provider",
					"provider_id": "openai_image",
					"retryable": false,
					"retry_after_seconds": null,
					"status_code": 401,
					"request_id": "request-safe-12345678",
					"attempts": 1,
					"expected_count": 1,
					"received_count": 0,
				},
			}
		],
		"terminal_steps": TERMINAL_STEPS.duplicate(),
	}


func _catalog_text(locale: String, key: String) -> String:
	var path := "res://assets/i18n/%s.json" % locale
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	return String(catalog.get(key, ""))


func _visible_text(root: Node) -> String:
	var parts := PackedStringArray()
	_collect_visible_text(root, parts)
	return "\n".join(parts)


func _collect_visible_text(node: Node, parts: PackedStringArray) -> void:
	if node is CanvasItem and not node.visible:
		return
	if node is Label or node is Button:
		if not String(node.text).is_empty():
			parts.append(String(node.text))
	for child in node.get_children():
		_collect_visible_text(child, parts)
