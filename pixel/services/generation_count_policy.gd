class_name PFGenerationCountPolicy
extends RefCounted

## Keeps the high-count confirmation gate independent from output/task side effects.

const MIN_COUNT := 1
const MAX_COUNT := 16
const CONFIRM_FROM := 5


static func validate(count: int) -> Dictionary:
	if count < MIN_COUNT or count > MAX_COUNT:
		return {"ok": false, "requires_confirmation": false}
	return {"ok": true, "requires_confirmation": count >= CONFIRM_FROM}
