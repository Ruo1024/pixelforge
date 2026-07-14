extends "res://addons/gut/test.gd"

const MatteDialogScript := preload("res://ui/dialogs/matte_dialog.gd")
const SliceDialogScript := preload("res://ui/dialogs/slice_dialog.gd")
const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
const GraphNodeParamsDialogScript := preload("res://ui/dialogs/graph_node_params_dialog.gd")
const OpenAISessionDialogScript := preload("res://ui/dialogs/openai_session_dialog.gd")
const ProviderSettingsDialogScript := preload("res://ui/dialogs/provider_settings_dialog.gd")
const OpenAIGenerationControllerScript := preload("res://ui/shell/openai_generation_controller.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Outliner := preload("res://core/pixel/outliner.gd")
const Strings := preload("res://ui/shell/strings.gd")


func test_matte_dialog_exposes_core_params() -> void:
	var dialog: ConfirmationDialog = MatteDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)

	dialog.set_source_image(_make_source_image())
	var params: Dictionary = dialog.get_params()

	assert_eq(params["mode"], Matting.MODE_FLOOD)
	assert_eq(int(params["feather"]), Matting.DEFAULT_FEATHER)
	assert_gt(float(params["tolerance"]), 0.0)


func test_slice_dialog_exposes_matte_and_segment_params() -> void:
	var dialog: ConfirmationDialog = SliceDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)

	dialog.set_source_image(_make_source_image())
	var params: Dictionary = dialog.get_params()
	var segment_params: Dictionary = params["segment_params"]

	assert_true(bool(params["matte_first"]))
	assert_eq(int(segment_params["merge_distance"]), 2)
	assert_eq(int(segment_params["min_area"]), 4)


func test_outline_dialog_exposes_core_params() -> void:
	var dialog: ConfirmationDialog = OutlineDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)

	dialog.set_source_image(_make_source_image())
	var params: Dictionary = dialog.get_params()

	assert_eq(params["type"], Outliner.TYPE_OUTER)
	assert_eq(params["corner"], Outliner.CORNER_CROSS)
	assert_eq(params["color"], Color.BLACK)


func test_graph_node_params_dialog_builds_controls_from_node_schema() -> void:
	var dialog: ConfirmationDialog = GraphNodeParamsDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)

	(
		dialog
		. configure_for_node(
			"graph_test",
			"generate",
			AiGenerateNodeScript.new(),
			{
				"provider_id": "mock",
				"model_id": "pixel_mock_v1",
				"target_width": 32,
				"target_height": 24,
				"batch_size": 2,
				"seed": -1,
				"extra": {},
			}
		)
	)
	assert_true(dialog.set_param_value("target_width", 48))
	assert_eq(dialog.get_params()["target_width"], 48)
	assert_eq(dialog.get_params()["target_height"], 24)

	var original_language: String = LocalizationService.current_preference
	LocalizationService.set_language("zh_CN")
	assert_eq(
		dialog.title,
		Strings.text("DIALOG_GRAPH_NODE_PARAMS_TITLE_FORMAT") % Strings.text("NODE_AI_GENERATE")
	)
	assert_eq(dialog._root.get_child(2).get_child(0).text, Strings.text("GRAPH_PARAM_TARGET_WIDTH"))
	assert_eq(dialog.get_ok_button().text, Strings.text("ACTION_APPLY"))
	LocalizationService.set_language(original_language)


func test_graph_node_params_dialog_uses_asset_ref_control() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var asset_id: String = AssetLibrary.register_image(image, "reference")
	var dialog: ConfirmationDialog = GraphNodeParamsDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)
	dialog.configure_for_node(
		"graph_test", "reference", ImageInputNodeScript.new(), {"asset_id": asset_id}
	)
	assert_eq(dialog.get_param_value("asset_id"), asset_id)
	assert_true(dialog.set_param_value("asset_id", "missing-reference"))
	assert_eq(dialog.get_params()["asset_id"], "missing-reference")
	assert_eq(
		dialog._root.get_child(0).get_child(0).text, Strings.text("GRAPH_PARAM_REFERENCE_ASSET")
	)


func test_openai_session_dialog_masks_and_clears_the_session_secret() -> void:
	var dialog: ConfirmationDialog = OpenAISessionDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)
	var configured := []
	dialog.session_configured.connect(func(value: String) -> void: configured.append(value))
	var secret_edit: LineEdit = dialog.get_node("Content/ApiKey")

	assert_true(dialog.is_secret_input())
	dialog.set_api_key_for_test("temporary-session-value")
	dialog.confirmed.emit()

	assert_eq(configured, ["temporary-session-value"])
	assert_eq(secret_edit.text, "")


func test_provider_settings_dialog_masks_schema_password_and_shows_capabilities() -> void:
	var dialog: ConfirmationDialog = ProviderSettingsDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)

	assert_eq(dialog.get_current_provider_id(), "openai_image")
	var secret: LineEdit = dialog.get_field_control("api_key")
	assert_not_null(secret)
	assert_true(secret.secret)
	assert_true(dialog.is_validation_available())
	dialog._select_provider("retrodiffusion")
	assert_false(dialog.is_validation_available())


func test_legacy_openai_session_action_redirects_to_unified_provider_settings() -> void:
	var provider_dialog: ConfirmationDialog = ProviderSettingsDialogScript.new()
	add_child_autofree(provider_dialog)
	var controller: Node = OpenAIGenerationControllerScript.new()
	add_child_autofree(controller)
	var canvas := Control.new()
	add_child_autofree(canvas)
	var status_label := Label.new()
	add_child_autofree(status_label)
	controller.setup(canvas, status_label, null, provider_dialog)
	await wait_process_frames(1)

	controller.configure_session()
	await wait_process_frames(1)
	assert_true(provider_dialog.visible)
	assert_eq(provider_dialog.get_current_provider_id(), "openai_image")
	assert_null(controller.get_node_or_null("OpenAISessionDialog"))


func test_ai_generate_provider_field_does_not_inject_production_mock() -> void:
	var dialog: ConfirmationDialog = GraphNodeParamsDialogScript.new()
	add_child_autofree(dialog)
	await wait_process_frames(1)
	dialog.configure_for_node(
		"graph_test",
		"generate",
		AiGenerateNodeScript.new(),
		{"provider_id": "openai_image", "batch_size": 1, "seed": 1}
	)

	assert_eq(dialog.get_param_value("provider_id"), "openai_image")


func _make_source_image() -> Image:
	var image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2, 4):
		for x in range(2, 4):
			image.set_pixel(x, y, Color.RED)
	return image
