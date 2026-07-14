class_name PFRunEdgeState
extends RefCounted

## Pure, clock-driven presentation state for edges in one run execution closure.
## The service never owns Graph geometry, project data, Undo, or renderer nodes.

const TERMINAL_HOLD_MSEC := {
	"succeeded": 800,
	"partial": 1200,
	"failed": 1200,
	"canceled": 400,
}
const TICKING_STATES := ["queued", "active", "succeeded", "partial", "failed", "canceled"]
const STATE_MAP := {
	"idle": "idle",
	"Ready": "idle",
	"queued": "queued",
	"Queued": "queued",
	"active": "active",
	"Running": "active",
	"Canceling": "canceling",
	"succeeded": "succeeded",
	"Complete": "succeeded",
	"partial": "partial",
	"Partial": "partial",
	"failed": "failed",
	"Failed": "failed",
	"canceled": "canceled",
	"Canceled": "canceled",
}
const VISUAL_TOKENS := {
	"idle_width_px": 2.0,
	"active_outer_width_px": 8.0,
	"active_outer_alpha": 0.28,
	"active_inner_width_px": 2.5,
	"dash_on_px": 14.0,
	"dash_off_px": 10.0,
	"speed_px_per_sec": 90.0,
}

var _clock: RefCounted
var _runs := {}


func _init(clock: RefCounted) -> void:
	_clock = clock


func apply_run_state(
	run_id: String, source_id: String, edge_ids: Array, run_state: String, is_history: bool = false
) -> void:
	if run_id.is_empty() or source_id.is_empty() or is_history:
		_runs.erase(run_id)
		return
	var state := String(STATE_MAP.get(run_state, "idle"))
	var previous: Dictionary = _runs.get(run_id, {})
	var started_msec := _now_msec()
	if String(previous.get("state", "")) == state:
		started_msec = int(previous.get("started_msec", started_msec))
	var edge_set := {}
	for edge_id_value in edge_ids:
		var edge_id := String(edge_id_value)
		if not edge_id.is_empty():
			edge_set[edge_id] = true
	_runs[run_id] = {
		"source_id": source_id,
		"edge_ids": edge_set,
		"state": state,
		"started_msec": started_msec,
	}


func clear_run(run_id: String) -> void:
	_runs.erase(run_id)


func needs_animation_tick() -> bool:
	_expire_terminals()
	for run_value in _runs.values():
		var run: Dictionary = run_value
		if String(run.get("state", "idle")) in TICKING_STATES:
			return true
	return false


func visual_for_edge(
	run_id: String, source_id: String, edge_id: String, lod_percent: int = 100
) -> Dictionary:
	_expire_run(run_id)
	var run: Dictionary = _runs.get(run_id, {})
	if (
		run.is_empty()
		or String(run.get("source_id", "")) != source_id
		or not (run.get("edge_ids", {}) as Dictionary).has(edge_id)
	):
		return _visual("idle", 0, lod_percent)
	return _visual(
		String(run.get("state", "idle")),
		maxi(0, _now_msec() - int(run.get("started_msec", _now_msec()))),
		lod_percent,
	)


func visual_tokens() -> Dictionary:
	return VISUAL_TOKENS.duplicate(true)


func _visual(state: String, elapsed_msec: int, lod_percent: int) -> Dictionary:
	var result := {
		"state": state,
		"effect": "static",
		"phase_px": 0.0,
		"render_mode": "polyline",
		"outer_glow": false,
		"advancing": false,
		"source_pulse": false,
		"success_fade": false,
		"warning": false,
		"error": false,
		"gray_fade": false,
	}
	match state:
		"queued":
			result["effect"] = "source_pulse"
			result["source_pulse"] = true
			result["phase_px"] = fmod(float(elapsed_msec), 1200.0) / 1200.0
		"active":
			result["effect"] = "liquid_flow"
			result["advancing"] = true
			result["outer_glow"] = true
			result["phase_px"] = (
				float(elapsed_msec) * 0.001 * float(VISUAL_TOKENS["speed_px_per_sec"])
			)
		"canceling":
			result["effect"] = "static_warning"
			result["warning"] = true
		"succeeded":
			result["effect"] = "success_fade"
			result["success_fade"] = true
		"partial":
			result["effect"] = "warning_pulse"
			result["warning"] = true
		"failed":
			result["effect"] = "error_pulse"
			result["error"] = true
		"canceled":
			result["effect"] = "gray_fade"
			result["gray_fade"] = true
	if lod_percent == 10 or lod_percent == 25:
		result["render_mode"] = "single_dot"
		result["outer_glow"] = false
	return result


func _expire_terminals() -> void:
	for run_id_value in _runs.keys():
		_expire_run(String(run_id_value))


func _expire_run(run_id: String) -> void:
	if not _runs.has(run_id):
		return
	var run: Dictionary = _runs[run_id]
	var state := String(run.get("state", "idle"))
	if not TERMINAL_HOLD_MSEC.has(state):
		return
	var elapsed_msec := maxi(0, _now_msec() - int(run.get("started_msec", _now_msec())))
	if elapsed_msec >= int(TERMINAL_HOLD_MSEC[state]):
		run["state"] = "idle"
		run["started_msec"] = _now_msec()
		_runs[run_id] = run


func _now_msec() -> int:
	if _clock == null or not _clock.has_method("now_msec"):
		return 0
	return int(_clock.call("now_msec"))
