extends "res://addons/gut/test.gd"

const Fixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")
const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func before_each() -> void:
	ProjectService.new_project("Beta 0.3 Journey")


func test_two_branch_stage_workspace_runs_saves_and_reopens_with_results() -> void:
	var fixture: Dictionary = Fixture.build()
	var graph_data: Dictionary = fixture["graphs"][Fixture.GRAPH_ID]
	var reference_ids := [
		AssetLibrary.register_image(
			_reference_image(Color.CORNFLOWER_BLUE), "reference_a", {"origin": "imported"}
		),
		AssetLibrary.register_image(
			_reference_image(Color.DARK_ORANGE), "reference_b", {"origin": "imported"}
		),
	]
	for node in graph_data["nodes"]:
		if String(node.get("id", "")) == "reference_a":
			node["params"]["asset_id"] = reference_ids[0]
		elif String(node.get("id", "")) == "reference_b":
			node["params"]["asset_id"] = reference_ids[1]
	ProjectService.set_graph_data(Fixture.GRAPH_ID, graph_data, true)
	ProjectService.set_canvas_data(fixture["canvas"], true)
	var runner := GraphRunnerScript.new()
	var first_run: Dictionary = runner.run_to_batch(
		GraphScript.from_json(ProjectService.get_graph_data(Fixture.GRAPH_ID)),
		AssetLibrary,
		"batch_a"
	)
	assert_true(first_run["ok"])
	var first_graph := GraphScript.from_json(first_run["graph"])
	assert_eq(
		BatchNodeScript.get_visible_asset_ids(first_graph.get_node_params("batch_a")).size(), 4
	)
	ProjectService.set_graph_data(Fixture.GRAPH_ID, first_run["graph"], true)
	var second_run: Dictionary = runner.run_to_batch(
		GraphScript.from_json(ProjectService.get_graph_data(Fixture.GRAPH_ID)),
		AssetLibrary,
		"batch_b"
	)
	assert_true(second_run["ok"])
	var second_graph := GraphScript.from_json(second_run["graph"])
	assert_eq(
		BatchNodeScript.get_visible_asset_ids(second_graph.get_node_params("batch_b")).size(), 4
	)
	ProjectService.set_graph_data(Fixture.GRAPH_ID, second_run["graph"], true)

	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(1280, 720)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	canvas.load_canvas_data(ProjectService.current_project.canvas)
	assert_eq(canvas.get_item_count(), 12)
	assert_eq(canvas._items_by_id["batch_a_item"].asset_ids.size(), 4)
	assert_eq(canvas._items_by_id["batch_b_item"].asset_ids.size(), 4)
	canvas.set_camera_zoom(0.1)
	assert_eq(canvas.camera_zoom, 0.1)
	ProjectService.set_canvas_data(canvas.export_canvas_data(), true)
	var path := "user://tests/beta_0_3_journey.pxproj"
	assert_eq(ProjectService.save_project(path), OK)
	assert_eq(ProjectService.open_project(path), OK)
	assert_eq(ProjectService.current_project.canvas["camera"]["zoom"], 0.1)
	assert_eq(ProjectService.current_project.canvas["items"].filter(_is_frame).size(), 2)
	var reopened: PFGraph = GraphScript.from_json(ProjectService.get_graph_data(Fixture.GRAPH_ID))
	assert_eq(BatchNodeScript.get_visible_asset_ids(reopened.get_node_params("batch_a")).size(), 4)
	assert_eq(BatchNodeScript.get_visible_asset_ids(reopened.get_node_params("batch_b")).size(), 4)


func _reference_image(color: Color) -> Image:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _is_frame(item: Dictionary) -> bool:
	return String(item.get("type", "")) == "frame"
