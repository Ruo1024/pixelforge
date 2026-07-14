extends "res://addons/gut/test.gd"

const RUN_EDGE_STATE_PATH := "res://services/run_edge_state.gd"
const RENDERER_PATH := "res://ui/canvas/canvas_graph_edge_renderer.gd"
const FakeClock := preload("res://tests/fixtures/time/fake_clock.gd")


func test_idle_queued_running_canceling_terminal() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["state"], "idle")
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Queued")
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["effect"], "source_pulse")
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["state"], "active")
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Canceling")
	var canceling: Dictionary = state.visual_for_edge("run-a", "source-a", "edge-a")
	assert_eq(canceling["effect"], "static_warning")
	assert_false(canceling["advancing"])
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Canceled")
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["effect"], "gray_fade")
	state.apply_run_state("run-history", "source-a", ["edge-a"], "Running", true)
	assert_eq(state.visual_for_edge("run-history", "source-a", "edge-a")["state"], "idle")


func test_concurrent_runs_are_isolated() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	clock.advance_msec(250)
	state.apply_run_state("run-b", "source-b", ["edge-b"], "Running")
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["phase_px"], 22.5)
	assert_eq(state.visual_for_edge("run-b", "source-b", "edge-b")["phase_px"], 0.0)
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-b")["state"], "idle")
	assert_eq(state.visual_for_edge("run-a", "source-b", "edge-a")["state"], "idle")


func test_idle_stops_tick() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	assert_false(state.needs_animation_tick())
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Queued")
	assert_true(state.needs_animation_tick())
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	assert_true(state.needs_animation_tick())
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Canceling")
	assert_false(state.needs_animation_tick())
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Complete")
	assert_true(state.needs_animation_tick())
	clock.advance_msec(800)
	assert_false(state.needs_animation_tick())
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["state"], "idle")


func test_clock_injected_and_no_wall_clock() -> void:
	var source := FileAccess.get_file_as_string(RUN_EDGE_STATE_PATH)
	var renderer_source := FileAccess.get_file_as_string(RENDERER_PATH)
	assert_true(source.contains("_clock"))
	assert_false(source.contains("Time."))
	assert_false(source.contains("get_ticks"))
	assert_false(renderer_source.contains("Time."))
	assert_false(renderer_source.contains("get_ticks"))
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	clock.advance_msec(100)
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["phase_px"], 9.0)


func test_terminal_hold_durations() -> void:
	var durations := {"Complete": 800, "Partial": 1200, "Failed": 1200, "Canceled": 400}
	for run_state in durations:
		var clock := FakeClock.new()
		var state: Variant = _new_state(clock)
		if state == null:
			return
		state.apply_run_state("run-a", "source-a", ["edge-a"], run_state)
		clock.advance_msec(int(durations[run_state]) - 1)
		assert_ne(state.visual_for_edge("run-a", "source-a", "edge-a")["state"], "idle")
		clock.advance_msec(1)
		assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["state"], "idle")


func test_exact_visual_tokens_and_speed() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	var tokens: Dictionary = state.visual_tokens()
	assert_eq(tokens["idle_width_px"], 2.0)
	assert_eq(tokens["active_outer_width_px"], 8.0)
	assert_eq(tokens["active_outer_alpha"], 0.28)
	assert_eq(tokens["active_inner_width_px"], 2.5)
	assert_eq(tokens["dash_on_px"], 14.0)
	assert_eq(tokens["dash_off_px"], 10.0)
	assert_eq(tokens["speed_px_per_sec"], 90.0)
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	clock.advance_msec(1000)
	assert_eq(state.visual_for_edge("run-a", "source-a", "edge-a")["phase_px"], 90.0)


func test_cancel_partial_failed_canceled_sequences() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	var expected := {
		"Canceling": "static_warning",
		"Partial": "warning_pulse",
		"Failed": "error_pulse",
		"Canceled": "gray_fade",
	}
	for run_state in expected:
		state.apply_run_state("run-a", "source-a", ["edge-a"], run_state)
		var visual: Dictionary = state.visual_for_edge("run-a", "source-a", "edge-a")
		assert_eq(visual["effect"], expected[run_state])
		assert_false(visual["advancing"])
		assert_eq(_truthy_effect_count(visual), 1)


func test_low_lod_dot_and_no_geometry_mutation() -> void:
	var clock := FakeClock.new()
	var state: Variant = _new_state(clock)
	if state == null:
		return
	state.apply_run_state("run-a", "source-a", ["edge-a"], "Running")
	var geometry := {
		"start": Vector2(10, 20),
		"end": Vector2(110, 60),
		"hit_distance": 8.0,
		"camera": Vector2(4, 5),
		"bounds": Rect2(0, 0, 120, 80),
	}.duplicate(true)
	var before := geometry.duplicate(true)
	for lod_percent in [10, 25]:
		var visual: Dictionary = state.visual_for_edge(
			"run-a", "source-a", "edge-a", lod_percent
		)
		assert_eq(visual["render_mode"], "single_dot")
		assert_false(visual["outer_glow"])
	assert_eq(geometry, before)
	var renderer: Script = load(RENDERER_PATH)
	var points_before: PackedVector2Array = renderer._bezier_points(geometry["start"], geometry["end"])
	state.visual_for_edge("run-a", "source-a", "edge-a")
	var points_after: PackedVector2Array = renderer._bezier_points(geometry["start"], geometry["end"])
	assert_eq(points_after, points_before)


func _new_state(clock: RefCounted) -> Variant:
	var script: Script = load(RUN_EDGE_STATE_PATH)
	assert_not_null(script, "B7-4 requires the pure run edge state service")
	return null if script == null else script.new(clock)


func _truthy_effect_count(visual: Dictionary) -> int:
	var count := 0
	for key in ["source_pulse", "advancing", "success_fade", "warning", "error", "gray_fade"]:
		if bool(visual.get(key, false)):
			count += 1
	return count
