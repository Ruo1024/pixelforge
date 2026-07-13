class_name PFResponsiveWorkspace
extends Container

## Keeps the canvas full-width below the dock breakpoint and overlays the inspector.

const INSPECTOR_DOCK_BREAKPOINT := 1440.0
const INSPECTOR_WIDTH := 420.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout_workspace()


func is_inspector_overlay() -> bool:
	return size.x < INSPECTOR_DOCK_BREAKPOINT


func _layout_workspace() -> void:
	if get_child_count() < 2:
		return
	var canvas := get_child(0) as Control
	var inspector := get_child(1) as Control
	if canvas == null or inspector == null:
		return
	var inspector_width := minf(INSPECTOR_WIDTH, size.x)
	var docked := inspector.visible and not is_inspector_overlay()
	fit_child_in_rect(
		canvas, Rect2(Vector2.ZERO, Vector2(size.x - inspector_width if docked else size.x, size.y))
	)
	fit_child_in_rect(
		inspector,
		Rect2(Vector2(size.x - inspector_width, 0), Vector2(inspector_width, size.y))
	)
	inspector.z_index = 20 if is_inspector_overlay() else 0
