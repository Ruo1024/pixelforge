class_name PFCancelTaskV2
extends RefCounted

## Cancellation completion is separate from generation and has one terminal signal.

signal resolved(result: Dictionary)
signal rejected(error: Dictionary)

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

var _terminal := false
var _request_id := ""
var _provider_id := ""


func _init(request_id: String = "", provider_id: String = "") -> void:
	_request_id = request_id
	_provider_id = provider_id


func resolve(result: Dictionary) -> bool:
	if _terminal:
		return false
	if ContractV2.validate_cancel_result(result) != null:
		return reject(_cancel_error())
	if not _request_id.is_empty() and String(result["request_id"]) != _request_id:
		return reject(_cancel_error())
	_terminal = true
	resolved.emit(result.duplicate(true))
	return true


func reject(error: Dictionary) -> bool:
	if _terminal:
		return false
	var safe_error := error
	if (
		ContractV2.validate_pf_error(error) != null
		or String(error.get("code", "")) != "cancel_failed"
		or String(error.get("stage", "")) != "cancel"
	):
		safe_error = _cancel_error()
	_terminal = true
	rejected.emit(safe_error.duplicate(true))
	return true


func is_terminal() -> bool:
	return _terminal


func _cancel_error() -> Dictionary:
	return {
		"code": "cancel_failed",
		"stage": "cancel",
		"provider_id": _provider_id,
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": _request_id if not _request_id.is_empty() else "cancel-contract",
		"attempts": 1,
		"expected_count": 0,
		"received_count": 0,
	}
