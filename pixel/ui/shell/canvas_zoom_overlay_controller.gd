class_name PFCanvasZoomOverlayController
extends RefCounted

## 主窗口缩放 overlay 接线器。
## 职责：把 PFCanvasZoomControl 挂到主窗口，并同步滑条输入与画布缩放状态。

const CanvasZoomControlScript := preload("res://ui/canvas/canvas_zoom_control.gd")
const InfiniteCanvasScript := preload("res://ui/canvas/infinite_canvas.gd")

var zoom_control: Control = null

var _canvas: Control = null


func setup(parent: Control, canvas: Control, bottom_left_margin: int) -> void:
	_canvas = canvas

	zoom_control = CanvasZoomControlScript.new()
	zoom_control.name = "ZoomControl"
	zoom_control.configure_levels(InfiniteCanvasScript.ZOOM_LEVELS.size())
	zoom_control.set_bottom_left_margin(bottom_left_margin)
	zoom_control.zoom_index_requested.connect(_on_zoom_index_requested)
	parent.add_child(zoom_control)

	_canvas.zoom_changed.connect(_sync_from_canvas)
	_sync_from_canvas(_canvas.zoom_index, _canvas.camera_zoom)


func _on_zoom_index_requested(index: int) -> void:
	if _canvas == null:
		return
	var target_index := clampi(index, 0, InfiniteCanvasScript.ZOOM_LEVELS.size() - 1)
	_canvas.set_camera_zoom(float(InfiniteCanvasScript.ZOOM_LEVELS[target_index]))


func _sync_from_canvas(index: int, zoom: float) -> void:
	if zoom_control == null:
		return
	zoom_control.set_zoom_state(index, zoom)
