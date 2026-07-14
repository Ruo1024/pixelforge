extends "res://addons/gut/test.gd"

const Fixture := preload("res://tests/fixtures/generators/beta_large_workspace_fixture.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const MockHarness := preload("res://tests/fixtures/generators/mock_generation_harness.gd")
const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")

const PROJECT_PATH := "user://tests/beta_0_5_large_workspace.pxproj"
const STEP_BUDGET_MSEC := 10000


func before_each() -> void:
	ProjectService.new_project("Beta 0.5 large workspace")


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROJECT_PATH))


func test_two_hundred_module_workspace_is_deterministic_runnable_and_roundtrips() -> void:
	var started := Time.get_ticks_msec()
	var fixture: Dictionary = Fixture.build()
	var build_msec := Time.get_ticks_msec() - started
	assert_eq(fixture, Fixture.build())
	var graph_data: Dictionary = fixture["graphs"][Fixture.GRAPH_ID]
	assert_eq(graph_data["nodes"].size(), 200)
	assert_eq(graph_data["edges"].size(), 160)
	assert_eq(graph_data["nodes"].size(), Fixture.BRANCH_COUNT * Fixture.NODES_PER_BRANCH)
	assert_eq(GraphScript.from_json(graph_data).validate_edges(), [])

	started = Time.get_ticks_msec()
	var canvas: Control = add_child_autofree(CanvasScript.new())
	canvas.size = Vector2(1440, 900)
	canvas.load_canvas_data(fixture["canvas"])
	var load_msec := Time.get_ticks_msec() - started
	assert_eq(canvas.get_item_count(), 208)
	started = Time.get_ticks_msec()
	assert_true(canvas._focus_item_ids(canvas._items_by_id.keys()))
	var fit_msec := Time.get_ticks_msec() - started
	assert_lte(canvas.camera_zoom, 0.25)

	var graph := GraphScript.from_json(graph_data)
	var run := MockHarness.run(graph, AssetLibrary, "generate_00", "output_run_00")
	assert_true(run["ok"])
	assert_eq(BatchNodeScript.get_visible_asset_ids(graph.get_node_params("batch_00")), [])
	assert_eq(
		BatchNodeScript.get_visible_asset_ids(graph.get_node_params("output_run_00")).size(), 2
	)
	assert_eq(BatchNodeScript.get_visible_asset_ids(graph.get_node_params("batch_01")), [])
	ProjectService.set_graphs_data({Fixture.GRAPH_ID: graph.to_json()})
	ProjectService.set_canvas_data(canvas.export_canvas_data())

	started = Time.get_ticks_msec()
	assert_eq(ProjectService.save_project(PROJECT_PATH), OK)
	var save_msec := Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	assert_eq(ProjectService.open_project(PROJECT_PATH), OK)
	var reopen_msec := Time.get_ticks_msec() - started
	assert_eq(ProjectService.get_graph_data(Fixture.GRAPH_ID)["nodes"].size(), 201)
	assert_eq(ProjectService.current_project.canvas["items"].size(), 208)
	assert_lt(build_msec, STEP_BUDGET_MSEC)
	assert_lt(load_msec, STEP_BUDGET_MSEC)
	assert_lt(fit_msec, STEP_BUDGET_MSEC)
	assert_lt(save_msec, STEP_BUDGET_MSEC)
	assert_lt(reopen_msec, STEP_BUDGET_MSEC)
	gut.p(
		(
			"beta-0.5-large build=%dms load=%dms fit=%dms save=%dms reopen=%dms"
			% [build_msec, load_msec, fit_msec, save_msec, reopen_msec]
		)
	)
