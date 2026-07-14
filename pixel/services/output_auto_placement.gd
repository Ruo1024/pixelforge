class_name PFOutputAutoPlacement
extends RefCounted

## Pure right-side Output placement. Existing card bounds are read-only inputs.

const HORIZONTAL_GAP := 80.0
const VERTICAL_GAP := 56.0


static func find_position(
	source_bounds: Rect2, existing_bounds: Array, output_size: Vector2
) -> Vector2:
	var candidate := Vector2(source_bounds.end.x + HORIZONTAL_GAP, source_bounds.position.y)
	while true:
		var candidate_bounds := Rect2(candidate, output_size)
		var blocker: Variant = null
		for value in existing_bounds:
			if value is Rect2 and candidate_bounds.intersects(value, true):
				blocker = value
				break
		if blocker == null:
			return candidate
		var blocker_bounds: Rect2 = blocker
		candidate.y = blocker_bounds.end.y + VERTICAL_GAP
	return candidate
