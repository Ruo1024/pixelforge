class_name PFDialogScalePolicy
extends RefCounted

## 弹窗缩放策略。
## FileDialog 默认使用 Godot 自绘窗口，以便跟随 Window.content_scale_factor 做真机验收。


static func configure_file_dialog(dialog: FileDialog) -> void:
	if dialog == null:
		return
	dialog.use_native_dialog = false
