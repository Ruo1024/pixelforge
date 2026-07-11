class_name PFScaleAudit
extends RefCounted

## 缩放审计日志。
## 用途：`--scale-audit` 真机验收时输出顶层 Control 尺寸与画布物理像素吸附证据。

const CanvasScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
const Log := preload("res://core/util/log_util.gd")

const TARGET_CODEPOINTS := [
	0x0041,  # Latin uppercase
	0x0067,  # Latin descender
	0x00E9,  # Latin accent
	0x4E2D,  # 中
	0x6587,  # 文
	0x50CF,  # 像
	0x7D20,  # 素
]
const REPRESENTATIVE_DIALOG_NAMES := [
	"V1OnboardingDialog",
	"RecoveryDialog",
	"UnsavedChangesDialog",
	"ProviderSettingsDialog",
	"ExportOverwriteDialog",
]


static func is_requested() -> bool:
	return OS.get_cmdline_args().has("--scale-audit")


static func log_scale_audit(
	owner: Node,
	canvas: Control,
	screen_snapshot: Dictionary,
	content_scale_factor: float,
	window_pixel_scale: float
) -> void:
	(
		Log
		. info(
			"Scale audit",
			{
				"content_scale_factor": content_scale_factor,
				"window_pixel_scale": window_pixel_scale,
				"current_screen": int(screen_snapshot.get("screen", -1)),
				"controls": _collect_control_audit(owner),
				"dialogs": collect_dialog_audit(owner),
				"canvas": _collect_canvas_audit(canvas),
			}
		)
	)


static func collect_dialog_audit(owner: Node) -> Array:
	var dialogs: Array[ConfirmationDialog] = []
	_collect_confirmation_dialogs(owner, dialogs)
	var output := []
	for dialog in dialogs:
		var controls := []
		_collect_dialog_controls(dialog, dialog, controls)
		(
			output
			. append(
				{
					"path": String(owner.get_path_to(dialog)),
					"visible": dialog.visible,
					"position": [dialog.position.x, dialog.position.y],
					"size": [dialog.size.x, dialog.size.y],
					"min_size": [dialog.min_size.x, dialog.min_size.y],
					"controls": controls,
				}
			)
		)
	return output


static func _collect_control_audit(owner: Node) -> Array:
	var output := []
	if owner == null:
		return output
	for path in [
		"Root",
		"Root/TopBar",
		"Root/Content",
		"Root/Content/InfiniteCanvas",
		"Root/Content/ContextInspector",
		"Root/BottomBar",
		"ZoomControl",
	]:
		var control := owner.get_node_or_null(path) as Control
		if control == null:
			continue
		var rect := control.get_global_rect()
		(
			output
			. append(
				{
					"path": path,
					"position": [rect.position.x, rect.position.y],
					"size": [rect.size.x, rect.size.y],
				}
			)
		)
	return output


static func _collect_canvas_audit(canvas: Control) -> Dictionary:
	if canvas == null:
		return {}
	var viewport_scale_factor := float(canvas.call("_resolve_viewport_scale_factor"))
	var camera_zoom := float(canvas.get("camera_zoom"))
	var item_layer: Node2D = canvas.get("item_layer")
	return {
		"viewport_scale_factor": viewport_scale_factor,
		"canvas_device_scale": CanvasScalePolicy.compute_canvas_device_scale(viewport_scale_factor),
		"camera_zoom": camera_zoom,
		"art_physical_scale":
		CanvasScalePolicy.compute_art_physical_scale(camera_zoom, viewport_scale_factor),
		"item_layer_scale": [item_layer.scale.x, item_layer.scale.y],
		"item_layer_position": [item_layer.position.x, item_layer.position.y],
		"item_layer_pos_physical":
		[
			item_layer.position.x * viewport_scale_factor,
			item_layer.position.y * viewport_scale_factor,
		],
		"item_layer_position_aligned":
		CanvasScalePolicy.is_position_on_physical_pixel(item_layer.position, viewport_scale_factor),
	}


static func _collect_confirmation_dialogs(node: Node, output: Array[ConfirmationDialog]) -> void:
	if node == null:
		return
	if node is ConfirmationDialog:
		if String(node.name) in REPRESENTATIVE_DIALOG_NAMES:
			output.append(node)
		return
	for child in node.get_children():
		_collect_confirmation_dialogs(child, output)


static func _collect_dialog_controls(dialog: ConfirmationDialog, node: Node, output: Array) -> void:
	for child in node.get_children(true):
		if child is Window:
			continue
		if child is Control:
			output.append(_control_geometry_audit(dialog, child))
		_collect_dialog_controls(dialog, child, output)


static func _control_geometry_audit(dialog: ConfirmationDialog, control: Control) -> Dictionary:
	var rect := control.get_global_rect()
	var combined_minimum := control.get_combined_minimum_size()
	var audit := {
		"path": String(dialog.get_path_to(control)),
		"class": control.get_class(),
		"parent_chain": _parent_chain(dialog, control),
		"visible": control.is_visible_in_tree(),
		"position": [rect.position.x, rect.position.y],
		"size": [rect.size.x, rect.size.y],
		"minimum_size": [combined_minimum.x, combined_minimum.y],
		"custom_minimum_size": [control.custom_minimum_size.x, control.custom_minimum_size.y],
	}
	if _uses_font(control):
		audit["font"] = _font_audit(control)
	return audit


static func _parent_chain(dialog: ConfirmationDialog, control: Control) -> Array:
	var chain := []
	var current: Node = control
	while current != null:
		chain.push_front(String(current.name))
		if current == dialog:
			break
		current = current.get_parent()
	return chain


static func _uses_font(control: Control) -> bool:
	return (
		control is Label
		or control is Button
		or control is LineEdit
		or control is TextEdit
		or control is RichTextLabel
		or control is ItemList
		or control is Tree
		or control is SpinBox
	)


static func _font_audit(control: Control) -> Dictionary:
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	var coverage := {}
	for codepoint in TARGET_CODEPOINTS:
		coverage["U+%04X" % codepoint] = font != null and font.has_char(codepoint)
	if font == null:
		return {"font_size": font_size, "ascent": 0.0, "descent": 0.0, "coverage": coverage}
	return {
		"font_size": font_size,
		"ascent": font.get_ascent(font_size),
		"descent": font.get_descent(font_size),
		"height": font.get_height(font_size),
		"coverage": coverage,
	}
