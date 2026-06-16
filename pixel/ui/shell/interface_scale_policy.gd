class_name PFInterfaceScalePolicy
extends RefCounted

## 界面缩放策略。
## 输入：当前屏幕快照与用户配置；输出：检测缩放、实际应用缩放和日志证据字段。

const MIN_INTERFACE_SCALE := 1.0
const MAX_INTERFACE_SCALE := 2.0
const MAC_RETINA_DPI_THRESHOLD := 160
const MAC_RETINA_LOGICAL_DPI_THRESHOLD := 120
const MAC_RETINA_LOGICAL_MIN_WIDTH := 1100
const MAC_RETINA_LOGICAL_MIN_HEIGHT := 700
const MAC_RETINA_LOGICAL_MAX_WIDTH := 1800
const MAC_RETINA_LOGICAL_MAX_HEIGHT := 1200
const RETINA_WIDTH_THRESHOLD := 4800
const RETINA_HEIGHT_THRESHOLD := 2800
const LARGE_DISPLAY_WIDTH_THRESHOLD := 3200
const LARGE_DISPLAY_HEIGHT_THRESHOLD := 1800


static func compute_auto_interface_scale(
	reported_scale: float, usable_size: Vector2i, os_name: String = "", screen_dpi: int = 0
) -> float:
	var scale := maxf(reported_scale, MIN_INTERFACE_SCALE)
	if scale < 1.25:
		if should_use_macos_retina_fallback(reported_scale, usable_size, os_name, screen_dpi):
			scale = 2.0
		elif usable_size.x >= RETINA_WIDTH_THRESHOLD or usable_size.y >= RETINA_HEIGHT_THRESHOLD:
			scale = 2.0
		elif (
			usable_size.x >= LARGE_DISPLAY_WIDTH_THRESHOLD
			or usable_size.y >= LARGE_DISPLAY_HEIGHT_THRESHOLD
		):
			scale = 1.5
	return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)


static func should_use_macos_retina_fallback(
	reported_scale: float, usable_size: Vector2i, os_name: String = "", screen_dpi: int = 0
) -> bool:
	if os_name != "macOS" or reported_scale >= 1.25:
		return false
	if screen_dpi >= MAC_RETINA_DPI_THRESHOLD:
		return true
	var looks_like_retina_points := (
		usable_size.x >= MAC_RETINA_LOGICAL_MIN_WIDTH
		and usable_size.y >= MAC_RETINA_LOGICAL_MIN_HEIGHT
		and usable_size.x <= MAC_RETINA_LOGICAL_MAX_WIDTH
		and usable_size.y <= MAC_RETINA_LOGICAL_MAX_HEIGHT
	)
	return (
		looks_like_retina_points
		and (screen_dpi <= 0 or screen_dpi >= MAC_RETINA_LOGICAL_DPI_THRESHOLD)
	)


static func fit_interface_scale_to_startup_screen(scale: float, usable_size: Vector2i) -> float:
	if usable_size.x <= 0 or usable_size.y <= 0:
		return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
	return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)


static func resolve_from_snapshot(
	snapshot: Dictionary, configured_scale: float, os_name: String
) -> Dictionary:
	var reported_scale := float(snapshot.get("reported_scale", MIN_INTERFACE_SCALE))
	var usable_size := Vector2i(snapshot.get("usable_size", Vector2i.ZERO))
	var screen_dpi := int(snapshot.get("screen_dpi", 0))
	var mac_retina_fallback := should_use_macos_retina_fallback(
		reported_scale, usable_size, os_name, screen_dpi
	)
	var auto_scale := compute_auto_interface_scale(reported_scale, usable_size, os_name, screen_dpi)
	var resolved := auto_scale
	var source := "auto"
	if configured_scale >= MIN_INTERFACE_SCALE:
		resolved = clampf(configured_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
		source = "settings"
	var unclamped_resolved := resolved
	resolved = fit_interface_scale_to_startup_screen(resolved, usable_size)
	return {
		"source": source,
		"resolved": resolved,
		"detected_F": auto_scale,
		"configured": configured_scale,
		"reported_screen_scale": reported_scale,
		"screen_dpi": screen_dpi,
		"usable_size": usable_size,
		"mac_retina_fallback": mac_retina_fallback,
		"clamped": resolved < unclamped_resolved,
		"before_clamp": unclamped_resolved,
	}


static func apply_content_scale_policy(root: Window, scale: float) -> void:
	if root == null:
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


static func read_current_screen_snapshot() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	return {
		"screen": screen,
		"reported_scale": DisplayServer.screen_get_scale(screen),
		"screen_dpi": DisplayServer.screen_get_dpi(screen),
		"usable_size": usable_rect.size,
	}


static func screen_scale_snapshot_changed(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return left.is_empty() != right.is_empty()
	if int(left.get("screen", -1)) != int(right.get("screen", -1)):
		return true
	if not is_equal_approx(
		float(left.get("reported_scale", 1.0)), float(right.get("reported_scale", 1.0))
	):
		return true
	if int(left.get("screen_dpi", 0)) != int(right.get("screen_dpi", 0)):
		return true
	return (
		Vector2i(left.get("usable_size", Vector2i.ZERO))
		!= Vector2i(right.get("usable_size", Vector2i.ZERO))
	)
