class_name PFProviderCancelSettlementV2
extends RefCounted

## Provider-side cancellation proof. This class owns wrapper deadlines only; it does
## not write Graph, Output, slots, ledger, UI, or final run state.

const CancelTaskV2Script := preload("res://services/pf_cancel_task_v2.gd")
const DeadlineSchedulerScript := preload("res://infra/cancel_deadline_scheduler.gd")
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

const CANCEL_SETTLE_TIMEOUT_MS := 5000
const REMOTE_CANCEL_TIMEOUT_MS := 3000

var _provider_id := ""
var _scheduler: Variant
var _states := {}


func _init(provider_id: String, scheduler: Variant = null) -> void:
	_provider_id = provider_id
	_scheduler = scheduler if scheduler != null else DeadlineSchedulerScript.new()


func cancel(
	request_id: String,
	generation_task: PFProviderTaskV2,
	queued: bool,
	request_local_stop: Callable,
	request_remote_cancel: Callable = Callable()
) -> PFCancelTaskV2:
	if _states.has(request_id):
		return _states[request_id]["cancel_task"]
	var cancel_task: PFCancelTaskV2 = CancelTaskV2Script.new(request_id, _provider_id)
	_states[request_id] = {
		"phase": "scheduled",
		"generation_task": generation_task,
		"cancel_task": cancel_task,
		"queued": queued,
		"request_local_stop": request_local_stop,
		"request_remote_cancel": request_remote_cancel,
		"billing_update": null,
		"early_local_stopped": false,
	}
	_scheduler.schedule_ms(0, _begin.bind(request_id))
	return cancel_task


func confirm_local_stopped(request_id: String, billing_update: Variant = null) -> bool:
	if not _states.has(request_id):
		return false
	var state: Dictionary = _states[request_id]
	if state["phase"] == "scheduled":
		state["early_local_stopped"] = true
		state["billing_update"] = _copy_variant(billing_update)
		return true
	if state["phase"] != "local_pending":
		return false
	return _finish_local_stop(request_id, billing_update)


func confirm_remote_cancel(request_id: String, confirmed: bool = true) -> bool:
	if not _states.has(request_id):
		return false
	var state: Dictionary = _states[request_id]
	if state["phase"] != "remote_pending":
		return false
	_resolve(request_id, confirmed)
	return true


func get_cancel_task(request_id: String) -> Variant:
	if not _states.has(request_id):
		return null
	return _states[request_id]["cancel_task"]


func _begin(request_id: String) -> void:
	if not _states.has(request_id):
		return
	var state: Dictionary = _states[request_id]
	if state["phase"] != "scheduled":
		return
	if bool(state["queued"]):
		state["phase"] = "local_stopped"
		(state["generation_task"] as PFProviderTaskV2).mark_canceled(request_id)
		_resolve(request_id, true)
		return
	state["phase"] = "local_pending"
	_scheduler.schedule_ms(CANCEL_SETTLE_TIMEOUT_MS, _on_local_timeout.bind(request_id))
	var local_stop: Callable = state["request_local_stop"]
	if local_stop.is_valid():
		local_stop.call()
	if bool(state["early_local_stopped"]):
		_finish_local_stop(request_id, state["billing_update"])


func _finish_local_stop(request_id: String, billing_update: Variant) -> bool:
	var state: Dictionary = _states[request_id]
	if state["phase"] != "local_pending":
		return false
	var provisional := _cancel_result(request_id, false, billing_update)
	if ContractV2.validate_cancel_result(provisional) != null:
		_fail_cancel(request_id)
		return false
	state["billing_update"] = _copy_variant(billing_update)
	state["phase"] = "local_stopped"
	(state["generation_task"] as PFProviderTaskV2).mark_canceled(request_id)
	var remote_cancel: Callable = state["request_remote_cancel"]
	if not remote_cancel.is_valid():
		_resolve(request_id, false)
		return true
	state["phase"] = "remote_pending"
	_scheduler.schedule_ms(REMOTE_CANCEL_TIMEOUT_MS, _on_remote_timeout.bind(request_id))
	remote_cancel.call()
	return true


func _on_local_timeout(request_id: String) -> void:
	if not _states.has(request_id) or _states[request_id]["phase"] != "local_pending":
		return
	_fail_cancel(request_id)


func _on_remote_timeout(request_id: String) -> void:
	if not _states.has(request_id) or _states[request_id]["phase"] != "remote_pending":
		return
	_resolve(request_id, false)


func _resolve(request_id: String, remote_confirmed: bool) -> void:
	var state: Dictionary = _states[request_id]
	if state["phase"] == "terminal":
		return
	state["phase"] = "terminal"
	(state["cancel_task"] as PFCancelTaskV2).resolve(
		_cancel_result(request_id, remote_confirmed, state["billing_update"])
	)


func _fail_cancel(request_id: String) -> void:
	var state: Dictionary = _states[request_id]
	if state["phase"] == "terminal":
		return
	state["phase"] = "terminal"
	var error := _cancel_error(request_id)
	(state["generation_task"] as PFProviderTaskV2).reject(error)
	(state["cancel_task"] as PFCancelTaskV2).reject(error)


func _cancel_result(
	request_id: String, remote_confirmed: bool, billing_update: Variant
) -> Dictionary:
	return {
		"request_id": request_id,
		"local_stopped": true,
		"remote_cancel_confirmed": remote_confirmed,
		"billing_update": _copy_variant(billing_update),
	}


func _cancel_error(request_id: String) -> Dictionary:
	return {
		"code": "cancel_failed",
		"stage": "cancel",
		"provider_id": _provider_id,
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": request_id,
		"attempts": 1,
		"expected_count": 0,
		"received_count": 0,
	}


func _copy_variant(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
