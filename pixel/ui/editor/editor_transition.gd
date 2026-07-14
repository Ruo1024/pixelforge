class_name PFEditorTransition
extends ColorRect

## Brief shared-element-style veil that prevents a hard visual cut into the editor.


func play_in(source_texture: Texture2D = null) -> void:
	color = Color(0.04, 0.045, 0.055, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween()
	tween.tween_property(self, "color:a", 0.72, 0.08)
	if source_texture != null:
		tooltip_text = PFStrings.text(
			"EDITOR_TRANSITION_TOOLTIP_FORMAT",
			[source_texture.get_width(), source_texture.get_height()]
		)
	tween.tween_property(self, "color:a", 0.0, 0.12)
	tween.tween_callback(queue_free)
