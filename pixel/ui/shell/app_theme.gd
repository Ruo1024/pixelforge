class_name PFAppTheme
extends RefCounted

## 根窗口主题的单点构建器；具体字体资源由 B2-D 诊断结论接入这里。

const UIFont := preload("res://ui/widgets/ui_font.gd")

const CANVAS := Color("0d121c")
const GRID := Color("283246")
const CARD := Color("151c29")
const ELEVATED := Color("1b2535")
const SECTION := Color("101722")
const BORDER := Color("2b3850")
const BORDER_HOVER := Color("455773")
const TEXT_PRIMARY := Color("f2f5fa")
const TEXT_SECONDARY := Color("aab4c4")
const TEXT_MUTED := Color("7b879b")
const SELECTION := Color("6fa8ff")
const SUCCESS := Color("45d6a3")
const WARNING := Color("f4b45f")
const ERROR := Color("f06b6b")
const MEDIA_RAIL := Color("dde8f7")
const MEDIA_RAIL_TEXT := Color("111827")

const OUTER_RADIUS := 14
const SECTION_RADIUS := 10
const CONTROL_RADIUS := 8
const CARD_HEADER_HEIGHT := 44
const MEDIA_HEADER_HEIGHT := 32
const CARD_PADDING := 16
const LEFT_RAIL_WIDTH := 48
const INSPECTOR_MIN_WIDTH := 320
const RAIL_BUTTON_SIZE := 40
const PROMPT_MIN_HEIGHT := 132
const PALETTE_SWATCH_SIZE := 20
const REFERENCE_TILE_SIZE := 96
const REFERENCE_TILE_ROW_HEIGHT := 132
const STRUCTURED_HERO_FONT_SIZE := 24


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
