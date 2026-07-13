class_name PFInterfaceScalePolicy
extends RefCounted

## 界面缩放策略。
## 输入：当前屏幕快照与用户配置；输出：检测缩放、实际应用缩放和日志证据字段。

const MIN_INTERFACE_SCALE := 1.0
const MAX_INTERFACE_SCALE := 2.0
const RETINA_WIDTH_THRESHOLD := 4800
const RETINA_HEIGHT_THRESHOLD := 2800
const LARGE_DISPLAY_WIDTH_THRESHOLD := 3200
const LARGE_DISPLAY_HEIGHT_THRESHOLD := 1800
const READABLE_2K_WIDTH_THRESHOLD := 2560
const READABLE_2K_HEIGHT_THRESHOLD := 1440
const MID_INTERFACE_SCALE := 1.25


static func compute_auto_interface_scale(
	reported_scale: float, usable_size: Vector2i, os_name: String = "", _screen_dpi: int = 0
) -> float:
	if os_name == "macOS":
		return clampf(reported_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)

	if reported_scale >= 1.25:
		return clampf(reported_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)

	if usable_size.x >= RETINA_WIDTH_THRESHOLD or usable_size.y >= RETINA_HEIGHT_THRESHOLD:
		return 2.0
	if (
		usable_size.x >= LARGE_DISPLAY_WIDTH_THRESHOLD
		or usable_size.y >= LARGE_DISPLAY_HEIGHT_THRESHOLD
	):
		return 1.5
	if (
		usable_size.x >= READABLE_2K_WIDTH_THRESHOLD
		or usable_size.y >= READABLE_2K_HEIGHT_THRESHOLD
	):
		return MID_INTERFACE_SCALE
	return MIN_INTERFACE_SCALE


static func fit_interface_scale_to_startup_screen(scale: float, usable_size: Vector2i) -> float:
	if usable_size.x <= 0 or usable_size.y <= 0:
		return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)
	return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)


static func window_pixel_scale_from_snapshot(snapshot: Dictionary, os_name: String) -> float:
	var reported_scale := float(snapshot.get("reported_scale", MIN_INTERFACE_SCALE))
	if os_name == "macOS":
		return maxf(float(snapshot.get("max_scale", reported_scale)), MIN_INTERFACE_SCALE)
	return maxf(reported_scale, MIN_INTERFACE_SCALE)


static func resolve_from_snapshot(
	snapshot: Dictionary, configured_scale: float, os_name: String
) -> Dictionary:
	var reported_scale := float(snapshot.get("reported_scale", MIN_INTERFACE_SCALE))
	var max_scale := float(snapshot.get("max_scale", reported_scale))
	var usable_size := Vector2i(snapshot.get("usable_size", Vector2i.ZERO))
	var screen_dpi := int(snapshot.get("screen_dpi", 0))
	var display_server := String(snapshot.get("display_server", ""))
	var window_pixel_scale := window_pixel_scale_from_snapshot(snapshot, os_name)
	var detected_scale := max_scale if os_name == "macOS" else reported_scale
	var auto_scale := compute_auto_interface_scale(detected_scale, usable_size, os_name, screen_dpi)
	var resolved := auto_scale
	var source := "auto"
	if display_server == "embedded":
		resolved = MIN_INTERFACE_SCALE
		source = "editor_embed"
	elif configured_scale >= MIN_INTERFACE_SCALE:
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
		"max_screen_scale": max_scale,
		"window_pixel_scale": window_pixel_scale,
		"screen_dpi": screen_dpi,
		"usable_size": usable_size,
		"mac_retina_fallback": false,
		"display_server": display_server,
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
	var scale_screen := screen
	if DisplayServer.get_name() == "wayland":
		scale_screen = DisplayServer.SCREEN_OF_MAIN_WINDOW
	return {
		"screen": screen,
		"reported_scale": DisplayServer.screen_get_scale(scale_screen),
		"max_scale": DisplayServer.screen_get_max_scale(),
		"screen_dpi": DisplayServer.screen_get_dpi(screen),
		"screen_size": DisplayServer.screen_get_size(screen),
		"usable_size": usable_rect.size,
		"display_server": DisplayServer.get_name(),
	}
