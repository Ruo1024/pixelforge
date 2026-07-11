extends "res://addons/gut/test.gd"

const MatteDialogScript := preload("res://ui/dialogs/matte_dialog.gd")
const SliceDialogScript := preload("res://ui/dialogs/slice_dialog.gd")
const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
const GraphNodeParamsDialogScript := preload("res://ui/dialogs/graph_node_params_dialog.gd")
const OpenAISessionDialogScript := preload("res://ui/dialogs/openai_session_dialog.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Outliner := preload("res://core/pixel/outliner.gd")


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

	dialog.configure_for_node(
		"graph_test", "objects", ObjectListNodeScript.new(), {"items": "barrel\nfence"}
	)
	assert_eq(dialog.get_param_value("items"), "barrel\nfence")
	assert_true(dialog.set_param_value("items", "tree\nrock\nwell"))
	assert_eq(dialog.get_params()["items"], "tree\nrock\nwell")

	dialog.configure_for_node(
		"graph_test",
		"size",
		SizeSpecNodeScript.new(),
		{"width": 32, "height": 24, "per_subject": 2}
	)
	assert_true(dialog.set_param_value("width", 48))
	assert_eq(dialog.get_params()["width"], 48)
	assert_eq(dialog.get_params()["height"], 24)


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


func _make_source_image() -> Image:
	var image := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2, 4):
		for x in range(2, 4):
			image.set_pixel(x, y, Color.RED)
	return image
