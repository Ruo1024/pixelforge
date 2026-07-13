class_name PFWindowScalePolicy
extends RefCounted

## 窗口尺寸缩放策略。
## DisplayServer 与 Window 的几何量使用同一套平台单位；这里仅应用界面倍率，禁止再猜测
## Cocoa point/physical pixel 并做二次换算。

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
		target_size = fit_size_to_usable_rect(
			target_size, window.min_size, usable_rect.size, screen_margin
		)
		window.size = target_size
		window.position = usable_rect.position + (usable_rect.size - target_size) / 2
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


static func fit_size_to_usable_rect(
	target_size: Vector2i, minimum_size: Vector2i, usable_size: Vector2i, screen_margin: int
) -> Vector2i:
	var margin := maxi(screen_margin, 0)
	var available := Vector2i(maxi(1, usable_size.x - margin), maxi(1, usable_size.y - margin))
	return Vector2i(
		clampi(target_size.x, mini(minimum_size.x, available.x), available.x),
		clampi(target_size.y, mini(minimum_size.y, available.y), available.y)
	)


static func effective_window_geometry_scale(
	interface_scale: float, _window_pixel_scale: float
) -> float:
	return maxf(interface_scale, InterfaceScalePolicy.MIN_INTERFACE_SCALE)


static func usable_size_to_window_pixels(
	size: Vector2i, _window_pixel_scale: float, _os_name: String
) -> Vector2i:
	return size


static func window_pixels_to_screen_units(
	size: Vector2i,
	_window_pixel_scale: float,
	_os_name: String,
	_usable_screen_units: Vector2i = Vector2i.ZERO
) -> Vector2i:
	return size
