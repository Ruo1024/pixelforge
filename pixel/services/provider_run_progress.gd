class_name PFProviderRunProgress
extends RefCounted

## Pure request/run progress state used before B7-4 wires it to product state.

const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const TERMINAL_STATES := ["succeeded", "partial", "failed", "canceled"]


static func apply_provider_progress(record: Dictionary, progress: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	var expected := maxi(1, int(result.get("requested_count", 0)))
	if ContractV2.validate_provider_progress(progress, expected) != null:
		result["progress_issue"] = {"code": "invalid_progress", "field": "progress", "args": {}}
		return result
	if String(progress["phase"]) == "submitting" and String(result.get("state", "")) == "queued":
		result["state"] = "running"
		result["attempts"] = 1
	result["progress"] = progress.duplicate(true)
	return result


static func aggregate(records: Array, total_items: int, previous_ratio: float = 0.0) -> Dictionary:
	var fixed_total := maxi(0, total_items)
	var completed_items := 0
	var weighted_ratio := 0.0
	var determinate := fixed_total > 0
	for value in records:
		if not (value is Dictionary):
			determinate = false
			continue
		var record: Dictionary = value
		var count := maxi(0, int(record.get("requested_count", 0)))
		if String(record.get("state", "")) in TERMINAL_STATES:
			completed_items += count
			weighted_ratio += float(count)
			continue
		var progress_value: Variant = record.get("progress")
		if not (progress_value is Dictionary):
			determinate = false
			continue
		var progress: Dictionary = progress_value
		if not bool(progress.get("determinate", false)) or progress.get("ratio") == null:
			determinate = false
		else:
			weighted_ratio += float(count) * clampf(float(progress["ratio"]), 0.0, 1.0)
	var ratio: Variant = null
	if determinate and fixed_total > 0:
		ratio = maxf(previous_ratio, clampf(weighted_ratio / float(fixed_total), 0.0, 1.0))
	return {
		"determinate": determinate,
		"ratio": ratio,
		"completed_items": mini(completed_items, fixed_total),
		"total_items": fixed_total,
	}
