class_name PFCanvasRunEdgePresenter
extends RefCounted

## Translates typed coordinator events into transient edge visuals.
## It never writes Graph, project data, or Undo state.

signal visual_changed

const PFRunEdgeState := preload("res://services/run_edge_state.gd")

var _clock: RefCounted
var _edge_state: PFRunEdgeState
var _coordinator: Variant = null
var _bindings := {}
var _sequence := 0


func _init(clock: RefCounted) -> void:
	_clock = clock
	_edge_state = PFRunEdgeState.new(clock)


func bind_coordinator(coordinator: Variant) -> void:
	if _coordinator != null and _coordinator.run_event.is_connected(_on_run_event):
		_coordinator.run_event.disconnect(_on_run_event)
	_coordinator = coordinator
	if _coordinator != null and not _coordinator.run_event.is_connected(_on_run_event):
		_coordinator.run_event.connect(_on_run_event)


func visual_for_edge(edge: Dictionary, output_params: Dictionary, lod_percent: int) -> Dictionary:
	var endpoints := _execution_endpoints(edge)
	var source_id := String(endpoints.get("source_id", ""))
	var output_id := String(endpoints.get("output_id", ""))
	if (
		source_id.is_empty()
		or output_id.is_empty()
		or String(output_params.get("role", "")) != "current"
		or String(output_params.get("source_node_id", "")) != source_id
	):
		return _idle_visual(lod_percent)
	var binding := _latest_binding(source_id, output_id)
	if binding.is_empty():
		return _idle_visual(lod_percent)
	var run_id := String(binding["run_id"])
	var visual: Dictionary = _edge_state.visual_for_edge(
		run_id, source_id, _edge_id(source_id, output_id), lod_percent
	)
	visual["effect_progress"] = _effect_progress(binding, String(visual.get("state", "idle")))
	return visual


func needs_animation_tick() -> bool:
	return _edge_state.needs_animation_tick()


func clear() -> void:
	for run_id_value in _bindings.keys():
		_edge_state.clear_run(String(run_id_value))
	_bindings.clear()
	visual_changed.emit()


func _on_run_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	var run_id := String(event.get("run_id", ""))
	if run_id.is_empty() or event_type not in ["edge_state", "run_state"]:
		return
	var existing: Dictionary = _bindings.get(run_id, {})
	var source_id := String(event.get("source_node_id", existing.get("source_id", "")))
	var output_id := String(event.get("output_node_id", existing.get("output_id", "")))
	if source_id.is_empty() or output_id.is_empty():
		return
	var state := String(event.get("state", "idle"))
	var started_msec := _now_msec()
	if String(existing.get("state", "")) == state:
		started_msec = int(existing.get("started_msec", started_msec))
	_sequence += 1
	_bindings[run_id] = {
		"run_id": run_id,
		"source_id": source_id,
		"output_id": output_id,
		"state": state,
		"started_msec": started_msec,
		"sequence": _sequence,
	}
	_edge_state.apply_run_state(run_id, source_id, [_edge_id(source_id, output_id)], state, false)
	visual_changed.emit()


func _latest_binding(source_id: String, output_id: String) -> Dictionary:
	var latest := {}
	for value in _bindings.values():
		var binding: Dictionary = value
		if (
			String(binding.get("source_id", "")) == source_id
			and String(binding.get("output_id", "")) == output_id
			and int(binding.get("sequence", -1)) > int(latest.get("sequence", -1))
		):
			latest = binding
	return latest


func _effect_progress(binding: Dictionary, state: String) -> float:
	var durations: Dictionary = PFRunEdgeState.TERMINAL_HOLD_MSEC
	if not durations.has(state):
		return 0.0
	return clampf(
		(
			float(maxi(0, _now_msec() - int(binding.get("started_msec", _now_msec()))))
			/ float(durations[state])
		),
		0.0,
		1.0
	)


func _idle_visual(lod_percent: int) -> Dictionary:
	return _edge_state.visual_for_edge("", "", "", lod_percent)


func _now_msec() -> int:
	if _clock == null or not _clock.has_method("now_msec"):
		return 0
	return int(_clock.call("now_msec"))


static func _execution_endpoints(edge: Dictionary) -> Dictionary:
	var from_data: Array = edge.get("from", [])
	var to_data: Array = edge.get("to", [])
	if (
		from_data.size() < 2
		or to_data.size() < 2
		or String(from_data[1]) != "assets"
		or String(to_data[1]) != "in"
	):
		return {}
	return {"source_id": String(from_data[0]), "output_id": String(to_data[0])}


static func _edge_id(source_id: String, output_id: String) -> String:
	return "%s/assets>%s/in" % [source_id, output_id]
