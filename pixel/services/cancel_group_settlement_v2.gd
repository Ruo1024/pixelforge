class_name PFCancelGroupSettlementV2
extends RefCounted

## Waits for every request-level cancel wrapper before exposing one ordered domain result.

signal settled(outcomes: Array)

var _order := []
var _outcomes := {}
var _sealed := false
var _terminal := false


func add(request_id: String, task: PFCancelTaskV2) -> bool:
	if _sealed or _outcomes.has(request_id) or request_id in _order or task.is_terminal():
		return false
	_order.append(request_id)
	task.resolved.connect(_on_resolved.bind(request_id), CONNECT_ONE_SHOT)
	task.rejected.connect(_on_rejected.bind(request_id), CONNECT_ONE_SHOT)
	return true


func seal() -> void:
	_sealed = true
	_emit_if_complete()


func is_terminal() -> bool:
	return _terminal


func _on_resolved(result: Dictionary, request_id: String) -> void:
	if _outcomes.has(request_id):
		return
	_outcomes[request_id] = {
		"request_id": request_id,
		"status": "resolved",
		"result": result.duplicate(true),
		"error": null,
	}
	_emit_if_complete()


func _on_rejected(error: Dictionary, request_id: String) -> void:
	if _outcomes.has(request_id):
		return
	_outcomes[request_id] = {
		"request_id": request_id,
		"status": "rejected",
		"result": null,
		"error": error.duplicate(true),
	}
	_emit_if_complete()


func _emit_if_complete() -> void:
	if not _sealed or _terminal or _outcomes.size() != _order.size():
		return
	_terminal = true
	var ordered := []
	for request_id in _order:
		ordered.append(_outcomes[request_id].duplicate(true))
	settled.emit(ordered)
