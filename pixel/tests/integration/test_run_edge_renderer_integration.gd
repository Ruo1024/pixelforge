extends "res://addons/gut/test.gd"

const PRESENTER_PATH := "res://ui/canvas/canvas_run_edge_presenter.gd"
const RENDERER_PATH := "res://ui/canvas/canvas_graph_edge_renderer.gd"
const CANVAS_PATH := "res://ui/canvas/infinite_canvas.gd"
const FakeClock := preload("res://tests/fixtures/time/fake_clock.gd")


class FakeCoordinator:
	extends RefCounted
	signal run_event(event: Dictionary)

	func publish(event: Dictionary) -> void:
		run_event.emit(event)


func test_typed_coordinator_event_drives_only_current_execution_edge() -> void:
	var clock := FakeClock.new()
	var coordinator := FakeCoordinator.new()
	var presenter: Variant = _new_presenter(clock)
	if presenter == null:
		return
	presenter.bind_coordinator(coordinator)
	coordinator.publish(_event("run-a", "source-a", "output-a", "Queued"))
	var edge := _edge("source-a", "output-a")
	var current := _output_params("current", "source-a")
	assert_eq(presenter.visual_for_edge(edge, current, 100)["effect"], "source_pulse")
	assert_eq(
		presenter.visual_for_edge(_edge("source-a", "output-other"), current, 100)["state"], "idle"
	)
	assert_eq(
		presenter.visual_for_edge(edge, _output_params("history", "source-a"), 100)["state"],
		"idle",
		"history Output edges never enter execution presentation"
	)
	coordinator.publish(_event("run-a", "source-a", "output-a", "Running"))
	coordinator.publish({"type": "run_state", "run_id": "run-a", "state": "Canceling"})
	var canceling: Dictionary = presenter.visual_for_edge(edge, current, 100)
	assert_eq(canceling["effect"], "static_warning")
	assert_false(canceling["advancing"])


func test_concurrent_typed_runs_keep_source_output_and_phase_isolated() -> void:
	var clock := FakeClock.new()
	var coordinator := FakeCoordinator.new()
	var presenter: Variant = _new_presenter(clock)
	if presenter == null:
		return
	presenter.bind_coordinator(coordinator)
	coordinator.publish(_event("run-a", "source-a", "output-a", "Running"))
	clock.advance_msec(250)
	coordinator.publish(_event("run-b", "source-b", "output-b", "Running"))
	assert_eq(
		(
			presenter
			. visual_for_edge(
				_edge("source-a", "output-a"), _output_params("current", "source-a"), 100
			)["phase_px"]
		),
		22.5
	)
	assert_eq(
		(
			presenter
			. visual_for_edge(
				_edge("source-b", "output-b"), _output_params("current", "source-b"), 100
			)["phase_px"]
		),
		0.0
	)
	assert_eq(
		(
			presenter
			. visual_for_edge(
				_edge("source-a", "output-b"), _output_params("current", "source-b"), 100
			)["state"]
		),
		"idle"
	)


func test_canvas_binds_typed_events_and_ticks_only_while_animation_needs_it() -> void:
	var canvas_script: Script = load(CANVAS_PATH)
	var source := FileAccess.get_file_as_string(CANVAS_PATH)
	var clock := FakeClock.new()
	var coordinator := FakeCoordinator.new()
	var canvas: Variant = canvas_script.new()
	add_child_autofree(canvas)
	canvas.configure_run_edge_renderer(coordinator, clock)
	assert_false(canvas._run_edge_presenter.needs_animation_tick())
	coordinator.publish(_event("run-a", "source-a", "output-a", "Queued"))
	assert_true(canvas._run_edge_presenter.needs_animation_tick())
	coordinator.publish(_event("run-a", "source-a", "output-a", "Canceling"))
	assert_false(canvas._run_edge_presenter.needs_animation_tick())
	assert_true(source.contains("_run_edge_presenter.needs_animation_tick()"))
	assert_true(source.contains("GraphEdgeInteraction.draw_edges"))


func test_renderer_builds_exact_active_layers_without_mutating_geometry() -> void:
	var renderer: Script = load(RENDERER_PATH)
	var points: PackedVector2Array = renderer._bezier_points(Vector2(10, 20), Vector2(210, 80))
	var before: PackedVector2Array = points.duplicate()
	var visual := {
		"state": "active",
		"effect": "liquid_flow",
		"phase_px": 22.5,
		"render_mode": "polyline",
		"outer_glow": true,
	}
	var commands: Array = renderer._run_visual_commands(points, visual, Color.WHITE)
	assert_eq(points, before)
	assert_eq(commands[0]["kind"], "polyline")
	assert_eq(commands[0]["width"], 8.0)
	assert_almost_eq(commands[0]["color"].a, 0.28, 0.0001)
	assert_eq(commands[1]["kind"], "dashes")
	assert_eq(commands[1]["width"], 2.5)
	assert_eq(commands[1]["dash_on"], 14.0)
	assert_eq(commands[1]["dash_off"], 10.0)
	assert_eq(commands[1]["phase_px"], 22.5)


func test_low_lod_changes_only_overlay_to_one_dot() -> void:
	var renderer: Script = load(RENDERER_PATH)
	var points: PackedVector2Array = renderer._bezier_points(Vector2(10, 20), Vector2(210, 80))
	var before: PackedVector2Array = points.duplicate()
	var low_lod := {
		"state": "active",
		"effect": "liquid_flow",
		"phase_px": 22.5,
		"render_mode": "single_dot",
		"outer_glow": false,
		"advancing": true,
	}
	var commands: Array = renderer._run_visual_commands(points, low_lod, Color.WHITE)
	assert_eq(commands.size(), 1)
	assert_eq(commands[0]["kind"], "dot")
	assert_ne(commands[0]["position"], points[0], "active low-LOD dot advances source to target")
	assert_eq(points, before)
	assert_eq(renderer.EDGE_HIT_DISTANCE, 8.0)
	assert_eq(
		renderer._bezier_points(Vector2(10, 20), Vector2(210, 80)),
		before,
		"LOD presentation must not change endpoints or hit geometry"
	)


func test_renderer_and_presenter_use_injected_clock_without_persistence_writes() -> void:
	var presenter_source := FileAccess.get_file_as_string(PRESENTER_PATH)
	var renderer_source := FileAccess.get_file_as_string(RENDERER_PATH)
	var canvas_source := FileAccess.get_file_as_string(CANVAS_PATH)
	for source in [presenter_source, renderer_source]:
		assert_false(source.contains("Time."))
		assert_false(source.contains("get_ticks"))
		assert_false(source.contains("set_node_params"))
		assert_false(source.contains("UndoService"))
	assert_true(presenter_source.contains("PFRunEdgeState"))
	assert_true(presenter_source.contains("run_event.connect"))
	assert_true(renderer_source.contains("run_edge_presenter.visual_for_edge"))
	assert_true(canvas_source.contains("_run_edge_presenter"))


func _new_presenter(clock: RefCounted) -> Variant:
	var script: Script = load(PRESENTER_PATH)
	assert_not_null(script, "renderer integration requires the typed run-edge presenter")
	return null if script == null else script.new(clock)


func _event(run_id: String, source_id: String, output_id: String, state: String) -> Dictionary:
	return {
		"type": "edge_state",
		"run_id": run_id,
		"source_node_id": source_id,
		"output_node_id": output_id,
		"state": state,
	}


func _edge(source_id: String, output_id: String) -> Dictionary:
	return {"from": [source_id, "assets"], "to": [output_id, "in"]}


func _output_params(role: String, source_id: String) -> Dictionary:
	return {"role": role, "source_node_id": source_id}
