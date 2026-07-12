class_name PFCanvasMinimapController
extends RefCounted

## Connects the pure minimap control to PFInfiniteCanvas state and navigation.

const CanvasMinimapScript := preload("res://ui/canvas/canvas_minimap.gd")
const MAP_SIZE := Vector2(220, 150)
const MAP_MARGIN := 12
const OVERLAY_Z_INDEX := 4094

var minimap: Control = null
var _canvas: Control = null


func setup(canvas: Control) -> void:
	_canvas = canvas
	minimap = CanvasMinimapScript.new()
	minimap.name = "CanvasMinimap"
	minimap.custom_minimum_size = MAP_SIZE
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -MAP_SIZE.x - MAP_MARGIN
	minimap.offset_top = MAP_MARGIN
	minimap.offset_right = -MAP_MARGIN
	minimap.offset_bottom = MAP_MARGIN + MAP_SIZE.y
	minimap.z_as_relative = false
	minimap.z_index = OVERLAY_Z_INDEX
	minimap.world_center_requested.connect(_canvas._center_on_world)
	_canvas.canvas_changed.connect(refresh)
	_canvas.zoom_changed.connect(func(_index: int, _zoom: float) -> void: refresh())
	_canvas.resized.connect(refresh)
	_canvas.add_child(minimap)
	refresh()


func refresh() -> void:
	if _canvas == null or minimap == null:
		return
	var items: Array = _canvas.export_canvas_data()["items"]
	for item in items:
		if not (item is Dictionary):
			continue
		var runtime_item: Node = _canvas._items_by_id.get(String(item.get("id", "")), null)
		if runtime_item != null and runtime_item.has_method("get_canvas_bounds"):
			item["bounds"] = runtime_item.get_canvas_bounds()
	minimap.set_canvas_snapshot(items, _canvas._content_bounds(), _canvas._viewport_world_rect())
