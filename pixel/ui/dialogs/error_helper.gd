class_name PFErrorHelper
extends RefCounted

## M2.1 用户错误提示。
## 只负责把 core 返回的 warning 翻译成可操作建议；不改变算法结果。

const Strings := preload("res://ui/shell/strings.gd")


static func show_matte_error(parent: Node, warning: String) -> void:
	if warning != "non_flat_background" or parent == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = Strings.DIALOG_MATTE_NON_FLAT_TITLE
	dialog.dialog_text = Strings.DIALOG_MATTE_NON_FLAT_BODY
	parent.add_child(dialog)
	dialog.popup_centered()
