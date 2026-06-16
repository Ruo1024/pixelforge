class_name PFWindowScalePolicy
extends RefCounted

## 窗口尺寸缩放策略。
## 输入：逻辑尺寸、界面缩放与屏幕可用区域；输出：Godot Window 的像素尺寸。

const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")


static func apply_minimum_size(
	window: Window, min_logical_size: Vector2i, interface_scale: float
) -> void:
	if window == null:
		return
	window.min_size = logical_size_to_window_pixels(min_logical_size, interface_scale)


static func apply_startup_defaults(
	window: Window,
	interface_scale: float,
	default_logical_size: Vector2i,
	min_logical_size: Vector2i,
	screen_margin: int,
	os_name: String
) -> Dictionary:
	apply_minimum_size(window, min_logical_size, interface_scale)
	var target_size := logical_size_to_window_pixels(default_logical_size, interface_scale)
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		var margin := logical_size_to_window_pixels(Vector2i(screen_margin, 0), interface_scale).x
		var usable_size_for_window := usable_size_to_window_pixels(
			usable_rect.size, interface_scale, os_name
		)
		var minimum_fit := logical_size_to_window_pixels(Vector2i(960, 640), interface_scale)
		var max_width := maxi(minimum_fit.x, usable_size_for_window.x - margin)
		var max_height := maxi(minimum_fit.y, usable_size_for_window.y - margin)
		target_size.x = mini(target_size.x, max_width)
		target_size.y = mini(target_size.y, max_height)
		target_size.x = maxi(target_size.x, mini(window.min_size.x, max_width))
		target_size.y = maxi(target_size.y, mini(window.min_size.y, max_height))
		window.size = target_size
		var position_size := window_pixels_to_screen_units(target_size, interface_scale, os_name)
		window.position = usable_rect.position + (usable_rect.size - position_size) / 2
	else:
		window.size = target_size
	return {
		"content_scale_factor": interface_scale,
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


static func usable_size_to_window_pixels(
	size: Vector2i, interface_scale: float, os_name: String
) -> Vector2i:
	if os_name == "macOS" and interface_scale > 1.0:
		return Vector2i(
			maxi(1, int(round(float(size.x) * interface_scale))),
			maxi(1, int(round(float(size.y) * interface_scale)))
		)
	return size


static func window_pixels_to_screen_units(
	size: Vector2i, interface_scale: float, os_name: String
) -> Vector2i:
	if os_name == "macOS" and interface_scale > 1.0:
		return Vector2i(
			maxi(1, int(round(float(size.x) / interface_scale))),
			maxi(1, int(round(float(size.y) / interface_scale)))
		)
	return size
