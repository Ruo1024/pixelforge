class_name PFCancelDeadlineScheduler
extends RefCounted

## Monotonic cancellation deadline boundary. Tests inject a manual scheduler with the
## same schedule_ms method; production timers never use wall-clock time.

var _next_id := 0


func schedule_ms(delay_ms: int, callback: Callable) -> int:
	_next_id += 1
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		(main_loop as SceneTree).create_timer(float(maxi(0, delay_ms)) / 1000.0).timeout.connect(
			callback, CONNECT_ONE_SHOT
		)
	else:
		callback.call_deferred()
	return _next_id
