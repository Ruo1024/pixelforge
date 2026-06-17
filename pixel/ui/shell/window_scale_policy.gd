class_name PFWindowScalePolicy
extends RefCounted

## 窗口尺寸缩放策略。
## 输入：逻辑尺寸、界面缩放、屏幕像素倍率；输出：Godot Window 的像素尺寸。

const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")

const MAC_SCREEN_POINT_MAX_WIDTH := 2200
const MAC_SCREEN_POINT_MAX_HEIGHT := 1400


static func apply_minimum_size(
	window: Window, min_logical_size: Vector2i, interface_scale: float
) -> void:
	if window == null:
		return
	window.min_size = logical_size_to_window_pixels(min_logical_size, interface_scale)


static func apply_startup_defaults(
	window: Window,
	interface_scale: float,
	window_pixel_scale: float,
	default_logical_size: Vector2i,
	min_logical_size: Vector2i,
	screen_margin: int,
	os_name: String
) -> Dictionary:
	apply_minimum_size(window, min_logical_size, interface_scale)
	var geometry_scale := effective_window_geometry_scale(interface_scale, window_pixel_scale)
	var target_size := logical_size_to_window_pixels(default_logical_size, geometry_scale)
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		var margin := logical_size_to_window_pixels(Vector2i(screen_margin, 0), geometry_scale).x
		var usable_size_for_window := usable_size_to_window_pixels(
			usable_rect.size, window_pixel_scale, os_name
		)
		var minimum_fit := logical_size_to_window_pixels(Vector2i(960, 640), interface_scale)
		var max_width := maxi(minimum_fit.x, usable_size_for_window.x - margin)
		var max_height := maxi(minimum_fit.y, usable_size_for_window.y - margin)
		target_size.x = mini(target_size.x, max_width)
		target_size.y = mini(target_size.y, max_height)
		target_size.x = maxi(target_size.x, mini(window.min_size.x, max_width))
		target_size.y = maxi(target_size.y, mini(window.min_size.y, max_height))
		window.size = target_size
		var position_size := window_pixels_to_screen_units(
			target_size, window_pixel_scale, os_name, usable_rect.size
		)
		window.position = usable_rect.position + (usable_rect.size - position_size) / 2
	else:
		window.size = target_size
	return {
		"content_scale_factor": interface_scale,
		"window_pixel_scale": window_pixel_scale,
		"window_geometry_scale": geometry_scale,
		"min_size": [window.min_size.x, window.min_size.y],
		"target_size": [target_size.x, target_size.y],
		"actual_size": [window.size.x, window.size.y],
		"position": [window.position.x, window.position.y],
		"usable_rect": [usable_rect.size.x, usable_rect.size.y],
		"os": os_name,
	}


static func logical_size_to_window_pixels(size: Vector2i, interface_scale: float) -> Vector2i:
	var factor := maxf(interface_scale, InterfaceScalePolicy.MIN_INTERFACE_SCALE)
	return Vector2i(
		maxi(1, int(round(float(size.x) * factor))), maxi(1, int(round(float(size.y) * factor)))
	)


static func effective_window_geometry_scale(
	interface_scale: float, window_pixel_scale: float
) -> float:
	return maxf(
		maxf(interface_scale, InterfaceScalePolicy.MIN_INTERFACE_SCALE),
		maxf(window_pixel_scale, InterfaceScalePolicy.MIN_INTERFACE_SCALE)
	)


static func usable_size_to_window_pixels(
	size: Vector2i, window_pixel_scale: float, os_name: String
) -> Vector2i:
	if should_convert_macos_screen_units(size, window_pixel_scale, os_name):
		return Vector2i(
			maxi(1, int(round(float(size.x) * window_pixel_scale))),
			maxi(1, int(round(float(size.y) * window_pixel_scale)))
		)
	return size


static func window_pixels_to_screen_units(
	size: Vector2i,
	window_pixel_scale: float,
	os_name: String,
	usable_screen_units: Vector2i = Vector2i.ZERO
) -> Vector2i:
	if should_convert_macos_screen_units(usable_screen_units, window_pixel_scale, os_name):
		return Vector2i(
			maxi(1, int(round(float(size.x) / window_pixel_scale))),
			maxi(1, int(round(float(size.y) / window_pixel_scale)))
		)
	return size


static func should_convert_macos_screen_units(
	usable_size: Vector2i, window_pixel_scale: float, os_name: String
) -> bool:
	if os_name != "macOS" or window_pixel_scale <= 1.0:
		return false
	if usable_size == Vector2i.ZERO:
		return false
	return (
		usable_size.x <= MAC_SCREEN_POINT_MAX_WIDTH and usable_size.y <= MAC_SCREEN_POINT_MAX_HEIGHT
	)
