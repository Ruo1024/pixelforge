class_name PFUIFont
extends RefCounted

## 产品 UI 字体单点入口；普通 Control 与画布自绘文字使用同一资源和度量。

const FONT: Font = preload("res://assets/fonts/NotoSansCJKsc-Regular.otf")


static func get_font() -> Font:
	return FONT
