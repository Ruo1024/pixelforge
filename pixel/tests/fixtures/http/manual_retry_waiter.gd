class_name PFManualRetryWaiter
extends RefCounted

## Deterministic retry waiter: each wait stays pending until the test explicitly advances it.

signal resumed

var delays := []
var pending_count := 0


func wait(delay_seconds: float) -> void:
	delays.append(delay_seconds)
	pending_count += 1
	await resumed
	pending_count -= 1


func advance() -> void:
	if pending_count > 0:
		resumed.emit()
