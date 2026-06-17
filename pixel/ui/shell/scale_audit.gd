class_name PFScaleAudit
extends RefCounted

## 缩放审计日志。
## 用途：`--scale-audit` 真机验收时输出顶层 Control 尺寸与画布物理像素吸附证据。

const CanvasScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
const Log := preload("res://core/util/log_util.gd")


static func is_requested() -> bool:
	return OS.get_cmdline_args().has("--scale-audit")


static func log_scale_audit(
	owner: Node,
	canvas: Control,
	screen_snapshot: Dictionary,
	content_scale_factor: float,
	window_pixel_scale: float
) -> void:
	(
		Log
		. info(
			"Scale audit",
			{
				"content_scale_factor": content_scale_factor,
				"window_pixel_scale": window_pixel_scale,
				"current_screen": int(screen_snapshot.get("screen", -1)),
				"controls": _collect_control_audit(owner),
				"canvas": _collect_canvas_audit(canvas),
			}
		)
	)


static func _collect_control_audit(owner: Node) -> Array:
	var output := []
	if owner == null:
		return output
	for path in [
		"Root",
		"Root/TopBar",
		"Root/Content",
		"Root/Content/InfiniteCanvas",
		"Root/Content/CleanupInspector",
		"Root/BottomBar",
		"ZoomControl",
	]:
		var control := owner.get_node_or_null(path) as Control
		if control == null:
			continue
		var rect := control.get_global_rect()
		(
			output
			. append(
				{
					"path": path,
					"position": [rect.position.x, rect.position.y],
					"size": [rect.size.x, rect.size.y],
				}
			)
		)
	return output


static func _collect_canvas_audit(canvas: Control) -> Dictionary:
	if canvas == null:
		return {}
	var viewport_scale_factor := float(canvas.call("_resolve_viewport_scale_factor"))
	var camera_zoom := float(canvas.get("camera_zoom"))
	var item_layer: Node2D = canvas.get("item_layer")
	return {
		"viewport_scale_factor": viewport_scale_factor,
		"canvas_device_scale": CanvasScalePolicy.compute_canvas_device_scale(viewport_scale_factor),
		"camera_zoom": camera_zoom,
		"art_physical_scale":
		CanvasScalePolicy.compute_art_physical_scale(camera_zoom, viewport_scale_factor),
		"item_layer_scale": [item_layer.scale.x, item_layer.scale.y],
		"item_layer_position": [item_layer.position.x, item_layer.position.y],
		"item_layer_pos_physical":
		[
			item_layer.position.x * viewport_scale_factor,
			item_layer.position.y * viewport_scale_factor,
		],
		"item_layer_position_aligned":
		CanvasScalePolicy.is_position_on_physical_pixel(item_layer.position, viewport_scale_factor),
	}
