class_name PFOnboarding
extends RefCounted

## 首次启动引导。
## 只在真实窗口中显示；headless 测试不弹窗，避免自动化不稳定。

const Strings := preload("res://ui/shell/strings.gd")


static func show_first_run_tips(parent: Node) -> AcceptDialog:
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var dialog := AcceptDialog.new()
	dialog.title = Strings.DIALOG_ONBOARDING_TITLE
	dialog.dialog_text = Strings.DIALOG_ONBOARDING_BODY
	parent.add_child(dialog)
	dialog.popup_centered()
	return dialog
