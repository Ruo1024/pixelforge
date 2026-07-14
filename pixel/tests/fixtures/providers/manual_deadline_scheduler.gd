class_name PFManualDeadlineScheduler
extends RefCounted

## Deterministic deadline scheduler. Tests advance monotonic time explicitly.

var now_ms := 0
var _next_id := 0
var _scheduled := []


func schedule_ms(delay_ms: int, callback: Callable) -> int:
	_next_id += 1
	_scheduled.append({"id": _next_id, "due_ms": now_ms + maxi(0, delay_ms), "callback": callback})
	return _next_id


func advance_ms(delta_ms: int) -> void:
	now_ms += maxi(0, delta_ms)
	while true:
		var next_index := -1
		var next_due := 0
		var next_id := 0
		for index in range(_scheduled.size()):
			var item: Dictionary = _scheduled[index]
			if int(item["due_ms"]) > now_ms:
				continue
			if (
				next_index < 0
				or int(item["due_ms"]) < next_due
				or (int(item["due_ms"]) == next_due and int(item["id"]) < next_id)
			):
				next_index = index
				next_due = int(item["due_ms"])
				next_id = int(item["id"])
		if next_index < 0:
			return
		var due: Dictionary = _scheduled.pop_at(next_index)
		(due["callback"] as Callable).call()
