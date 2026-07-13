# gdlint: disable=max-file-lines
class_name PFInfiniteCanvas
extends Control

## 职责：平移、缩放、sprite 元素增删选移、框选、网格和视口剔除；保存格式直接导出 canvas.json 结构。

signal canvas_changed
signal selection_changed(selected_ids: Array)
signal cleanup_grid_changed(scale: float, offset: Vector2)
signal batch_context_requested(card_id: String, screen_position: Vector2i)
signal graph_quick_add_requested(screen_position: Vector2i)
signal zoom_changed(zoom_index: int, camera_zoom: float)
signal graph_connect_failed(reason: String)
signal graph_status(event: Dictionary)
signal asset_edit_requested(asset_id: String, batch_id: String)
signal graph_node_params_commit_requested(graph_id: String, node_id: String, params: Dictionary)
signal graph_node_action_requested(graph_id: String, node_id: String, action_id: String)
signal batch_run_action_requested(graph_id: String, node_id: String, action_id: String)
signal batch_face_action_requested(card_id: String, action_id: String, asset_ids: Array)
signal project_resource_dropped(resource: Dictionary, world_position: Vector2)
signal image_paste_requested(world_position: Vector2)

const ZOOM_LEVELS := [0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 16.0, 32.0]
const DEFAULT_ZOOM_INDEX := 4
const WHEEL_ZOOM_MIN_INTERVAL_MSEC := 80
const CULL_INTERVAL_SECONDS := 0.1
const CULL_PADDING_PIXELS := 128.0
const GRID_MIN_ZOOM := 4.0
const FRAME_PADDING := 40.0
const SELECTION_COLOR := Color(0.1, 0.85, 0.65, 1.0)
const BOX_COLOR := Color(1.0, 0.85, 0.25, 0.35)
const BACKGROUND_COLOR := Color(0.105, 0.11, 0.12, 1.0)
const EDGE_COLOR := Color(0.42, 0.58, 0.62, 0.9)
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const CanvasItemFrameScript := preload("res://ui/canvas/canvas_item_frame.gd")
const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
const GraphEdgeInteraction := preload("res://ui/canvas/canvas_graph_edge_interaction.gd")
const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
const GraphClipboard := preload("res://core/graph/canvas_graph_clipboard.gd")
const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")
const LODCoordinator := preload("res://ui/canvas/canvas_lod_coordinator.gd")
const BatchOps := preload("res://ui/canvas/canvas_batch_ops.gd")
const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
const SelectionSnapshot := preload("res://ui/canvas/canvas_selection_snapshot.gd")
const ScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
const CleanupGridOverlayScript := preload("res://ui/canvas/cleanup_grid_overlay.gd")
const PixelGridRenderer := preload("res://ui/canvas/canvas_pixel_grid_renderer.gd")
const ToolInputPolicy := preload("res://ui/canvas/canvas_tool_input_policy.gd")
const ToolTarget := preload("res://ui/canvas/canvas_tool_target.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")
const Log := preload("res://core/util/log_util.gd")
const Strings := preload("res://ui/shell/strings.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")

var camera_center := Vector2.ZERO
var zoom_index := DEFAULT_ZOOM_INDEX
var camera_zoom := float(ZOOM_LEVELS[DEFAULT_ZOOM_INDEX])

var item_layer := Node2D.new()
var tool_manager: Variant = null

var _viewport_scale_factor_override := 0.0
var _items_by_id := {}
var _unrendered_items: Array[Dictionary] = []
var _selection: Variant = CanvasSelectionScript.new()
var _cleanup_grid_overlay: Control = null
var _cleanup_grid_active := false
var _cleanup_grid_scale := 4.0
var _cleanup_grid_offset := Vector2.ZERO
var _cleanup_preview: Variant = CanvasCleanupPreviewScript.new()
var _is_panning := false
var _cull_elapsed := 0.0
var _suppress_change_signal := false
var _last_wheel_zoom_msec := -1000000
var _graph_edge_drag := {}
var _graph_edge_drag_world := Vector2.ZERO
var _selected_graph_edge := {}
var _graph_clipboard := {}
var _graph_edge_preview_signature := ""
var _graph_edges_visible := true
var _resize_drag := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_selection.selection_changed.connect(_on_selection_changed)

	item_layer.name = "ItemLayer"
	item_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(item_layer)

	_cleanup_grid_overlay = CleanupGridOverlayScript.new()
	_cleanup_grid_overlay.name = "CleanupGridOverlay"
	_cleanup_grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cleanup_grid_overlay.set_canvas(self)
	_cleanup_grid_overlay.grid_changed.connect(_on_cleanup_grid_changed)
	add_child(_cleanup_grid_overlay)

	_update_layer_transform()
	set_process(true)


func _process(delta: float) -> void:
	_cull_elapsed += delta
	if _cull_elapsed >= CULL_INTERVAL_SECONDS:
		_cull_elapsed = 0.0
		_update_item_visibility()
	_cleanup_preview.update_alt_state()
	if tool_manager != null and tool_manager.needs_redraw():
		queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _cleanup_grid_overlay != null:
			_cleanup_grid_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_update_layer_transform()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		graph_quick_add_requested.emit(Vector2i(get_screen_position() + get_local_mouse_position()))
		accept_event()
	elif _tool_manager_handles(event):
		accept_event()
		queue_redraw()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventPanGesture:
		pan_by_pixels(event.delta)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.keycode == KEY_ESCAPE and not _resize_drag.is_empty():
		_cancel_resize_drag()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if not _selected_graph_edge.is_empty():
			var delete_result := GraphEdgeInteraction.delete_edge(
				_selected_graph_edge, _emit_canvas_changed
			)
			if bool(delete_result.get("ok", false)):
				graph_status.emit({"type": "edge_deleted", "edge": delete_result.get("edge", {})})
			_selected_graph_edge = {}
			queue_redraw()
		else:
			delete_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z and event.is_command_or_control_pressed():
		if event.shift_pressed:
			UndoService.redo()
		else:
			UndoService.undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_C and event.is_command_or_control_pressed():
		_copy_selected_graph_nodes()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_V and event.is_command_or_control_pressed():
		if _graph_clipboard.is_empty():
			image_paste_requested.emit(get_mouse_world_position())
		else:
			_paste_graph_clipboard_at(get_mouse_world_position())
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_D and event.is_command_or_control_pressed():
		_duplicate_selected_graph_nodes()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_G and event.is_command_or_control_pressed():
		if event.shift_pressed:
			_ungroup_selected()
		else:
			_group_selected_nodes()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_0 and event.is_command_or_control_pressed():
		_focus_item_ids(_items_by_id.keys())
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	if (
		ScalePolicy.compute_art_physical_scale(camera_zoom, _resolve_viewport_scale_factor())
		>= GRID_MIN_ZOOM
	):
		PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
	if _graph_edges_visible:
		GraphEdgeInteraction.draw_edges(
			self,
			GraphEdgeRenderer,
			_items_by_id,
			CanvasBatchCardScript,
			CanvasNodeCardScript,
			EDGE_COLOR,
			_selected_graph_edge,
			_graph_edge_drag,
			_graph_edge_drag_world
		)
	elif not _graph_edge_drag.is_empty():
		GraphEdgeInteraction.draw_preview(
			self, GraphEdgeRenderer, _graph_edge_drag, _graph_edge_drag_world
		)

	SelectionSnapshot.draw_overlay(self, _items_by_id, _selection, SELECTION_COLOR, BOX_COLOR)

	if tool_manager != null:
		tool_manager.draw_overlay(self, _get_active_tool_target())


func add_sprite_item(
	image: Image,
	asset_id: String = "",
	world_position: Vector2 = Vector2.ZERO,
	item_id: String = "",
	record_undo: bool = true
) -> Node:
	var data := {
		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(round(world_position.x)), int(round(world_position.y))],
		"scale_factor": 1,
		"z_index": _items_by_id.size(),
		"locked": false,
		"frame_id": null,
	}
	var image_copy: Image = ImageMath.duplicate_rgba8(image)

	var do_add := func() -> void:
		_add_sprite_direct(data, image_copy)
		_select_only([String(data["id"])])
		_emit_canvas_changed()

	var undo_add := func() -> void:
		_remove_item_direct(String(data["id"]))
		_clear_selection()
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action(
			"Add sprite", do_add, undo_add, ImageMath.estimate_rgba8_bytes(image_copy)
		)
	else:
		do_add.call()

	return _items_by_id.get(String(data["id"]), null)


func _add_batch_card(
	asset_ids: Array,
	world_position: Vector2 = Vector2.ZERO,
	label: String = "Batch",
	item_id: String = "",
	record_undo: bool = true,
	graph_id: String = "",
	node_id: String = ""
) -> Node:
	var data := {
		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
		"type": "node" if not node_id.is_empty() else "batch_card",
		"asset_ids": asset_ids.duplicate(),
		"selected_asset_ids": [],
		"label": label,
		"graph_id": graph_id,
		"node_id": node_id,
		"position": [int(round(world_position.x)), int(round(world_position.y))],
		"z_index": _items_by_id.size(),
		"locked": false,
	}

	var do_add := func() -> void:
		_add_batch_direct(data)
		_select_only([String(data["id"])])
		_emit_canvas_changed()

	var undo_add := func() -> void:
		_remove_item_direct(String(data["id"]))
		_clear_selection()
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action("Add batch", do_add, undo_add)
	else:
		do_add.call()

	return _items_by_id.get(String(data["id"]), null)


func _add_graph_node_card(
	graph_id: String,
	node_id: String,
	world_position: Vector2 = Vector2.ZERO,
	item_id: String = "",
	record_undo: bool = true
) -> Node:
	var data := {
		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
		"type": "node",
		"graph_id": graph_id,
		"node_id": node_id,
		"position": [int(round(world_position.x)), int(round(world_position.y))],
		"z_index": _items_by_id.size(),
		"collapsed": false,
		"locked": false,
	}

	var do_add := func() -> void:
		_add_node_direct(data)
		_select_only([String(data["id"])])
		_emit_canvas_changed()

	var undo_add := func() -> void:
		_remove_item_direct(String(data["id"]))
		_clear_selection()
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action("Add node", do_add, undo_add)
	else:
		do_add.call()

	return _items_by_id.get(String(data["id"]), null)


func _refresh_graph_node_card(graph_id: String, node_id: String) -> bool:
	var refreshed := false
	for item in _items_by_id.values():
		if item.get_script() != CanvasNodeCardScript:
			continue
		if item.graph_id != graph_id or item.node_id != node_id:
			continue
		item.refresh_from_graph()
		refreshed = true
	if refreshed:
		queue_redraw()
		selection_changed.emit(_selection.get_selected_ids())
	return refreshed


func _refresh_graph_batch_card(graph_id: String, node_id: String) -> bool:
	for item in _items_by_id.values():
		if (
			item.get_script() == CanvasBatchCardScript
			and item.graph_id == graph_id
			and item.node_id == node_id
		):
			item._refresh_from_graph()
			queue_redraw()
			return true
	return false


func _set_graph_node_type_status(
	graph_id: String, node_type: String, status: String, detail: String = ""
) -> void:
	var matching_ids := []
	for raw_node in ProjectService.get_graph_data(graph_id).get("nodes", []):
		if raw_node is Dictionary and String(raw_node.get("type", "")) == node_type:
			matching_ids.append(String(raw_node.get("id", "")))
	for item in _items_by_id.values():
		if (
			item.get_script() == CanvasNodeCardScript
			and item.graph_id == graph_id
			and matching_ids.has(item.node_id)
		):
			item.set_execution_status(status, detail)


func _set_graph_node_status(
	graph_id: String, node_id: String, status: String, detail: String = ""
) -> void:
	for item in _items_by_id.values():
		if (
			item.get_script() == CanvasNodeCardScript
			and item.graph_id == graph_id
			and item.node_id == node_id
		):
			item.set_execution_status(status, detail)


func delete_selected(record_undo: bool = true) -> void:
	if _selection.is_empty():
		return

	var snapshots := []
	for item_id in _selection.get_selected_ids():
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		var snapshot := {"data": item.to_canvas_data()}
		if item.get_script() == CanvasItemSpriteScript:
			snapshot["image"] = item.duplicate_image()
		elif item.get_script() == CanvasItemFrameScript:
			snapshot["member_ids"] = _frame_member_item_ids(item.item_id)
		snapshots.append(snapshot)

	if snapshots.is_empty():
		return

	var graph_snapshots := GraphItemBridge.graph_deletion_snapshots_for_canvas_snapshots(snapshots)
	var graph_delete_counts := GraphItemBridge.deletion_counts(graph_snapshots)

	var do_delete := func() -> void:
		GraphItemBridge.apply_graph_deletion_snapshots(graph_snapshots, "after")
		for snapshot in snapshots:
			if String(snapshot["data"].get("type", "")) == "frame":
				_set_frame_membership(snapshot.get("member_ids", []), null)
			_remove_item_direct(String(snapshot["data"]["id"]))
		_clear_selection()
		_emit_canvas_changed()
		if int(graph_delete_counts.get("nodes", 0)) > 0:
			(
				graph_status
				. emit(
					{
						"type": "nodes_deleted",
						"nodes": int(graph_delete_counts.get("nodes", 0)),
						"edges": int(graph_delete_counts.get("edges", 0)),
					}
				)
			)

	var undo_delete := func() -> void:
		GraphItemBridge.apply_graph_deletion_snapshots(graph_snapshots, "before")
		for snapshot in snapshots:
			var data: Dictionary = snapshot["data"]
			if String(data.get("type", "")) == "sprite":
				_add_sprite_direct(data, snapshot["image"])
			elif (
				String(data.get("type", "")) == "batch_card"
				or GraphItemBridge.is_graph_batch_node_data(data)
			):
				_add_batch_direct(data)
			elif String(data.get("type", "")) == "node":
				_add_node_direct(data)
			elif String(data.get("type", "")) == "frame":
				_add_frame_direct(data)
		for snapshot in snapshots:
			if String(snapshot["data"].get("type", "")) == "frame":
				_set_frame_membership(
					snapshot.get("member_ids", []), String(snapshot["data"].get("id", ""))
				)
		_select_only(SelectionSnapshot.ids_from_snapshots(snapshots))
		_emit_canvas_changed()

	var memory_cost := 0
	for snapshot in snapshots:
		if snapshot.has("image"):
			memory_cost += ImageMath.estimate_rgba8_bytes(snapshot["image"])

	if record_undo:
		UndoService.perform_action("Delete canvas selection", do_delete, undo_delete, memory_cost)
	else:
		do_delete.call()


func clear_canvas() -> void:
	_suppress_change_signal = true
	for item in _items_by_id.values():
		item.queue_free()
	_items_by_id.clear()
	_unrendered_items.clear()
	clear_cleanup_preview()
	hide_cleanup_grid_overlay()
	_selection.clear(false)
	_suppress_change_signal = false
	queue_redraw()


func load_canvas_data(canvas_data: Dictionary) -> void:
	clear_canvas()
	_suppress_change_signal = true

	var camera: Dictionary = canvas_data.get("camera", {})
	var center: Variant = camera.get("center", [0, 0])
	camera_center = Vector2(float(center[0]), float(center[1]))
	_set_zoom_to_value(float(camera.get("zoom", 1.0)))

	for item_data in canvas_data.get("items", []):
		var item_type := String(item_data.get("type", ""))
		if item_type == "sprite":
			var asset_id := String(item_data.get("asset_id", ""))
			var image := AssetLibrary.get_image(asset_id)
			if image == null:
				Log.warn("Canvas sprite uses an unavailable asset", {"asset_id": asset_id})
				_unrendered_items.append(Dictionary(item_data).duplicate(true))
				continue
			_add_sprite_direct(item_data, image)
		elif item_type == "batch_card":
			_add_batch_direct(item_data)
		elif item_type == "node" and GraphItemBridge.is_graph_batch_node_data(item_data):
			_add_batch_direct(item_data)
		elif item_type == "node":
			_add_node_direct(item_data)
		elif item_type == "frame":
			_add_frame_direct(item_data)

	_suppress_change_signal = false
	_update_layer_transform()
	_update_item_visibility()
	_emit_zoom_changed()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and String(data.get("kind", "")) in ["project_asset", "style_preset", "workflow_template"]
	)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	project_resource_dropped.emit(Dictionary(data).duplicate(true), screen_to_world(at_position))
	_emit_zoom_changed()
	queue_redraw()


func export_canvas_data() -> Dictionary:
	var items := _unrendered_items.duplicate(true)
	var nodes := item_layer.get_children()
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return a.z_index < b.z_index)

	for node in nodes:
		if node.get_script() == CanvasItemSpriteScript:
			items.append(node.to_canvas_data())
		elif node.get_script() == CanvasBatchCardScript:
			items.append(node.to_canvas_data())
		elif node.get_script() == CanvasNodeCardScript:
			items.append(node.to_canvas_data())
		elif node.get_script() == CanvasItemFrameScript:
			items.append(node.to_canvas_data())

	return {
		"camera":
		{
			"center": [int(round(camera_center.x)), int(round(camera_center.y))],
			"zoom": camera_zoom,
		},
		"items": items,
	}


func screen_to_world(screen_position: Vector2) -> Vector2:
	return (screen_position - item_layer.position) / _get_art_logical_scale()


func world_to_screen(world_position: Vector2) -> Vector2:
	return item_layer.position + world_position * _get_art_logical_scale()


func _world_rect_to_screen(world_rect: Rect2) -> Rect2:
	return Rect2(world_to_screen(world_rect.position), world_rect.size * _get_art_logical_scale())


func get_mouse_world_position() -> Vector2:
	return screen_to_world(get_local_mouse_position()).round()


func pan_by_pixels(pixel_delta: Vector2) -> void:
	var target_position := item_layer.position - pixel_delta
	var snapped_position := ScalePolicy.snap_position_to_physical_pixel(
		target_position, _resolve_viewport_scale_factor()
	)
	camera_center = ScalePolicy.camera_center_from_layer_position(
		size, snapped_position, _get_art_logical_scale()
	)
	_update_layer_transform()
	_emit_canvas_changed()


func set_camera_zoom(value: float, screen_anchor: Vector2 = size * 0.5) -> void:
	var anchor_world := screen_to_world(screen_anchor)
	var old_zoom := camera_zoom
	_set_zoom_to_value(value)
	if is_equal_approx(old_zoom, camera_zoom):
		_emit_zoom_changed()
		return
	camera_center = _camera_center_for_snapped_anchor(anchor_world, screen_anchor)
	_update_layer_transform()
	_emit_canvas_changed()
	_emit_zoom_changed()


func zoom_by_steps(step_delta: int, screen_anchor: Vector2) -> void:
	var old_zoom := camera_zoom
	var anchor_world := screen_to_world(screen_anchor)
	zoom_index = clampi(zoom_index + step_delta, 0, ZOOM_LEVELS.size() - 1)
	camera_zoom = float(ZOOM_LEVELS[zoom_index])
	if is_equal_approx(old_zoom, camera_zoom):
		_emit_zoom_changed()
		return
	camera_center = _camera_center_for_snapped_anchor(anchor_world, screen_anchor)
	_update_layer_transform()
	_emit_canvas_changed()
	_emit_zoom_changed()


func get_item_count() -> int:
	return _items_by_id.size()


func get_selected_ids() -> Array:
	return _selection.get_selected_ids()


func _set_graph_edges_visible(value: bool) -> void:
	_graph_edges_visible = value
	if not value:
		_selected_graph_edge = {}
	queue_redraw()


func _toggle_graph_edges() -> bool:
	_set_graph_edges_visible(not _graph_edges_visible)
	return _graph_edges_visible


func _are_graph_edges_visible() -> bool:
	return _graph_edges_visible


func _focus_item_ids(item_ids: Array) -> bool:
	var bounds := Rect2()
	var has_bounds := false
	for raw_id in item_ids:
		var item: Node = _items_by_id.get(String(raw_id), null)
		if item == null or not item.has_method("get_canvas_bounds"):
			continue
		var item_bounds: Rect2 = item.get_canvas_bounds()
		bounds = item_bounds if not has_bounds else bounds.merge(item_bounds)
		has_bounds = true
	if not has_bounds or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or size.is_zero_approx():
		return false
	var target_zoom := minf(size.x * 0.72 / bounds.size.x, size.y * 0.72 / bounds.size.y)
	set_camera_zoom(target_zoom, size * 0.5)
	pan_by_pixels(world_to_screen(bounds.get_center()) - size * 0.5)
	return true


func _content_bounds() -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for item in _items_by_id.values():
		if not item.has_method("get_canvas_bounds"):
			continue
		var item_bounds: Rect2 = item.get_canvas_bounds()
		bounds = item_bounds if not has_bounds else bounds.merge(item_bounds)
		has_bounds = true
	return bounds if has_bounds else Rect2(Vector2.ZERO, Vector2.ONE)


func _viewport_world_rect() -> Rect2:
	var world_origin := screen_to_world(Vector2.ZERO)
	return Rect2(world_origin, screen_to_world(size) - world_origin).abs()


func _center_on_world(world_center: Vector2) -> void:
	camera_center = world_center
	_update_layer_transform()
	_emit_canvas_changed()


func _copy_selected_graph_nodes() -> bool:
	var selected_ids: Array = _selection.get_selected_ids()
	var canvas_items: Array = export_canvas_data()["items"]
	var graph_id := ""
	for raw_item in canvas_items:
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		if selected_ids.has(String(item.get("id", ""))) and String(item.get("type", "")) == "node":
			graph_id = String(item.get("graph_id", ""))
			break
	if graph_id.is_empty():
		return false
	var payload: Dictionary = GraphClipboard.capture(
		ProjectService.get_graph_data(graph_id), canvas_items, selected_ids
	)
	if not bool(payload.get("ok", false)):
		return false
	_graph_clipboard = payload
	graph_status.emit({"type": "selection_copied", "count": payload["items"].size()})
	return true


func _paste_graph_clipboard_at(target_position: Vector2) -> bool:
	if _graph_clipboard.is_empty():
		return false
	var graph_id := String(_graph_clipboard.get("graph_id", ""))
	var before: Dictionary = ProjectService.get_graph_data(graph_id)
	if before.is_empty():
		graph_status.emit({"type": "clipboard_failed", "reason": "source_graph_unavailable"})
		return false
	var instance: Dictionary = GraphClipboard.instantiate(_graph_clipboard, target_position.round())
	if not bool(instance.get("ok", false)):
		return false
	var after := before.duplicate(true)
	var after_nodes: Array = after.get("nodes", []).duplicate(true)
	after_nodes.append_array(instance["nodes"])
	after["nodes"] = after_nodes
	var after_edges: Array = after.get("edges", []).duplicate(true)
	after_edges.append_array(instance["edges"])
	after["edges"] = after_edges
	var node_types := {}
	for raw_node in instance["nodes"]:
		if raw_node is Dictionary:
			node_types[String(raw_node.get("id", ""))] = String(raw_node.get("type", ""))
	var pasted_items: Array = instance["items"]
	for index in range(pasted_items.size()):
		pasted_items[index]["z_index"] = _items_by_id.size() + index
	var pasted_item_ids := []
	for item in pasted_items:
		pasted_item_ids.append(String(item.get("id", "")))
	var do_paste := func() -> void:
		ProjectService.set_graph_data(graph_id, after, true)
		for item in pasted_items:
			if node_types.get(String(item.get("node_id", "")), "") == "batch":
				_add_batch_direct(item)
			else:
				_add_node_direct(item)
		_select_only(pasted_item_ids)
		_emit_canvas_changed()
	var undo_paste := func() -> void:
		for item_id in pasted_item_ids:
			_remove_item_direct(item_id)
		ProjectService.set_graph_data(graph_id, before, true)
		_select_only([])
		_emit_canvas_changed()
	UndoService.perform_action("Paste graph selection", do_paste, undo_paste)
	graph_status.emit({"type": "selection_pasted", "count": pasted_item_ids.size()})
	return true


func _duplicate_selected_graph_nodes() -> bool:
	if not _copy_selected_graph_nodes():
		return false
	var anchor: Array = _graph_clipboard.get("anchor", [0, 0])
	return _paste_graph_clipboard_at(Vector2(float(anchor[0]), float(anchor[1])) + Vector2(32, 32))


func _group_selected_nodes() -> bool:
	var member_ids := []
	var graph_id := ""
	var bounds := Rect2()
	var has_bounds := false
	for item_id in _selection.get_selected_ids():
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		if item.get_script() not in [CanvasNodeCardScript, CanvasBatchCardScript]:
			continue
		var item_graph_id := String(item.graph_id)
		if graph_id.is_empty():
			graph_id = item_graph_id
		elif graph_id != item_graph_id:
			graph_status.emit({"type": "group_failed", "reason": "cross_graph"})
			return false
		member_ids.append(item_id)
		bounds = (
			item.get_canvas_bounds() if not has_bounds else bounds.merge(item.get_canvas_bounds())
		)
		has_bounds = true
	if member_ids.size() < 2 or graph_id.is_empty():
		graph_status.emit({"type": "group_failed", "reason": "needs_multiple_nodes"})
		return false
	var frame_id := IdUtil.uuid_v4()
	var previous_membership := {}
	for item_id in member_ids:
		previous_membership[item_id] = _items_by_id[item_id].frame_id
	var frame_rect := bounds.grow(FRAME_PADDING)
	var frame_data := {
		"id": frame_id,
		"type": "frame",
		"graph_id": graph_id,
		"title": Strings.text("FRAME_DEFAULT_TITLE"),
		"color": "4f6f8fff",
		"position": [int(round(frame_rect.position.x)), int(round(frame_rect.position.y))],
		"size": [int(round(frame_rect.size.x)), int(round(frame_rect.size.y))],
		"z_index": -1,
	}
	var do_group := func() -> void:
		_add_frame_direct(frame_data)
		_set_frame_membership(member_ids, frame_id)
		_select_only([frame_id])
		_emit_canvas_changed()
	var undo_group := func() -> void:
		for item_id in previous_membership:
			_set_item_frame_id(item_id, previous_membership[item_id])
		_remove_item_direct(frame_id)
		_select_only(member_ids)
		_emit_canvas_changed()
	UndoService.perform_action("Group canvas nodes", do_group, undo_group)
	graph_status.emit({"type": "nodes_grouped", "frame_id": frame_id, "count": member_ids.size()})
	return true


func _ungroup_selected() -> bool:
	var frame_ids := []
	for item_id in _selection.get_selected_ids():
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		if item.get_script() == CanvasItemFrameScript:
			frame_ids.append(item.item_id)
		elif item.get_script() in [CanvasNodeCardScript, CanvasBatchCardScript]:
			var frame_id := "" if item.frame_id == null else String(item.frame_id)
			if not frame_id.is_empty() and not frame_ids.has(frame_id):
				frame_ids.append(frame_id)
	if frame_ids.is_empty():
		return false
	var frame_snapshots := []
	for frame_id in frame_ids:
		if _items_by_id.has(frame_id):
			(
				frame_snapshots
				. append(
					{
						"data": _items_by_id[frame_id].to_canvas_data(),
						"member_ids": _frame_member_item_ids(frame_id),
					}
				)
			)
	var do_ungroup := func() -> void:
		for snapshot in frame_snapshots:
			_set_frame_membership(snapshot["member_ids"], null)
			_remove_item_direct(String(snapshot["data"]["id"]))
		_select_only([])
		_emit_canvas_changed()
	var undo_ungroup := func() -> void:
		var restored_ids := []
		for snapshot in frame_snapshots:
			_add_frame_direct(snapshot["data"])
			var frame_id := String(snapshot["data"]["id"])
			_set_frame_membership(snapshot["member_ids"], frame_id)
			restored_ids.append(frame_id)
		_select_only(restored_ids)
		_emit_canvas_changed()
	UndoService.perform_action("Ungroup canvas nodes", do_ungroup, undo_ungroup)
	graph_status.emit({"type": "nodes_ungrouped", "count": frame_snapshots.size()})
	return true


func _frame_member_item_ids(frame_id: String) -> Array:
	var result := []
	for item_id in _items_by_id:
		var item: Node = _items_by_id[item_id]
		if item.get_script() not in [CanvasNodeCardScript, CanvasBatchCardScript]:
			continue
		if item.frame_id != null and String(item.frame_id) == frame_id:
			result.append(item_id)
	return result


func _set_frame_membership(member_ids: Array, frame_id: Variant) -> void:
	for item_id in member_ids:
		_set_item_frame_id(String(item_id), frame_id)


func _set_item_frame_id(item_id: String, frame_id: Variant) -> void:
	if not _items_by_id.has(item_id):
		return
	var item: Node = _items_by_id[item_id]
	if item.get_script() in [CanvasNodeCardScript, CanvasBatchCardScript]:
		item.frame_id = frame_id


func select_ids(ids: Array) -> void:
	_select_only(ids)


func get_selected_sprite_snapshots() -> Array:
	var snapshots := []
	for item_id in _selection.get_selected_ids():
		if not _items_by_id.has(item_id):
			continue
		var item: Node = _items_by_id[item_id]
		if item.get_script() != CanvasItemSpriteScript:
			continue
		snapshots.append({"data": item.to_canvas_data(), "image": item.duplicate_image()})
	return snapshots


func _get_active_tool_target() -> Dictionary:
	return ToolTarget.active_target(_items_by_id, _selection, CanvasItemSpriteScript)


func _get_batch_asset_ids(card_id: String, selected_only: bool = false) -> Array:
	return BatchOps.get_asset_ids(_items_by_id, card_id, selected_only)


func _get_batch_selected_asset_ids(card_id: String) -> Array:
	return BatchOps.get_selected_asset_ids(_items_by_id, card_id)


func _set_batch_review_filter(
	card_id: String, review_filter: String, record_undo: bool = true
) -> bool:
	return BatchOps.set_review_filter(
		_items_by_id, card_id, review_filter, record_undo, _select_only, _emit_canvas_changed
	)


func _set_batch_review_layout(
	card_id: String, review_layout: String, record_undo: bool = true
) -> bool:
	return BatchOps.set_review_layout(
		_items_by_id, card_id, review_layout, record_undo, _select_only, _emit_canvas_changed
	)


func _replace_batch_asset_ids(
	card_id: String, new_asset_ids: Array, record_undo: bool = true, compare_asset_ids: Array = []
) -> void:
	BatchOps.replace_asset_ids(
		_items_by_id,
		card_id,
		new_asset_ids,
		record_undo,
		compare_asset_ids,
		_select_only,
		_emit_canvas_changed
	)


func _set_batch_compare_mode(
	card_id: String, compare_mode: String, record_undo: bool = true
) -> bool:
	return BatchOps.set_compare_mode(
		_items_by_id, card_id, compare_mode, record_undo, _select_only, _emit_canvas_changed
	)


func _set_batch_review_state(
	card_id: String, asset_ids: Array, review_state: String, record_undo: bool = true
) -> int:
	return BatchOps.set_review_state(
		_items_by_id,
		card_id,
		asset_ids,
		review_state,
		record_undo,
		_select_only,
		_emit_canvas_changed
	)


func _focus_batch_relative(card_id: String, step: int, record_undo: bool = true) -> Dictionary:
	return BatchOps.focus_relative(
		_items_by_id, card_id, step, record_undo, _select_only, _emit_canvas_changed
	)


func _split_batch_selection(card_id: String) -> Node:
	var spec: Dictionary = BatchOps.split_selection_spec(_items_by_id, card_id)
	if spec.is_empty():
		return null
	return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)


func _split_batch_marked(card_id: String, review_state: String, label_suffix: String) -> Node:
	var spec: Dictionary = BatchOps.split_marked_spec(
		_items_by_id, card_id, review_state, label_suffix
	)
	if spec.is_empty():
		return null
	return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)


func show_cleanup_preview(
	source_item_id: String, preview_image: Image, opacity: float = 0.56
) -> void:
	_cleanup_preview.show(item_layer, _items_by_id, source_item_id, preview_image, opacity)


func clear_cleanup_preview() -> void:
	_cleanup_preview.clear()


func show_cleanup_grid_overlay(scale: float, offset: Vector2) -> void:
	_cleanup_grid_active = true
	_cleanup_grid_scale = maxf(1.0, scale)
	_cleanup_grid_offset = offset
	_sync_cleanup_grid_overlay()


func hide_cleanup_grid_overlay() -> void:
	_cleanup_grid_active = false
	_sync_cleanup_grid_overlay()


func move_selected_by(delta: Vector2, record_undo: bool = true) -> void:
	if _selection.is_empty():
		return

	var before := _expanded_selected_positions()
	var after := {}
	var snapped_delta := delta.round()
	for item_id in before.keys():
		after[item_id] = (Vector2(before[item_id]) + snapped_delta).round()

	if SelectionSnapshot.positions_equal(before, after):
		return

	var ids: Array = _selection.get_selected_ids()
	var do_move := func() -> void:
		_apply_positions(after)
		_select_only(ids)
		_emit_canvas_changed()

	var undo_move := func() -> void:
		_apply_positions(before)
		_select_only(ids)
		_emit_canvas_changed()

	if record_undo:
		UndoService.perform_action("Move canvas selection", do_move, undo_move)
	else:
		do_move.call()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_handle_wheel_zoom(1, event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_handle_wheel_zoom(-1, event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_panning = event.pressed
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_emit_context_request(event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if Input.is_key_pressed(KEY_SPACE):
			_is_panning = event.pressed
		elif event.pressed and event.double_click:
			if (
				not _focus_low_lod_item_at(event.position)
				and not _reset_resize_handle_at(event.position)
				and not _emit_asset_edit_request(event.position)
			):
				graph_quick_add_requested.emit(
					Vector2i(get_screen_position()) + Vector2i(event.position)
				)
		elif event.pressed:
			_begin_left_interaction(event.position, event.shift_pressed)
		else:
			_finish_left_interaction(event.position)
		accept_event()


func _focus_low_lod_item_at(screen_position: Vector2) -> bool:
	if camera_zoom >= 0.75:
		return false
	var hit := _hit_at_world(screen_to_world(screen_position))
	var item: Node = hit.get("item", null)
	if item == null:
		return false
	var bounds: Rect2 = item.get_canvas_bounds()
	if item.get_script() == CanvasItemFrameScript:
		var target := minf(size.x * 0.72 / bounds.size.x, size.y * 0.72 / bounds.size.y)
		var fit_zoom := float(ZOOM_LEVELS[0])
		for level in ZOOM_LEVELS:
			if float(level) > target:
				break
			fit_zoom = float(level)
		set_camera_zoom(fit_zoom, size * 0.5)
	else:
		set_camera_zoom(1.0, size * 0.5)
	_center_on_world(bounds.get_center())
	return true


func _emit_asset_edit_request(screen_position: Vector2) -> bool:
	var hit := _hit_at_world(screen_to_world(screen_position))
	var item: Node = hit.get("item", null)
	if item == null:
		return false
	if item.get_script() == CanvasItemSpriteScript:
		asset_edit_requested.emit(String(item.asset_id), "")
		return true
	if item.get_script() == CanvasBatchCardScript:
		var visible_ids: Array[String] = item.get_visible_asset_ids()
		var index := int(hit.get("asset_index", -1))
		if index >= 0 and index < visible_ids.size():
			asset_edit_requested.emit(visible_ids[index], String(item.item_id))
			return true
	return false


func _replace_asset_reference(old_asset_id: String, new_asset_id: String) -> int:
	var replacement: Image = AssetLibrary.get_image(new_asset_id)
	if replacement == null:
		return 0
	var count := 0
	for item in _items_by_id.values():
		if item.get_script() == CanvasItemSpriteScript and item.asset_id == old_asset_id:
			var data: Dictionary = item.to_canvas_data()
			data["asset_id"] = new_asset_id
			item.setup_from_image(data, replacement)
			count += 1
	if count > 0:
		_emit_canvas_changed()
	return count


func _handle_wheel_zoom(step_delta: int, screen_anchor: Vector2) -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_wheel_zoom_msec < WHEEL_ZOOM_MIN_INTERVAL_MSEC:
		return
	_last_wheel_zoom_msec = now_msec
	zoom_by_steps(step_delta, screen_anchor)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _graph_edge_drag.is_empty():
		var preview: Dictionary = GraphEdgeInteraction.connection_preview(
			self,
			_items_by_id,
			CanvasBatchCardScript,
			CanvasNodeCardScript,
			_graph_edge_drag,
			event.position
		)
		_graph_edge_drag["preview_state"] = String(preview.get("state", "none"))
		_graph_edge_drag_world = preview.get(
			"anchor", GraphEdgeInteraction.update_drag_world(self, event.position)
		)
		var signature := (
			"%s:%s:%s"
			% [
				String(preview.get("state", "none")),
				String(preview.get("item_id", "")),
				String(preview.get("reason", "")),
			]
		)
		if signature != _graph_edge_preview_signature:
			_graph_edge_preview_signature = signature
			(
				graph_status
				. emit(
					{
						"type": "connect_preview",
						"state": String(preview.get("state", "none")),
						"reason": String(preview.get("reason", "")),
						"item_id": String(preview.get("item_id", "")),
					}
				)
			)
		queue_redraw()
		accept_event()
	elif _is_panning:
		pan_by_pixels(-event.relative)
		accept_event()
	elif _selection.is_dragging_items:
		_drag_selected_to(screen_to_world(event.position))
		accept_event()
	elif not _resize_drag.is_empty():
		_preview_resize_drag(screen_to_world(event.position))
		accept_event()
	elif _selection.is_box_selecting:
		_selection.update_box(event.position)
		queue_redraw()
		accept_event()


func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
	var world_position := screen_to_world(screen_position)
	var hit := _hit_at_world(world_position)
	var hit_item: Node = hit.get("item", null)
	if hit_item != null:
		if (
			hit_item.has_method("resize_handle_contains_world")
			and hit_item.resize_handle_contains_world(world_position)
		):
			_select_only([hit_item.item_id])
			_resize_drag = {
				"item_id": hit_item.item_id,
				"start_world": world_position,
				"before": Vector2i(hit_item.requested_size),
			}
			queue_redraw()
			return
		if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
			if additive:
				_selection.toggle(hit_item.item_id, _items_by_id.keys())
			else:
				_select_only([hit_item.item_id])
			_graph_edge_drag = GraphEdgeInteraction.begin_drag(hit)
			_graph_edge_drag_world = world_position
			queue_redraw()
			return
		if (
			String(hit.get("kind", "")) == HitPolicy.KIND_BATCH_THUMBNAIL
			and hit_item.toggle_asset_at_world(world_position)
		):
			_select_only([hit_item.item_id])
			_emit_canvas_changed()
			return
		if additive:
			_selection.toggle(hit_item.item_id, _items_by_id.keys())
		elif not _selection.has(hit_item.item_id):
			_select_only([hit_item.item_id])

		if _selection.has(hit_item.item_id):
			var drag_positions := SelectionSnapshot.selected_positions(_items_by_id, _selection)
			if hit_item.get_script() == CanvasItemFrameScript:
				for member_id in _frame_member_item_ids(hit_item.item_id):
					if _items_by_id.has(member_id):
						drag_positions[member_id] = _items_by_id[member_id].position
			_selection.start_drag(world_position, drag_positions)
	else:
		if not _graph_edges_visible:
			if not additive:
				_clear_selection()
			_selection.start_box(screen_position, additive)
			queue_redraw()
			return
		var edge_hit := GraphEdgeRenderer.hit_edge_at_screen(
			self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, screen_position
		)
		if not edge_hit.is_empty():
			_selection.clear()
			_selected_graph_edge = edge_hit
			graph_status.emit({"type": "edge_selected", "edge": edge_hit.get("edge", {})})
			queue_redraw()
			return
		if not additive:
			_clear_selection()
		_selection.start_box(screen_position, additive)
	queue_redraw()


func _finish_left_interaction(screen_position: Vector2) -> void:
	if not _graph_edge_drag.is_empty():
		var start := _graph_edge_drag.duplicate(true)
		_graph_edge_drag = {}
		_graph_edge_preview_signature = ""
		var result := GraphEdgeInteraction.connect_at_screen(
			self,
			_items_by_id,
			CanvasBatchCardScript,
			CanvasNodeCardScript,
			start,
			screen_position,
			_emit_canvas_changed
		)
		var reason := String(result.get("reason", ""))
		if bool(result.get("ok", false)):
			graph_status.emit({"type": "connect_succeeded", "edge": result.get("edge", {})})
		elif not reason.is_empty():
			graph_connect_failed.emit(reason)
	elif _selection.is_dragging_items:
		_commit_drag_if_needed()
		_selection.stop_drag()
	elif not _resize_drag.is_empty():
		_commit_resize_drag()
	elif _selection.is_box_selecting:
		_selection.update_box(screen_position)
		_finish_box_selection()
		_selection.stop_box()

	queue_redraw()


func _preview_resize_drag(world_position: Vector2) -> void:
	var item_id := String(_resize_drag.get("item_id", ""))
	if not _items_by_id.has(item_id):
		_resize_drag = {}
		return
	var item: Node = _items_by_id[item_id]
	var before: Vector2i = _resize_drag.get("before", Vector2i.ZERO)
	var delta := (world_position - Vector2(_resize_drag["start_world"])).round()
	var next_size := before + Vector2i(delta)
	if bool(item.get("collapsed")):
		next_size.y = before.y
	item.set_requested_size(next_size)
	_update_item_visibility()
	queue_redraw()


func _commit_resize_drag() -> void:
	var drag := _resize_drag.duplicate(true)
	_resize_drag = {}
	var item_id := String(drag.get("item_id", ""))
	if not _items_by_id.has(item_id):
		return
	var item: Node = _items_by_id[item_id]
	var before: Vector2i = drag.get("before", Vector2i.ZERO)
	var after := Vector2i(item.requested_size)
	if before == after:
		return
	var apply := func(value: Vector2i) -> void:
		if _items_by_id.has(item_id):
			_items_by_id[item_id].set_requested_size(value)
			_update_item_visibility()
			_emit_canvas_changed()
	UndoService.perform_action(
		"Resize canvas card", func() -> void: apply.call(after), func() -> void: apply.call(before)
	)


func _cancel_resize_drag() -> void:
	var item_id := String(_resize_drag.get("item_id", ""))
	var before: Vector2i = _resize_drag.get("before", Vector2i.ZERO)
	_resize_drag = {}
	if _items_by_id.has(item_id):
		_items_by_id[item_id].set_requested_size(before)
		_update_item_visibility()
		queue_redraw()


func _reset_resize_handle_at(screen_position: Vector2) -> bool:
	var world_position := screen_to_world(screen_position)
	var hit := _hit_at_world(world_position)
	var item: Node = hit.get("item", null)
	if (
		item == null
		or not item.has_method("resize_handle_contains_world")
		or not item.resize_handle_contains_world(world_position)
		or not item.has_method("default_requested_size")
	):
		return false
	return _set_canvas_item_size(item.item_id, item.default_requested_size(), true)


func _drag_selected_to(world_position: Vector2) -> void:
	var delta: Vector2 = (world_position - _selection.drag_start_world).round()
	for item_id in _selection.drag_start_positions.keys():
		if _items_by_id.has(item_id) and _selection.drag_start_positions.has(item_id):
			var item: Node = _items_by_id[item_id]
			if not item.locked:
				item.position = (_selection.drag_start_positions[item_id] + delta).round()
	_sync_cleanup_grid_overlay()
	queue_redraw()


func _commit_drag_if_needed() -> void:
	var after_positions := _positions_for_ids(_selection.drag_start_positions.keys())
	if SelectionSnapshot.positions_equal(_selection.drag_start_positions, after_positions):
		return

	var before: Dictionary = _selection.drag_start_positions.duplicate(true)
	var after: Dictionary = after_positions.duplicate(true)
	var ids: Array = _selection.get_selected_ids()

	var do_move := func() -> void:
		_apply_positions(after)
		_select_only(ids)
		_emit_canvas_changed()

	var undo_move := func() -> void:
		_apply_positions(before)
		_select_only(ids)
		_emit_canvas_changed()

	UndoService.perform_action("Move canvas selection", do_move, undo_move, 0, false)
	_emit_canvas_changed()


func _positions_for_ids(item_ids: Array) -> Dictionary:
	var positions := {}
	for item_id in item_ids:
		if _items_by_id.has(item_id):
			positions[item_id] = _items_by_id[item_id].position
	return positions


func _expanded_selected_positions() -> Dictionary:
	var positions := SelectionSnapshot.selected_positions(_items_by_id, _selection)
	for selected_id in _selection.get_selected_ids():
		if not _items_by_id.has(selected_id):
			continue
		var item: Node = _items_by_id[selected_id]
		if item.get_script() != CanvasItemFrameScript:
			continue
		for member_id in _frame_member_item_ids(item.item_id):
			if _items_by_id.has(member_id):
				positions[member_id] = _items_by_id[member_id].position
	return positions


func _finish_box_selection() -> void:
	var screen_box: Rect2 = _selection.get_box_rect()
	var world_a := screen_to_world(screen_box.position)
	var world_b := screen_to_world(screen_box.position + screen_box.size)
	var world_box := Rect2(world_a, world_b - world_a).abs()

	var selected: Array = _selection.get_selected_ids() if _selection.box_additive else []
	for item in _items_by_id.values():
		if world_box.intersects(item.get_canvas_bounds()):
			if not selected.has(item.item_id):
				selected.append(item.item_id)
	_select_only(selected)


func _add_sprite_direct(item_data: Dictionary, image: Image) -> Node:
	var item: Node = CanvasItemSpriteScript.new()
	item.setup_from_image(item_data, image)
	item.display_title_change_requested.connect(_set_canvas_item_display_title)
	item.size_change_requested.connect(_set_canvas_item_size)
	item.set_lod_camera_zoom(camera_zoom)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	if not item.asset_id.is_empty():
		AssetLibrary.add_ref(item.asset_id)
	_update_item_visibility()
	queue_redraw()
	return item


func _add_batch_direct(item_data: Dictionary) -> Node:
	var item: Node = CanvasBatchCardScript.new()
	item.setup_from_data(item_data)
	item.collapsed_change_requested.connect(_set_batch_collapsed)
	item.display_title_change_requested.connect(_set_canvas_item_display_title)
	item.size_change_requested.connect(_set_canvas_item_size)
	item.run_action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			_select_only([item.item_id])
			batch_run_action_requested.emit(graph_id, node_id, action_id)
	)
	item.face_action_requested.connect(_on_batch_face_action_requested)
	item.set_lod_camera_zoom(camera_zoom)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	for asset_id in item.asset_ids:
		AssetLibrary.add_ref(asset_id)
	_update_item_visibility()
	queue_redraw()
	return item


func _on_batch_face_action_requested(card_id: String, action_id: String, asset_ids: Array) -> void:
	_select_only([card_id])
	match action_id:
		"filter_all":
			_set_batch_review_filter(card_id, CanvasBatchCardScript.FILTER_ALL, true)
		"filter_pending":
			_set_batch_review_filter(card_id, CanvasBatchCardScript.FILTER_PENDING, true)
		"filter_keep":
			_set_batch_review_filter(card_id, CanvasBatchCardScript.REVIEW_KEEP, true)
		"filter_reject":
			_set_batch_review_filter(card_id, CanvasBatchCardScript.REVIEW_REJECT, true)
		"filter_flag":
			_set_batch_review_filter(card_id, CanvasBatchCardScript.REVIEW_FLAG, true)
		"review_keep":
			_set_batch_review_state(card_id, asset_ids, CanvasBatchCardScript.REVIEW_KEEP, true)
		"review_reject":
			_set_batch_review_state(card_id, asset_ids, CanvasBatchCardScript.REVIEW_REJECT, true)
		"review_flag":
			_set_batch_review_state(card_id, asset_ids, CanvasBatchCardScript.REVIEW_FLAG, true)
		_:
			batch_face_action_requested.emit(card_id, action_id, asset_ids)


func _set_batch_collapsed(item_id: String, value: bool, record_undo: bool = true) -> bool:
	if not _items_by_id.has(item_id):
		return false
	var item: Node = _items_by_id[item_id]
	if item.get_script() != CanvasBatchCardScript or item.collapsed == value:
		return false
	var before := bool(item.collapsed)
	var apply := func(next_value: bool) -> void:
		item._set_collapsed(next_value)
		_update_item_visibility()
		_emit_canvas_changed()
	if record_undo:
		UndoService.perform_action(
			"Collapse result batch",
			func() -> void: apply.call(value),
			func() -> void: apply.call(before)
		)
	else:
		apply.call(value)
	return true


func _add_node_direct(item_data: Dictionary) -> Node:
	var item: Node = CanvasNodeCardScript.new()
	item.setup_from_data(item_data)
	item.params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			graph_node_params_commit_requested.emit(graph_id, node_id, params)
	)
	item.action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			_select_only([item.item_id])
			graph_node_action_requested.emit(graph_id, node_id, action_id)
	)
	item.collapsed_change_requested.connect(_set_graph_node_collapsed)
	item.display_title_change_requested.connect(_set_canvas_item_display_title)
	item.size_change_requested.connect(_set_canvas_item_size)
	item.set_lod_camera_zoom(camera_zoom)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	_update_item_visibility()
	queue_redraw()
	return item


func _add_frame_direct(item_data: Dictionary) -> Node:
	var item: Node = CanvasItemFrameScript.new()
	item.setup_from_data(item_data)
	item.display_title_change_requested.connect(_set_canvas_item_display_title)
	item.size_change_requested.connect(_set_canvas_item_size)
	item.set_lod_camera_zoom(camera_zoom)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	_update_item_visibility()
	queue_redraw()
	return item


func _set_graph_node_collapsed(item_id: String, value: bool, record_undo: bool = true) -> bool:
	if not _items_by_id.has(item_id):
		return false
	var item: Node = _items_by_id[item_id]
	if item.get_script() != CanvasNodeCardScript or item.collapsed == value:
		return false
	var before := bool(item.collapsed)
	var apply := func(next_value: bool) -> void:
		item.set_collapsed(next_value)
		_update_item_visibility()
		_emit_canvas_changed()
	if record_undo:
		UndoService.perform_action(
			"Collapse graph module",
			func() -> void: apply.call(value),
			func() -> void: apply.call(before)
		)
	else:
		apply.call(value)
	return true


func _set_canvas_item_display_title(
	item_id: String, value: String, record_undo: bool = true
) -> bool:
	if not _items_by_id.has(item_id):
		return false
	var item: Node = _items_by_id[item_id]
	if not item.has_method("set_display_title") or item.locked:
		return false
	var before := String(item.display_title)
	var normalized := CardContract.normalize_display_title(value)
	if before == normalized:
		return false
	var apply := func(next_value: String) -> void:
		item.set_display_title(next_value)
		_emit_canvas_changed()
	if record_undo:
		UndoService.perform_action(
			"Rename canvas card",
			func() -> void: apply.call(normalized),
			func() -> void: apply.call(before)
		)
	else:
		apply.call(normalized)
	return true


func _set_canvas_item_size(item_id: String, value: Vector2i, record_undo: bool = true) -> bool:
	if not _items_by_id.has(item_id):
		return false
	var item: Node = _items_by_id[item_id]
	if not item.has_method("set_requested_size") or item.locked:
		return false
	var before := Vector2i(item.requested_size)
	var apply := func(next_value: Vector2i) -> void:
		item.set_requested_size(next_value)
		_update_item_visibility()
		_emit_canvas_changed()
	if record_undo:
		apply.call(value)
		UndoService.perform_action(
			"Resize canvas card",
			func() -> void: apply.call(value),
			func() -> void: apply.call(before),
			0,
			false
		)
	else:
		apply.call(value)
	return true


func _remove_item_direct(item_id: String) -> void:
	if not _items_by_id.has(item_id):
		return

	var item: Node = _items_by_id[item_id]
	if item.get_script() == CanvasItemSpriteScript and not item.asset_id.is_empty():
		AssetLibrary.release_ref(item.asset_id)
	elif item.get_script() == CanvasBatchCardScript:
		for asset_id in item.asset_ids:
			AssetLibrary.release_ref(asset_id)
	_items_by_id.erase(item_id)
	if item_id == _cleanup_preview.source_item_id:
		clear_cleanup_preview()
	_selection.remove_item_reference(item_id)
	item_layer.remove_child(item)
	item.free()
	queue_redraw()


func _hit_at_world(world_position: Vector2) -> Dictionary:
	return HitPolicy.hit_at_world(
		item_layer,
		world_position,
		CanvasBatchCardScript,
		CanvasItemSpriteScript,
		CanvasNodeCardScript,
		CanvasItemFrameScript
	)


func _apply_positions(positions: Dictionary) -> void:
	SelectionSnapshot.apply_positions(_items_by_id, positions)
	GraphItemBridge.sync_graph_node_positions(_items_by_id, positions)
	_sync_cleanup_grid_overlay()
	queue_redraw()


func _select_only(ids: Array) -> void:
	_selected_graph_edge = {}
	_selection.select_only(ids, _items_by_id.keys())


func _clear_selection() -> void:
	_selected_graph_edge = {}
	_selection.clear()


func _set_zoom_to_value(value: float) -> void:
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(ZOOM_LEVELS.size()):
		var distance := absf(float(ZOOM_LEVELS[index]) - value)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	zoom_index = nearest_index
	camera_zoom = float(ZOOM_LEVELS[zoom_index])


func _set_viewport_scale_factor_for_test(viewport_scale_factor: float) -> void:
	_viewport_scale_factor_override = maxf(viewport_scale_factor, 1.0)
	_update_layer_transform()


func _update_layer_transform() -> void:
	var viewport_scale_factor := _resolve_viewport_scale_factor()
	var art_logical_scale := _get_art_logical_scale()
	var raw_position := size * 0.5 - camera_center * art_logical_scale
	item_layer.position = ScalePolicy.snap_position_to_physical_pixel(
		raw_position, viewport_scale_factor
	)
	item_layer.scale = Vector2.ONE * art_logical_scale
	LODCoordinator.sync_camera_zoom(_items_by_id, camera_zoom)
	_sync_cleanup_grid_overlay()
	queue_redraw()


func _update_item_visibility() -> void:
	var scale := _get_art_logical_scale()
	var visible_world := Rect2(
		screen_to_world(Vector2.ZERO) - Vector2.ONE * CULL_PADDING_PIXELS / scale,
		size / scale + Vector2.ONE * CULL_PADDING_PIXELS * 2.0 / scale
	)
	for item in _items_by_id.values():
		var is_visible := visible_world.intersects(item.get_canvas_bounds())
		item.visible = is_visible
		item.set_process(is_visible)
		item.set_physics_process(is_visible)


func _resolve_viewport_scale_factor() -> float:
	if _viewport_scale_factor_override >= 1.0:
		return _viewport_scale_factor_override
	if not is_inside_tree():
		return 1.0
	var root := get_tree().root
	if root == null:
		return 1.0
	return ScalePolicy.resolve_viewport_scale_factor(root)


func _get_art_logical_scale() -> float:
	return maxf(
		ScalePolicy.compute_art_logical_scale(camera_zoom, _resolve_viewport_scale_factor()), 0.0001
	)


func _camera_center_for_snapped_anchor(anchor_world: Vector2, screen_anchor: Vector2) -> Vector2:
	return ScalePolicy.camera_center_for_snapped_anchor(
		size,
		anchor_world,
		screen_anchor,
		_get_art_logical_scale(),
		_resolve_viewport_scale_factor()
	)


func _emit_canvas_changed() -> void:
	if _suppress_change_signal:
		return
	canvas_changed.emit()


func _emit_zoom_changed() -> void:
	zoom_changed.emit(zoom_index, camera_zoom)


func _on_selection_changed(selected_ids: Array) -> void:
	if not selected_ids.has(_cleanup_preview.source_item_id):
		clear_cleanup_preview()
	_sync_cleanup_grid_overlay()
	selection_changed.emit(selected_ids.duplicate())
	queue_redraw()


func _sync_cleanup_grid_overlay() -> void:
	if _cleanup_grid_overlay == null:
		return
	var selected_ids: Array = _selection.get_selected_ids()
	if (
		not _cleanup_grid_active
		or selected_ids.size() != 1
		or not _items_by_id.has(selected_ids[0])
	):
		_cleanup_grid_overlay.configure(Rect2(), _cleanup_grid_scale, _cleanup_grid_offset, false)
		return
	var item: Node = _items_by_id[selected_ids[0]]
	if item.get_script() != CanvasItemSpriteScript:
		_cleanup_grid_overlay.configure(Rect2(), _cleanup_grid_scale, _cleanup_grid_offset, false)
		return
	_cleanup_grid_overlay.configure(
		item.get_canvas_bounds(), _cleanup_grid_scale, _cleanup_grid_offset, true
	)


func _on_cleanup_grid_changed(scale: float, offset: Vector2) -> void:
	_cleanup_grid_scale = scale
	_cleanup_grid_offset = offset
	cleanup_grid_changed.emit(scale, offset)


func _tool_manager_handles(event: InputEvent) -> bool:
	return ToolInputPolicy.tool_manager_handles(
		tool_manager, event, self, _get_active_tool_target()
	)


func _emit_context_request(screen_position: Vector2) -> void:
	var hit_item: Node = _hit_at_world(screen_to_world(screen_position)).get("item", null)
	var popup_position := Vector2i(get_screen_position()) + Vector2i(screen_position)
	if hit_item != null and hit_item.get_script() == CanvasBatchCardScript:
		_select_only([hit_item.item_id])
		batch_context_requested.emit(hit_item.item_id, popup_position)
		return
	if hit_item == null:
		graph_quick_add_requested.emit(popup_position)
