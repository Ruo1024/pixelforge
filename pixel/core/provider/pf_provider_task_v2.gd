class_name PFProviderTaskV2
extends RefCounted

## Provider-only asynchronous boundary. Terminal emission is idempotent by construction.

signal progress(value: Dictionary)
signal completed(result: Dictionary)
signal failed(error: Dictionary)
signal canceled(request_id: String)

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

var _terminal := false
var _request := {}
var _allowed_meta_keys: Array = []
var _expected_total := 0
var _last_completed := 0
var _last_ratio := -1.0
var _last_phase_index := -1
var _submitting_emitted := false


func _init(request: Dictionary = {}, allowed_meta_keys: Array = []) -> void:
	_request = request.duplicate(true)
	_allowed_meta_keys = allowed_meta_keys.duplicate()
	_expected_total = maxi(0, int(request.get("batch", 0)))


func emit_progress(value: Dictionary) -> bool:
	if _terminal:
		return false
	var expected_total := (
		_expected_total if _expected_total > 0 else int(value.get("total_items", 0))
	)
	if ContractV2.validate_provider_progress(value, expected_total) != null:
		return false
	var phase_order := ["submitting", "provider_processing", "downloading", "decoding"]
	var phase_index := phase_order.find(String(value["phase"]))
	if phase_index < _last_phase_index or int(value["completed_items"]) < _last_completed:
		return false
	if String(value["phase"]) == "submitting":
		if _submitting_emitted:
			return false
		_submitting_emitted = true
	if value["ratio"] != null and float(value["ratio"]) < _last_ratio:
		return false
	_expected_total = expected_total
	_last_phase_index = phase_index
	_last_completed = int(value["completed_items"])
	if value["ratio"] != null:
		_last_ratio = float(value["ratio"])
	progress.emit(value.duplicate(true))
	return true


func resolve(result: Dictionary) -> bool:
	if _terminal:
		return false
	var expected_size: Array = _request.get("provider_output_size", [])
	if ContractV2.validate_gen_result(result, expected_size, _allowed_meta_keys) != null:
		return reject(_contract_error("ambiguous_result", "decode"))
	_terminal = true
	completed.emit(result.duplicate(true))
	return true


func reject(error: Dictionary) -> bool:
	if _terminal:
		return false
	var safe_error := error
	if ContractV2.validate_pf_error(error) != null:
		safe_error = _contract_error("provider_internal", "provider")
	_terminal = true
	failed.emit(safe_error.duplicate(true))
	return true


func mark_canceled(request_id: String) -> bool:
	if _terminal or request_id.is_empty():
		return false
	var expected_id := String(_request.get("request_id", request_id))
	if request_id != expected_id:
		return false
	_terminal = true
	canceled.emit(request_id)
	return true


func is_terminal() -> bool:
	return _terminal


func _contract_error(code: String, stage: String) -> Dictionary:
	return {
		"code": code,
		"stage": stage,
		"provider_id": String(_request.get("provider_id", "")),
		"retryable": false,
		"retry_after_seconds": null,
		"status_code": null,
		"request_id": String(_request.get("request_id", "provider-contract")),
		"attempts": 1,
		"expected_count": maxi(0, int(_request.get("batch", 0))),
		"received_count": 0,
	}
