class_name PFMagicWandTool
extends PFTool

## 魔棒选区工具。
## 点击单张素材内的像素，调用 core PFSelection.magic_wand 生成像素级选区。

const DEFAULT_TOLERANCE := 15.0

var tolerance := DEFAULT_TOLERANCE
var contiguous := true


func get_id() -> String:
	return "magic_wand"


func get_name() -> String:
	return "Magic Wand"


func get_hotkey() -> String:
	return "W"


func get_cursor_shape() -> int:
	return Input.CURSOR_POINTING_HAND


func on_mouse_press(image_pos: Vector2i, button: MouseButton, modifiers: int) -> void:
	if button != MOUSE_BUTTON_LEFT or _source_image == null:
		return
	var selection := SelectionScript.magic_wand(
		_source_image,
		image_pos,
		{"tolerance": tolerance, "contiguous": contiguous, "alpha_sensitive": true}
	)
	_commit_selection(_combine_with_current(selection, modifiers))
