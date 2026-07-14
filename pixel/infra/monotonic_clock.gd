class_name PFMonotonicClock
extends RefCounted

## Injectable monotonic time source for run coordination and deterministic tests.


func now_msec() -> int:
	return Time.get_ticks_msec()
