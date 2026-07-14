class_name PFFakeClock
extends RefCounted

## Deterministic monotonic clock for run-state and rendering tests.

var _now_msec := 0


func now_msec() -> int:
	return _now_msec


func advance_msec(delta_msec: int) -> void:
	_now_msec += maxi(0, delta_msec)
