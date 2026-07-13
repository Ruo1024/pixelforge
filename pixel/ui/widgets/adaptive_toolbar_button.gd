class_name PFAdaptiveToolbarButton
extends Button

## Toolbar action that swaps its label for a drawn icon only in the compact shell layout.

const Strings := preload("res://ui/shell/strings.gd")

var text_key := ""
var icon_id := ""
var full_width := 44.0
var compact_width := 40.0
var compact := false


func setup(key: String, icon: String, normal_width: float, small_width: float = 40.0) -> void:
	text_key = key
	icon_id = icon
	full_width = normal_width
	compact_width = small_width
	refresh_text()


func set_compact(value: bool) -> void:
	if compact == value:
		return
	compact = value
	custom_minimum_size.x = compact_width if compact else full_width
	refresh_text()


func refresh_text() -> void:
	var localized := Strings.text(text_key)
	text = "" if compact else localized
	tooltip_text = localized
	queue_redraw()


func _draw() -> void:
	if not compact:
		return
	var color := get_theme_color("font_color", "Button")
	var center := size * 0.5
	match icon_id:
		"undo":
			_draw_history_icon(center, color, false)
		"redo":
			_draw_history_icon(center, color, true)
		"inspector":
			draw_rect(Rect2(center - Vector2(8, 7), Vector2(16, 14)), color, false, 1.5)
			draw_line(center + Vector2(2, -7), center + Vector2(2, 7), color, 1.5)


func _draw_history_icon(center: Vector2, color: Color, mirrored: bool) -> void:
	var direction := 1.0 if mirrored else -1.0
	draw_arc(center, 6.0, -2.4 if mirrored else -0.75, 0.75 if mirrored else 2.4, 16, color, 1.5)
	var tip := center + Vector2(6.0 * direction, -4.0)
	draw_line(tip, tip + Vector2(-4.0 * direction, -1.0), color, 1.5)
	draw_line(tip, tip + Vector2(-1.0 * direction, 4.0), color, 1.5)
