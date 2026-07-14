class_name PFCleanupCancelAdapter
extends RefCounted

## Local cleanup cancellation proof: worker stop, operation terminal, then wrapper.

const CancelTaskScript := preload("res://services/pf_cancel_task_v2.gd")
const DeadlineSchedulerScript := preload("res://infra/cancel_deadline_scheduler.gd")
const TIMEOUT_MS := 5000

var _scheduler: Variant
var _states := {}


func _init(scheduler: Variant = null) -> void:
	_scheduler = scheduler if scheduler != null else DeadlineSchedulerScript.new()


func cancel(request_id: String, operation_task: PFTask, stop_worker: Callable) -> PFCancelTaskV2:
	if _states.has(request_id):
		return _states[request_id]["wrapper"]
	var wrapper: PFCancelTaskV2 = CancelTaskScript.new(request_id, "")
	_states[request_id] = {"phase": "stopping", "task": operation_task, "wrapper": wrapper}
	_scheduler.schedule_ms(TIMEOUT_MS, _timeout.bind(request_id))
	if stop_worker.is_valid():
		stop_worker.call()
	return wrapper


func confirm_worker_stopped(request_id: String) -> bool:
	if not _states.has(request_id) or _states[request_id]["phase"] != "stopping":
		return false
	var state: Dictionary = _states[request_id]
	state["phase"] = "terminal"
	(state["task"] as PFTask).canceled.emit()
	(state["wrapper"] as PFCancelTaskV2).resolve({
		"request_id": request_id,
		"local_stopped": true,
		"remote_cancel_confirmed": true,
		"billing_update": null,
	})
	return true


func _timeout(request_id: String) -> void:
	if not _states.has(request_id) or _states[request_id]["phase"] != "stopping":
		return
	var state: Dictionary = _states[request_id]
	state["phase"] = "terminal"
	var error := {
		"code": "cancel_failed", "stage": "cancel", "provider_id": "",
		"retryable": false, "retry_after_seconds": null, "status_code": null,
		"request_id": request_id, "attempts": 1, "expected_count": 0, "received_count": 0,
	}
	(state["task"] as PFTask).failed.emit(error.duplicate(true))
	(state["wrapper"] as PFCancelTaskV2).reject(error)
