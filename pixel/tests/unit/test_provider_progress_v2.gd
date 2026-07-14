extends "res://addons/gut/test.gd"

const PROGRESS_PATH := "res://services/provider_run_progress.gd"


func test_queue_submitting_attempt_once() -> void:
	var progress: Script = load(PROGRESS_PATH)
	assert_not_null(progress)
	if progress == null:
		return
	var queued := {"state": "queued", "attempts": 0, "requested_count": 4}
	var started: Dictionary = progress.apply_provider_progress(
		queued, _progress("submitting", false, null, 0, 4)
	)
	assert_eq(started["state"], "running")
	assert_eq(started["attempts"], 1)
	var duplicate: Dictionary = progress.apply_provider_progress(
		started, _progress("submitting", false, null, 0, 4)
	)
	assert_eq(duplicate["attempts"], 1)


func test_fixed_denominator_aggregate_is_monotonic_and_honest() -> void:
	var progress: Script = load(PROGRESS_PATH)
	assert_not_null(progress)
	if progress == null:
		return
	var records := [
		{
			"state": "running",
			"requested_count": 4,
			"progress": _progress("provider_processing", true, 0.5, 2, 4),
		},
		{
			"state": "running",
			"requested_count": 1,
			"progress": _progress("provider_processing", true, 0.0, 0, 1),
		},
	]
	var known: Dictionary = progress.aggregate(records, 5, 0.0)
	assert_true(known["determinate"])
	assert_eq(known["ratio"], 0.4)
	assert_eq(known["completed_items"], 2)
	assert_eq(known["total_items"], 5)
	records[1]["progress"] = _progress("provider_processing", false, null, 0, 1)
	var unknown: Dictionary = progress.aggregate(records, 5, 0.4)
	assert_false(unknown["determinate"])
	assert_null(unknown["ratio"])
	records[0]["state"] = "succeeded"
	records[0].erase("progress")
	records[1]["progress"] = _progress("provider_processing", true, 0.0, 0, 1)
	var completed_chunk: Dictionary = progress.aggregate(records, 5, 0.4)
	assert_true(completed_chunk["determinate"])
	assert_eq(completed_chunk["ratio"], 0.8)
	assert_eq(completed_chunk["completed_items"], 4)


func _progress(
	phase: String, determinate: bool, ratio: Variant, completed_items: int, total_items: int
) -> Dictionary:
	return {
		"phase": phase,
		"determinate": determinate,
		"ratio": ratio,
		"completed_items": completed_items,
		"total_items": total_items,
	}
