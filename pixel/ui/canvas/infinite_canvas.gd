class_name PFInfiniteCanvas
extends Control

## 无限画布核心交互。
## 职责：平移、缩放、sprite 元素增删选移、框选、网格和视口剔除；保存格式直接导出 canvas.json 结构。

signal canvas_changed
signal selection_changed(selected_ids: Array)
signal cleanup_grid_changed(scale: float, offset: Vector2)
signal batch_context_requested(card_id: String, screen_position: Vector2i)
signal zoom_changed(zoom_index: int, camera_zoom: float)

const ZOOM_LEVELS := [0.125, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 16.0, 32.0]
const DEFAULT_ZOOM_INDEX := 4
const WHEEL_ZOOM_MIN_INTERVAL_MSEC := 80
const CULL_INTERVAL_SECONDS := 0.1
const CULL_PADDING_PIXELS := 128.0
const GRID_MIN_ZOOM := 4.0
const SELECTION_COLOR := Color(0.1, 0.85, 0.65, 1.0)
const BOX_COLOR := Color(1.0, 0.85, 0.25, 0.35)
const BACKGROUND_COLOR := Color(0.105, 0.11, 0.12, 1.0)
const EDGE_COLOR := Color(0.42, 0.58, 0.62, 0.9)
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
const GraphEdgeInteraction := preload("res://ui/canvas/canvas_graph_edge_interaction.gd")
const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
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

var camera_center := Vector2.ZERO
var zoom_index := DEFAULT_ZOOM_INDEX
var camera_zoom := float(ZOOM_LEVELS[DEFAULT_ZOOM_INDEX])

var item_layer := Node2D.new()
var tool_manager: Variant = null

var _viewport_scale_factor_override := 0.0
var _items_by_id := {}
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
	if _tool_manager_handles(event):
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

	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if not _selected_graph_edge.is_empty():
			GraphEdgeInteraction.delete_edge(_selected_graph_edge, _emit_canvas_changed)
			_selected_graph_edge = {}
			queue_redraw()
		else:
			delete_selected()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed:
			UndoService.redo()
		else:
			UndoService.undo()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	if (
		ScalePolicy.compute_art_physical_scale(camera_zoom, _resolve_viewport_scale_factor())
		>= GRID_MIN_ZOOM
	):
		PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
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
		snapshots.append(snapshot)

	if snapshots.is_empty():
		return

	var do_delete := func() -> void:
		for snapshot in snapshots:
			_remove_item_direct(String(snapshot["data"]["id"]))
		_clear_selection()
		_emit_canvas_changed()

	var undo_delete := func() -> void:
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
		_select_only(SelectionSnapshot.ids_from_snapshots(snapshots))
		_emit_canvas_changed()

	var memory_cost := 0
	for snapshot in snapshots:
		if snapshot.has("image"):
			memory_cost += ImageMath.estimate_rgba8_bytes(snapshot["image"])

	if record_undo:
		UndoService.perform_action("Delete sprite", do_delete, undo_delete, memory_cost)
	else:
		do_delete.call()


func clear_canvas() -> void:
	_suppress_change_signal = true
	for item in _items_by_id.values():
		item.queue_free()
	_items_by_id.clear()
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
				Log.warn(
					"Canvas item skipped because asset image is missing", {"asset_id": asset_id}
				)
				continue
			_add_sprite_direct(item_data, image)
		elif item_type == "batch_card":
			_add_batch_direct(item_data)
		elif item_type == "node" and GraphItemBridge.is_graph_batch_node_data(item_data):
			_add_batch_direct(item_data)
		elif item_type == "node":
			_add_node_direct(item_data)

	_suppress_change_signal = false
	_update_layer_transform()
	_update_item_visibility()
	_emit_zoom_changed()
	queue_redraw()


func export_canvas_data() -> Dictionary:
	var items := []
	var nodes := item_layer.get_children()
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return a.z_index < b.z_index)

	for node in nodes:
		if node.get_script() == CanvasItemSpriteScript:
			items.append(node.to_canvas_data())
		elif node.get_script() == CanvasBatchCardScript:
			items.append(node.to_canvas_data())
		elif node.get_script() == CanvasNodeCardScript:
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

	var before := SelectionSnapshot.selected_positions(_items_by_id, _selection)
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
		UndoService.perform_action("Move sprite", do_move, undo_move)
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
		_emit_batch_context_if_hit(event.position)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		if Input.is_key_pressed(KEY_SPACE):
			_is_panning = event.pressed
		elif event.pressed:
			_begin_left_interaction(event.position, event.shift_pressed)
		else:
			_finish_left_interaction(event.position)
		accept_event()


func _handle_wheel_zoom(step_delta: int, screen_anchor: Vector2) -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec - _last_wheel_zoom_msec < WHEEL_ZOOM_MIN_INTERVAL_MSEC:
		return
	_last_wheel_zoom_msec = now_msec
	zoom_by_steps(step_delta, screen_anchor)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _graph_edge_drag.is_empty():
		_graph_edge_drag_world = GraphEdgeInteraction.update_drag_world(self, event.position)
		queue_redraw()
		accept_event()
	elif _is_panning:
		pan_by_pixels(-event.relative)
		accept_event()
	elif _selection.is_dragging_items:
		_drag_selected_to(screen_to_world(event.position))
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
			_selection.start_drag(
				world_position, SelectionSnapshot.selected_positions(_items_by_id, _selection)
			)
	else:
		var edge_hit := GraphEdgeRenderer.hit_edge_at_screen(
			self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, screen_position
		)
		if not edge_hit.is_empty():
			_selection.clear()
			_selected_graph_edge = edge_hit
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
		GraphEdgeInteraction.connect_at_screen(
			self,
			_items_by_id,
			CanvasBatchCardScript,
			CanvasNodeCardScript,
			start,
			screen_position,
			_emit_canvas_changed
		)
	elif _selection.is_dragging_items:
		_commit_drag_if_needed()
		_selection.stop_drag()
	elif _selection.is_box_selecting:
		_selection.update_box(screen_position)
		_finish_box_selection()
		_selection.stop_box()

	queue_redraw()


func _drag_selected_to(world_position: Vector2) -> void:
	var delta: Vector2 = (world_position - _selection.drag_start_world).round()
	for item_id in _selection.get_selected_ids():
		if _items_by_id.has(item_id) and _selection.drag_start_positions.has(item_id):
			var item: Node = _items_by_id[item_id]
			if not item.locked:
				item.position = (_selection.drag_start_positions[item_id] + delta).round()
	_sync_cleanup_grid_overlay()
	queue_redraw()


func _commit_drag_if_needed() -> void:
	var after_positions := SelectionSnapshot.selected_positions(_items_by_id, _selection)
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

	UndoService.perform_action("Move sprite", do_move, undo_move, 0, false)
	_emit_canvas_changed()


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
	item.set_lod_camera_zoom(camera_zoom)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	for asset_id in item.asset_ids:
		AssetLibrary.add_ref(asset_id)
	_update_item_visibility()
	queue_redraw()
	return item


func _add_node_direct(item_data: Dictionary) -> Node:
	var item: Node = CanvasNodeCardScript.new()
	item.setup_from_data(item_data)
	item_layer.add_child(item)
	_items_by_id[item.item_id] = item
	_update_item_visibility()
	queue_redraw()
	return item


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
		CanvasNodeCardScript
	)


func _apply_positions(positions: Dictionary) -> void:
	SelectionSnapshot.apply_positions(_items_by_id, positions)
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
	LODCoordinator.sync_batch_camera_zoom(_items_by_id, CanvasBatchCardScript, camera_zoom)
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


func _emit_batch_context_if_hit(screen_position: Vector2) -> void:
	var hit_item: Node = _hit_at_world(screen_to_world(screen_position)).get("item", null)
	if hit_item == null or hit_item.get_script() != CanvasBatchCardScript:
		return
	_select_only([hit_item.item_id])
	batch_context_requested.emit(
		hit_item.item_id, Vector2i(get_screen_position()) + Vector2i(screen_position)
	)
