class_name PFAppTheme
extends RefCounted

## 根窗口主题的单点构建器；具体字体资源由 B2-D 诊断结论接入这里。

const UIFont := preload("res://ui/widgets/ui_font.gd")


static func build(default_font_size: int, small_font_size: int) -> Theme:
	var app_theme := Theme.new()
	app_theme.default_font = UIFont.get_font()
	app_theme.default_font_size = default_font_size
	for type_name in [
		"Button",
		"CheckBox",
		"ConfirmationDialog",
		"FileDialog",
		"ItemList",
		"Label",
		"LineEdit",
		"MenuButton",
		"OptionButton",
		"PopupMenu",
		"TabBar",
		"Tree",
		"Window",
	]:
		app_theme.set_font_size("font_size", type_name, default_font_size)
	app_theme.set_font_size("font_size", "Button", small_font_size)
	app_theme.set_font_size("font_size", "PopupMenu", small_font_size)
	app_theme.set_constant("h_separation", "HBoxContainer", 8)
	app_theme.set_constant("v_separation", "VBoxContainer", 0)
	return app_theme
