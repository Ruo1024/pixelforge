extends Node

const Fixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const MainScene := preload("res://ui/shell/main.tscn")
const Log := preload("res://core/util/log_util.gd")

const WINDOW_SIZE := Vector2i(1440, 900)


func _ready() -> void:
	call_deferred("_capture_workspace")


func _capture_workspace() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		_fail("Usage: capture_beta_workspace.gd -- <output.png> <locale>")
		return
	var output_path := String(args[0])
	var locale := String(args[1])
	if locale not in ["en", "zh_CN"]:
		_fail("Screenshot locale must be en or zh_CN")
		return

	DisplayServer.window_set_size(WINDOW_SIZE)
	SettingsService.set_setting("onboarding", "v1_complete", true, false)
	SettingsService.set_setting("ui", "interface_scale", 1.25, false)
	SettingsService.set_setting("ui", "live_rescale", false, false)
	LocalizationService.apply_language(locale, locale)
	if not _build_project():
		return

	var main := MainScene.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	DisplayServer.window_set_size(WINDOW_SIZE)
	main._on_project_loaded(ProjectService.current_project)
	main.get_node("M21UiController/ImportFlowController").refresh_empty_hint()
	for _frame in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var absolute_output := ProjectSettings.globalize_path(output_path)
	var output_dir := absolute_output.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		_fail("Could not create screenshot directory", {"error": dir_error, "path": output_dir})
		return
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(absolute_output)
	if save_error != OK:
		_fail("Could not save screenshot", {"error": save_error, "path": absolute_output})
		return
	Log.info(
		"Beta workspace screenshot captured",
		{"locale": locale, "path": absolute_output, "size": WINDOW_SIZE}
	)
	get_tree().quit(OK)


func _build_project() -> bool:
	var fixture: Dictionary = Fixture.build()
	ProjectService.new_project(String(fixture["manifest_name"]))
	var graph_data: Dictionary = fixture["graphs"][Fixture.GRAPH_ID]
	var reference_ids := [
		AssetLibrary.register_image(_reference_image(Color.CORNFLOWER_BLUE), "reference_a"),
		AssetLibrary.register_image(_reference_image(Color.DARK_ORANGE), "reference_b"),
	]
	for node in graph_data["nodes"]:
		var node_id := String(node.get("id", ""))
		if node_id == "reference_a":
			node["params"]["asset_id"] = reference_ids[0]
		elif node_id == "reference_b":
			node["params"]["asset_id"] = reference_ids[1]

	var runner := GraphRunnerScript.new()
	for batch_id in ["batch_a", "batch_b"]:
		var result: Dictionary = runner.run_to_batch(
			GraphScript.from_json(graph_data), AssetLibrary, batch_id, false
		)
		if not bool(result.get("ok", false)):
			_fail("Fixture generation failed", result)
			return false
		graph_data = result["graph"]
	ProjectService.set_graph_data(Fixture.GRAPH_ID, graph_data, true)
	ProjectService.set_canvas_data(fixture["canvas"], true)
	return true


func _reference_image(color: Color) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _fail(message: String, detail: Variant = null) -> void:
	Log.error(message, detail)
	get_tree().quit(1)
