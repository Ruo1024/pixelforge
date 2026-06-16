class_name PFCanvasScalePolicy
extends RefCounted

## 画布美术缩放策略。
## 输入：viewport content scale factor 与相机缩放；输出：设备整数倍率和逻辑坐标倍率。


static func compute_canvas_device_scale(viewport_scale_factor: float) -> int:
	return maxi(1, int(round(maxf(viewport_scale_factor, 1.0))))


static func compute_canvas_compensation_scale(viewport_scale_factor: float) -> float:
	var safe_factor := maxf(viewport_scale_factor, 1.0)
	return float(compute_canvas_device_scale(safe_factor)) / safe_factor


static func compute_art_logical_scale(
	camera_zoom_value: float, viewport_scale_factor: float
) -> float:
	return maxf(camera_zoom_value, 0.0) * compute_canvas_compensation_scale(viewport_scale_factor)


static func compute_art_physical_scale(
	camera_zoom_value: float, viewport_scale_factor: float
) -> float:
	return maxf(camera_zoom_value, 0.0) * float(compute_canvas_device_scale(viewport_scale_factor))


static func effective_art_pixel_px(camera_zoom_value: float, viewport_scale_factor: float) -> int:
	return maxi(1, int(round(compute_art_physical_scale(camera_zoom_value, viewport_scale_factor))))
