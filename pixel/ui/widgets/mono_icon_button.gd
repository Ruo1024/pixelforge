class_name PFMonoIconButton
extends Button

## Small original line icons used by workspace chrome without font glyph dependencies.

var icon_id := ""


func setup(value: String) -> void:
	icon_id = value
	text = ""
	queue_redraw()


func _draw() -> void:
	var color := get_theme_color("font_color", "Button")
	var center := size * 0.5
	match icon_id:
		"add_input":
			draw_line(center - Vector2(7, 0), center + Vector2(7, 0), color, 2)
			draw_line(center - Vector2(0, 7), center + Vector2(0, 7), color, 2)
		"import_reference":
			draw_line(center - Vector2(0, 8), center + Vector2(0, 4), color, 2)
			draw_line(center + Vector2(0, 4), center + Vector2(-5, -1), color, 2)
			draw_line(center + Vector2(0, 4), center + Vector2(5, -1), color, 2)
			draw_line(center + Vector2(-7, 8), center + Vector2(7, 8), color, 2)
		"library":
			for offset in [Vector2(-6, -6), Vector2(2, -6), Vector2(-6, 2), Vector2(2, 2)]:
				draw_rect(Rect2(center + offset, Vector2(5, 5)), color, false, 1.5)
