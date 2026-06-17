class_name PFCanvasToolInputPolicy
extends RefCounted

## 画布工具输入分流。
## 高频导航（滚轮、中键、空格平移）优先保留给画布，其余事件交给激活工具。


static func tool_manager_handles(
	tool_manager: Variant, event: InputEvent, canvas: Control, active_target: Dictionary
) -> bool:
	if tool_manager == null:
		return false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP
			or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN
			or mouse_event.button_index == MOUSE_BUTTON_MIDDLE
			or Input.is_key_pressed(KEY_SPACE)
		):
			return false
		return tool_manager.handle_canvas_input(event, canvas, active_target)
	return tool_manager.handle_canvas_input(event, canvas, active_target)
