class_name PFMonotonicClock
extends RefCounted

## Production Clock implementation for transient run presentation and deadlines.


func now_msec() -> int:
	return Time.get_ticks_msec()
