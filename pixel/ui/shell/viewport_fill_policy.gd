class_name PFViewportFillPolicy
extends RefCounted

## 根 Control 填充策略。
## 输入：Viewport 可见矩形；输出：Control offset 覆盖 expand 模式暴露的完整区域。


static func apply(control: Control, viewport_rect: Rect2) -> void:
	if control == null:
		return
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = viewport_rect.position.x
	control.offset_top = viewport_rect.position.y
	control.offset_right = viewport_rect.position.x + viewport_rect.size.x
	control.offset_bottom = viewport_rect.position.y + viewport_rect.size.y
