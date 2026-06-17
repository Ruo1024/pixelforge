class_name PFCanvasScalePolicy
extends RefCounted

## 画布美术缩放策略。
## 输入：viewport content scale factor 与相机缩放；输出：设备整数倍率和逻辑坐标倍率。

const POSITION_EPSILON := 0.0001


static func compute_canvas_device_scale(viewport_scale_factor: float) -> int:
	return maxi(1, int(round(maxf(viewport_scale_factor, 1.0))))


static func compute_window_stretch_scale(
	window_size: Vector2i, content_scale_size: Vector2i, content_scale_aspect: int
) -> float:
	if window_size.x <= 0 or window_size.y <= 0:
		return 1.0
	if content_scale_size.x <= 0 or content_scale_size.y <= 0:
		return 1.0
	var scale_x := float(window_size.x) / float(content_scale_size.x)
	var scale_y := float(window_size.y) / float(content_scale_size.y)
	match content_scale_aspect:
		Window.CONTENT_SCALE_ASPECT_IGNORE:
			return minf(scale_x, scale_y)
		Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH:
			return scale_x
		Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT:
			return scale_y
		_:
			return minf(scale_x, scale_y)


static func resolve_viewport_scale_factor(root: Window) -> float:
	if root == null:
		return 1.0
	var user_scale := maxf(root.content_scale_factor, 1.0)
	if root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return user_scale
	return (
		user_scale
		* compute_window_stretch_scale(
			root.size, root.content_scale_size, root.content_scale_aspect
		)
	)


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


## 把 Control 逻辑坐标吸附到物理像素网格，避免 NEAREST 放大后的像素块宽度抖动。
static func snap_position_to_physical_pixel(
	logical_position: Vector2, viewport_scale_factor: float
) -> Vector2:
	var safe_factor := maxf(viewport_scale_factor, 1.0)
	return Vector2(
		round(logical_position.x * safe_factor) / safe_factor,
		round(logical_position.y * safe_factor) / safe_factor
	)


## Headless 测试用的不变量：逻辑坐标乘 content factor 后必须接近整数物理像素。
static func is_position_on_physical_pixel(
	logical_position: Vector2, viewport_scale_factor: float
) -> bool:
	var safe_factor := maxf(viewport_scale_factor, 1.0)
	var physical_position := logical_position * safe_factor
	return (
		absf(physical_position.x - round(physical_position.x)) <= POSITION_EPSILON
		and absf(physical_position.y - round(physical_position.y)) <= POSITION_EPSILON
	)


## 已知吸附后的 item layer 位置时，反推相机中心，保持相机状态与实际渲染一致。
static func camera_center_from_layer_position(
	viewport_size: Vector2, layer_position: Vector2, art_logical_scale: float
) -> Vector2:
	return (viewport_size * 0.5 - layer_position) / maxf(art_logical_scale, POSITION_EPSILON)


## 缩放到光标时，先取最近物理像素网格，再反推相机中心，限制锚点漂移。
static func camera_center_for_snapped_anchor(
	viewport_size: Vector2,
	anchor_world: Vector2,
	screen_anchor: Vector2,
	art_logical_scale: float,
	viewport_scale_factor: float
) -> Vector2:
	var target_position := screen_anchor - anchor_world * art_logical_scale
	var snapped_position := snap_position_to_physical_pixel(target_position, viewport_scale_factor)
	return camera_center_from_layer_position(viewport_size, snapped_position, art_logical_scale)
