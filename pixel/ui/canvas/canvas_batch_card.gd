class_name PFCanvasBatchCard
extends Node2D

## M2.1 批次内容卡（无连线 MVP）。
## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。

signal collapsed_change_requested(item_id: String, collapsed: bool)
signal run_action_requested(graph_id: String, node_id: String, action_id: String)

const IdUtil := preload("res://core/util/id_util.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
const Strings := preload("res://ui/shell/strings.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")

const CARD_WIDTH := 600
const HEADER_HEIGHT := 40
const PADDING := 16
const THUMB_SIZE := 128
const THUMB_TEXTURE_SIZE := 192
const THUMB_GAP := 12
const MIN_CARD_HEIGHT := 216
const BACKGROUND := Color(0.16, 0.17, 0.18, 0.96)
const BORDER := Color(0.52, 0.62, 0.72, 1.0)
const EDGE_ERROR_BORDER := Color(0.94, 0.5, 0.22, 1.0)
const SELECTED_BORDER := Color(0.1, 0.85, 0.65, 1.0)
const THUMB_BACKGROUND := Color(0.08, 0.085, 0.09, 1.0)
const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
const REVIEW_NONE := ""
const REVIEW_KEEP := "keep"
const REVIEW_REJECT := "reject"
const REVIEW_FLAG := "flag"
const FILTER_ALL := "all"
const FILTER_PENDING := "pending"
const LAYOUT_CONTACT := "contact"
const LAYOUT_FOCUS := "focus"
const COMPARE_CURRENT := "current"
const COMPARE_PREVIOUS := "previous"
const COMPARE_SPLIT := "split"
const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
const FOCUS_BORDER := Color(0.96, 0.96, 0.9, 1.0)
const COMPARE_DIVIDER := Color(0.96, 0.96, 0.9, 0.85)
const INPUT_PORTS: Array[String] = ["in"]
const OUTPUT_PORTS: Array[String] = ["images", "assets"]
const FOCUS_IMAGE_HEIGHT := 320
const FOCUS_FILMSTRIP_THUMB_SIZE := 72
const FOCUS_FILMSTRIP_VISIBLE := 7
const PORT_HIT_RADIUS := 10.0
const CHECKER_SIZE := 8
const MAX_INSPECT_COLOR_HINTS := 256
const CHECKER_LIGHT := Color(0.18, 0.19, 0.2, 1.0)
const CHECKER_DARK := Color(0.1, 0.105, 0.11, 1.0)
const INSPECT_GRID := Color(1.0, 1.0, 1.0, 0.16)
const HINT_BACKGROUND := Color(0.02, 0.025, 0.03, 0.78)
const BADGE_BACKGROUND := Color(0.12, 0.08, 0.06, 0.92)
const COLLAPSED_HEIGHT := 100

var item_id := ""
var graph_id := ""
var node_id := ""
var asset_ids: Array[String] = []
var selected_asset_ids: Array[String] = []
var review_states := {}
var review_filter := FILTER_ALL
var focus_asset_id := ""
var compare_asset_ids: Array[String] = []
var compare_mode := COMPARE_CURRENT
var review_layout := LAYOUT_CONTACT
var label := ""
var locked := false
var collapsed := false
var frame_id: Variant = null
var run_state := {}

var _thumbnail_textures := {}
var _asset_hints := {}
var _font: Font = null
var _lod_camera_zoom := 1.0
var _has_graph_edge_error := false
var _collapse_button: Button = null
var _retry_button: Button = null
var _remove_placeholder_button: Button = null
var _raw_data := {}


func setup_from_data(data: Dictionary) -> void:
	_raw_data = data.duplicate(true)
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	_has_graph_edge_error = _graph_has_edge_error()
	var graph_node_data := _resolve_graph_batch_node_data()
	var graph_params: Dictionary = graph_node_data.get("params", {})
	label = String(graph_params.get("label", data.get("label", "Batch")))
	asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
	run_state = graph_params.get("run_state", {}).duplicate(true)
	selected_asset_ids = _string_array(data.get("selected_asset_ids", []))
	review_states = _review_state_map(
		graph_params.get("review_states", data.get("review_states", {})), asset_ids
	)
	review_filter = _normalize_review_filter(
		String(graph_params.get("review_filter", data.get("review_filter", FILTER_ALL)))
	)
	focus_asset_id = _normalize_focus_asset_id(
		String(graph_params.get("focus_asset_id", data.get("focus_asset_id", "")))
	)
	compare_asset_ids = _aligned_compare_asset_ids(
		graph_params.get("compare_asset_ids", data.get("compare_asset_ids", []))
	)
	compare_mode = _normalize_compare_mode(
		String(graph_params.get("compare_mode", data.get("compare_mode", COMPARE_CURRENT)))
	)
	review_layout = _normalize_review_layout(String(data.get("review_layout", LAYOUT_CONTACT)))
	collapsed = bool(data.get("collapsed", false))
	frame_id = data.get("frame_id", null)
	_prune_selected_to_visible()
	_prune_focus_to_visible()
	locked = bool(data.get("locked", false))
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rebuild_thumbnails()
	_rebuild_header_controls()
	queue_redraw()


func _refresh_from_graph() -> void:
	setup_from_data(to_canvas_data())


func to_canvas_data() -> Dictionary:
	var result := _raw_data.duplicate(true)
	if has_graph_binding():
		result["id"] = item_id
		result["type"] = "node"
		result["graph_id"] = graph_id
		result["node_id"] = node_id
		result["position"] = [int(round(position.x)), int(round(position.y))]
		result["z_index"] = z_index
		result["collapsed"] = collapsed
		result["review_layout"] = review_layout
		result["locked"] = locked
		result["frame_id"] = frame_id
		for graph_param_key in [
			"asset_ids",
			"selected_asset_ids",
			"review_states",
			"review_filter",
			"focus_asset_id",
			"compare_asset_ids",
			"compare_mode",
			"label",
		]:
			result.erase(graph_param_key)
		return result
	result["id"] = item_id
	result["type"] = "batch_card"
	result["asset_ids"] = asset_ids.duplicate()
	result["selected_asset_ids"] = selected_asset_ids.duplicate()
	result["review_states"] = review_states.duplicate(true)
	result["review_filter"] = review_filter
	result["focus_asset_id"] = focus_asset_id
	result["compare_asset_ids"] = compare_asset_ids.duplicate()
	result["compare_mode"] = compare_mode
	result["review_layout"] = review_layout
	result["label"] = label
	result["position"] = [int(round(position.x)), int(round(position.y))]
	result["z_index"] = z_index
	result["locked"] = locked
	result["collapsed"] = collapsed
	return result


func has_graph_binding() -> bool:
	return not graph_id.is_empty() and not node_id.is_empty()


func get_canvas_bounds() -> Rect2:
	return Rect2(position, Vector2(CARD_WIDTH, _card_height()))


func set_lod_camera_zoom(camera_zoom_value: float) -> void:
	var normalized_zoom := maxf(camera_zoom_value, 0.0)
	if is_equal_approx(_lod_camera_zoom, normalized_zoom):
		return
	_lod_camera_zoom = normalized_zoom
	queue_redraw()


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func _set_collapsed(value: bool) -> void:
	if collapsed == value:
		return
	collapsed = value
	_rebuild_header_controls()
	queue_redraw()


func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
	var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
	var count := ports.size()
	if count <= 0:
		return position + Vector2(0.0 if is_input else CARD_WIDTH, _card_height() * 0.5)
	var index := ports.find(port_name)
	if index < 0:
		index = 0
	return position + _graph_port_position(index, count, is_input)


func _graph_port_at_world(world_position: Vector2) -> Dictionary:
	if not has_graph_binding():
		return {}
	var input_hit := _port_hit_at_world(world_position, true)
	if not input_hit.is_empty():
		return input_hit
	return _port_hit_at_world(world_position, false)


func set_asset_ids(new_asset_ids: Array) -> void:
	asset_ids = _string_array(new_asset_ids)
	for selected_id in selected_asset_ids.duplicate():
		if not asset_ids.has(selected_id):
			selected_asset_ids.erase(selected_id)
	review_states = _review_state_map(review_states, asset_ids)
	compare_asset_ids = _aligned_compare_asset_ids(compare_asset_ids)
	compare_mode = _normalize_compare_mode(compare_mode)
	_prune_selected_to_visible()
	_prune_focus_to_visible()
	_rebuild_thumbnails()
	queue_redraw()


func get_selected_asset_ids() -> Array[String]:
	var visible_lookup := _visible_lookup()
	var result: Array[String] = []
	for asset_id in selected_asset_ids:
		if visible_lookup.has(asset_id):
			result.append(asset_id)
	return result


func get_selected_or_all_asset_ids() -> Array[String]:
	var visible_ids := get_visible_asset_ids()
	if selected_asset_ids.is_empty():
		return visible_ids
	var visible_lookup := _lookup(visible_ids)
	var result: Array[String] = []
	for selected_id in selected_asset_ids:
		if visible_lookup.has(selected_id):
			result.append(selected_id)
	return result


func get_marked_asset_ids(review_state: String) -> Array[String]:
	var normalized_state := _normalize_review_state(review_state)
	var result: Array[String] = []
	for asset_id in asset_ids:
		if String(review_states.get(asset_id, REVIEW_NONE)) == normalized_state:
			result.append(asset_id)
	return result


func get_visible_asset_ids() -> Array[String]:
	var result: Array[String] = []
	match review_filter:
		FILTER_ALL:
			return asset_ids.duplicate()
		FILTER_PENDING:
			for asset_id in asset_ids:
				if not review_states.has(asset_id):
					result.append(asset_id)
		REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
			for asset_id in asset_ids:
				if String(review_states.get(asset_id, REVIEW_NONE)) == review_filter:
					result.append(asset_id)
	return result


func get_review_states() -> Dictionary:
	return review_states.duplicate(true)


func set_review_states(new_review_states: Dictionary) -> void:
	review_states = _review_state_map(new_review_states, asset_ids)
	_prune_selected_to_visible()
	_prune_focus_to_visible()
	queue_redraw()


func get_review_filter() -> String:
	return review_filter


func set_review_filter(new_review_filter: String) -> void:
	review_filter = _normalize_review_filter(new_review_filter)
	_prune_selected_to_visible()
	_prune_focus_to_visible()
	queue_redraw()


func get_review_layout() -> String:
	return review_layout


func set_review_layout(new_review_layout: String) -> void:
	review_layout = _normalize_review_layout(new_review_layout)
	if review_layout == LAYOUT_FOCUS and focus_asset_id.is_empty():
		focus_asset_id = _initial_focus_asset_id()
	queue_redraw()


func _get_focus_asset_id() -> String:
	return focus_asset_id


func _set_focus_asset_id(new_focus_asset_id: String, select_focused: bool = false) -> void:
	focus_asset_id = _normalize_focus_asset_id(new_focus_asset_id)
	_prune_focus_to_visible()
	if select_focused and not focus_asset_id.is_empty():
		selected_asset_ids = [focus_asset_id]
	queue_redraw()


func _set_selected_asset_ids(new_selected_asset_ids: Array) -> void:
	selected_asset_ids = _visible_selected_array(new_selected_asset_ids)
	queue_redraw()


func _focus_asset_id_relative(step: int) -> String:
	var visible_ids := get_visible_asset_ids()
	if visible_ids.is_empty():
		return ""
	if step == 0:
		return focus_asset_id if visible_ids.has(focus_asset_id) else ""
	var anchor_index := _focus_anchor_index(visible_ids)
	if anchor_index < 0:
		anchor_index = -1 if step > 0 else visible_ids.size()
	return visible_ids[posmod(anchor_index + step, visible_ids.size())]


func _get_compare_asset_ids() -> Array[String]:
	return compare_asset_ids.duplicate()


func _get_compare_mode() -> String:
	return compare_mode


func _set_compare_state(new_compare_asset_ids: Array, new_compare_mode: String) -> void:
	compare_asset_ids = _aligned_compare_asset_ids(new_compare_asset_ids)
	compare_mode = _normalize_compare_mode(new_compare_mode)
	_rebuild_thumbnails()
	queue_redraw()


func _set_compare_mode(new_compare_mode: String) -> void:
	compare_mode = _normalize_compare_mode(new_compare_mode)
	queue_redraw()


func toggle_asset_at_world(world_position: Vector2) -> bool:
	var index := asset_index_at_world(world_position)
	var visible_ids := get_visible_asset_ids()
	if index < 0 or index >= visible_ids.size():
		return false
	var asset_id := visible_ids[index]
	if selected_asset_ids.has(asset_id):
		selected_asset_ids.erase(asset_id)
		if focus_asset_id == asset_id:
			focus_asset_id = ""
			if not selected_asset_ids.is_empty():
				focus_asset_id = selected_asset_ids[selected_asset_ids.size() - 1]
	else:
		selected_asset_ids.append(asset_id)
		focus_asset_id = asset_id
	queue_redraw()
	return true


func asset_index_at_world(world_position: Vector2) -> int:
	if collapsed:
		return -1
	var local := world_position - position
	if local.y < HEADER_HEIGHT:
		return -1
	if review_layout == LAYOUT_FOCUS:
		return _focus_layout_asset_index_at_local(local)
	var columns := _columns()
	var visible_ids := get_visible_asset_ids()
	for index in range(visible_ids.size()):
		var rect := _thumb_rect(index, columns)
		if rect.has_point(local):
			return index
	return -1


func _get_lod_profile() -> String:
	return LODProfile.profile_for_camera_zoom(_lod_camera_zoom)


func _draw() -> void:
	_font = UIFont.get_font() if _font == null else _font
	var card_rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, _card_height()))
	draw_rect(card_rect, BACKGROUND, true)
	draw_rect(card_rect, _border_color(), false, 1.0)
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, HEADER_HEIGHT)), Color(0.21, 0.22, 0.24, 1.0), true
	)
	var visible_ids := get_visible_asset_ids()
	if _font != null:
		var visible_count := visible_ids.size()
		var title := "%s (%d)" % [label, asset_ids.size()]
		if visible_count != asset_ids.size():
			title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
		if compare_mode == COMPARE_PREVIOUS:
			title = "%s - %s" % [title, Strings.BATCH_COMPARE_PREVIOUS_SUFFIX]
		elif compare_mode == COMPARE_SPLIT:
			title = "%s - %s" % [title, Strings.BATCH_COMPARE_SPLIT_SUFFIX]
		draw_string(
			_font,
			Vector2(PADDING, 28),
			title,
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - PADDING * 2,
			18,
			Color(0.9, 0.92, 0.92, 1.0)
		)
		_draw_graph_status_badge()
	if collapsed:
		if has_graph_binding():
			_draw_graph_ports()
		return

	if review_layout == LAYOUT_FOCUS:
		_draw_focus_layout(visible_ids)
	elif visible_ids.is_empty() and int(run_state.get("expected_count", 0)) > 0:
		_draw_placeholders()
	else:
		var columns := _columns()
		for index in range(visible_ids.size()):
			_draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
	if has_graph_binding():
		_draw_graph_ports()


func _draw_placeholders() -> void:
	var expected_count := int(run_state.get("expected_count", 0))
	var columns := _columns()
	for index in range(expected_count):
		var rect := _thumb_rect(index, columns)
		draw_rect(rect, THUMB_BACKGROUND, true)
		draw_rect(rect, BORDER.darkened(0.3), false, 1.5)
		draw_line(rect.position + Vector2(12, 12), rect.end - Vector2(12, 12), BORDER, 2.0)
		draw_line(
			Vector2(rect.end.x - 12, rect.position.y + 12),
			Vector2(rect.position.x + 12, rect.end.y - 12),
			BORDER,
			2.0
		)
	var detail := String(run_state.get("detail", ""))
	if not detail.is_empty() and _font != null:
		draw_string(
			_font,
			Vector2(PADDING, _card_height() - 12),
			detail,
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - PADDING * 2,
			13,
			Color(0.86, 0.88, 0.88, 1.0)
		)


func _draw_focus_layout(visible_ids: Array[String]) -> void:
	if visible_ids.is_empty():
		return
	var focused_asset_id := _focused_visible_asset_id()
	if focused_asset_id.is_empty():
		return
	_draw_thumbnail(focused_asset_id, _focus_rect())
	var start_index := _filmstrip_start_index(visible_ids)
	var end_index := mini(visible_ids.size(), start_index + FOCUS_FILMSTRIP_VISIBLE)
	for index in range(start_index, end_index):
		_draw_thumbnail(visible_ids[index], _filmstrip_rect(index - start_index))


func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
	var inspect_mode := _get_lod_profile() == LODProfile.PROFILE_INSPECT
	if inspect_mode:
		_draw_checkerboard(rect)
	else:
		draw_rect(rect, THUMB_BACKGROUND, true)
	if compare_mode == COMPARE_SPLIT:
		_draw_split_compare_thumbnail(asset_id, rect)
	else:
		_draw_thumbnail_texture(_texture_asset_id_for(asset_id), rect)
	if inspect_mode:
		_draw_inspect_overlay(asset_id, rect)
	var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
	draw_rect(rect, border_color, false, 1.5)
	_draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
	if focus_asset_id == asset_id:
		draw_rect(rect.grow(3.0), FOCUS_BORDER, false, 2.5)


func _draw_split_compare_thumbnail(asset_id: String, rect: Rect2) -> void:
	var compare_asset_id := _compare_asset_id_for(asset_id)
	if compare_asset_id.is_empty():
		_draw_thumbnail_texture(asset_id, rect)
		return
	var left_rect := Rect2(rect.position, Vector2(floor(rect.size.x * 0.5), rect.size.y))
	var right_rect := Rect2(
		Vector2(rect.position.x + left_rect.size.x, rect.position.y),
		Vector2(rect.size.x - left_rect.size.x, rect.size.y)
	)
	_draw_thumbnail_texture(compare_asset_id, left_rect)
	_draw_thumbnail_texture(asset_id, right_rect)
	var divider_x := rect.position.x + left_rect.size.x
	draw_line(
		Vector2(divider_x, rect.position.y), Vector2(divider_x, rect.end.y), COMPARE_DIVIDER, 2.0
	)


func _draw_thumbnail_texture(asset_id: String, rect: Rect2) -> void:
	var texture_rect := _thumbnail_texture_rect(asset_id, rect)
	if texture_rect.size == Vector2.ZERO:
		return
	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
	draw_texture_rect(texture, texture_rect, false)


func _thumbnail_texture_rect(asset_id: String, rect: Rect2) -> Rect2:
	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
	if texture != null:
		var image_size := texture.get_size()
		var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
		var draw_size := image_size * scale
		var draw_pos := rect.position + (rect.size - draw_size) * 0.5
		return Rect2(draw_pos, draw_size)
	return Rect2()


func _draw_checkerboard(rect: Rect2) -> void:
	var columns := int(ceil(rect.size.x / float(CHECKER_SIZE)))
	var rows := int(ceil(rect.size.y / float(CHECKER_SIZE)))
	for row in range(rows):
		for column in range(columns):
			var cell := Rect2(
				rect.position + Vector2(column * CHECKER_SIZE, row * CHECKER_SIZE),
				Vector2(CHECKER_SIZE, CHECKER_SIZE)
			)
			draw_rect(cell, CHECKER_LIGHT if (row + column) % 2 == 0 else CHECKER_DARK, true)


func _draw_inspect_overlay(asset_id: String, rect: Rect2) -> void:
	var texture_asset_id := _texture_asset_id_for(asset_id)
	var texture_rect := _thumbnail_texture_rect(texture_asset_id, rect)
	if texture_rect.size != Vector2.ZERO:
		_draw_texture_pixel_grid(texture_asset_id, texture_rect)
	var hint := _asset_hint_for(asset_id)
	if hint.is_empty() or _font == null:
		return
	var hint_rect := Rect2(
		rect.position + Vector2(6.0, rect.size.y - 24.0), Vector2(rect.size.x - 12.0, 18.0)
	)
	draw_rect(hint_rect, HINT_BACKGROUND, true)
	draw_string(
		_font,
		hint_rect.position + Vector2(5.0, 14.0),
		hint,
		HORIZONTAL_ALIGNMENT_LEFT,
		hint_rect.size.x - 10.0,
		12,
		Color(0.94, 0.95, 0.94, 1.0)
	)


func _draw_texture_pixel_grid(asset_id: String, texture_rect: Rect2) -> void:
	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
	if texture == null:
		return
	var image_size := texture.get_size()
	var cell_size := minf(texture_rect.size.x / image_size.x, texture_rect.size.y / image_size.y)
	if not LODProfile.should_draw_pixel_grid(_lod_camera_zoom, cell_size):
		return
	for x in range(1, int(image_size.x)):
		var line_x := texture_rect.position.x + float(x) * cell_size
		draw_line(
			Vector2(line_x, texture_rect.position.y),
			Vector2(line_x, texture_rect.end.y),
			INSPECT_GRID
		)
	for y in range(1, int(image_size.y)):
		var line_y := texture_rect.position.y + float(y) * cell_size
		draw_line(
			Vector2(texture_rect.position.x, line_y),
			Vector2(texture_rect.end.x, line_y),
			INSPECT_GRID
		)


func _draw_review_marker(rect: Rect2, review_state: String) -> void:
	match _normalize_review_state(review_state):
		REVIEW_KEEP:
			draw_rect(Rect2(rect.position, Vector2(7.0, rect.size.y)), KEEP_MARK, true)
		REVIEW_REJECT:
			draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), REJECT_MARK, 4.0)
			draw_line(
				Vector2(rect.end.x - 8, rect.position.y + 8),
				Vector2(rect.position.x + 8, rect.end.y - 8),
				REJECT_MARK,
				4.0
			)
		REVIEW_FLAG:
			draw_colored_polygon(
				PackedVector2Array(
					[
						rect.position + Vector2(rect.size.x - 30.0, 0.0),
						rect.position + Vector2(rect.size.x, 0.0),
						rect.position + Vector2(rect.size.x, 30.0),
					]
				),
				FLAG_MARK
			)


func _thumb_rect(index: int, columns: int) -> Rect2:
	var col := index % columns
	var row := int(index / columns)
	return Rect2(
		Vector2(
			PADDING + col * (THUMB_SIZE + THUMB_GAP),
			HEADER_HEIGHT + PADDING + row * (THUMB_SIZE + THUMB_GAP)
		),
		Vector2(THUMB_SIZE, THUMB_SIZE)
	)


func _focus_rect() -> Rect2:
	return Rect2(
		Vector2(PADDING, HEADER_HEIGHT + PADDING),
		Vector2(CARD_WIDTH - PADDING * 2, FOCUS_IMAGE_HEIGHT)
	)


func _filmstrip_rect(slot_index: int) -> Rect2:
	var y := HEADER_HEIGHT + PADDING + FOCUS_IMAGE_HEIGHT + THUMB_GAP
	return Rect2(
		Vector2(PADDING + slot_index * (FOCUS_FILMSTRIP_THUMB_SIZE + THUMB_GAP), y),
		Vector2(FOCUS_FILMSTRIP_THUMB_SIZE, FOCUS_FILMSTRIP_THUMB_SIZE)
	)


func _card_height() -> int:
	if collapsed:
		return COLLAPSED_HEIGHT
	var visible_count := get_visible_asset_ids().size()
	if visible_count <= 0:
		visible_count = int(run_state.get("expected_count", 0))
	if visible_count <= 0:
		return MIN_CARD_HEIGHT
	if review_layout == LAYOUT_FOCUS:
		return maxi(
			MIN_CARD_HEIGHT,
			(
				HEADER_HEIGHT
				+ PADDING * 2
				+ FOCUS_IMAGE_HEIGHT
				+ THUMB_GAP
				+ FOCUS_FILMSTRIP_THUMB_SIZE
			)
		)
	var rows := int(ceil(float(visible_count) / float(_columns())))
	return maxi(
		MIN_CARD_HEIGHT, HEADER_HEIGHT + PADDING * 2 + rows * THUMB_SIZE + (rows - 1) * THUMB_GAP
	)


func _columns() -> int:
	return maxi(1, int((CARD_WIDTH - PADDING * 2 + THUMB_GAP) / (THUMB_SIZE + THUMB_GAP)))


func _draw_graph_ports() -> void:
	for index in range(INPUT_PORTS.size()):
		draw_circle(_graph_port_position(index, INPUT_PORTS.size(), true), 5.0, PORT_IN)
	for index in range(OUTPUT_PORTS.size()):
		draw_circle(_graph_port_position(index, OUTPUT_PORTS.size(), false), 5.0, PORT_OUT)


func _border_color() -> Color:
	return EDGE_ERROR_BORDER if _has_graph_edge_error else BORDER


func _draw_graph_status_badge() -> void:
	if _font == null:
		return
	var run_status := String(run_state.get("status", ""))
	if not _has_graph_edge_error and run_status.is_empty():
		return
	var badge_size := Vector2(78, 18)
	var action_space := 164.0 if run_status in ["failed", "canceled"] else 30.0
	var badge_rect := Rect2(
		Vector2(CARD_WIDTH - PADDING - action_space - badge_size.x, 11), badge_size
	)
	var badge_color := EDGE_ERROR_BORDER if _has_graph_edge_error else BORDER
	draw_rect(badge_rect, BADGE_BACKGROUND, true)
	draw_rect(badge_rect, badge_color, false, 1.0)
	draw_string(
		_font,
		badge_rect.position + Vector2(5, 13),
		(
			Strings.GRAPH_NODE_BADGE_EDGE_ERROR
			if _has_graph_edge_error
			else Strings.text("CONTENT_STATUS_%s" % run_status.to_upper())
		),
		HORIZONTAL_ALIGNMENT_LEFT,
		badge_rect.size.x - 10,
		11,
		badge_color
	)


func _rebuild_header_controls() -> void:
	if _collapse_button == null:
		_collapse_button = Button.new()
		_collapse_button.name = "CollapseButton"
		_collapse_button.focus_mode = Control.FOCUS_NONE
		_collapse_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_collapse_button.pressed.connect(
			func() -> void: collapsed_change_requested.emit(item_id, not collapsed)
		)
		add_child(_collapse_button)
	_collapse_button.text = "+" if collapsed else "−"
	_collapse_button.tooltip_text = Strings.text(
		"ACTION_EXPAND_MODULE" if collapsed else "ACTION_COLLAPSE_MODULE"
	)
	_collapse_button.position = Vector2(CARD_WIDTH - 28, 7)
	_collapse_button.size = Vector2(24, 24)
	var retryable := String(run_state.get("status", "")) in ["failed", "canceled"]
	if _retry_button == null:
		_retry_button = Button.new()
		_retry_button.name = "RetryButton"
		_retry_button.text = Strings.text("ACTION_RETRY_GENERATION")
		_retry_button.pressed.connect(
			func() -> void: run_action_requested.emit(graph_id, node_id, "retry")
		)
		add_child(_retry_button)
	_retry_button.visible = retryable
	_retry_button.position = Vector2(CARD_WIDTH - 160, 7)
	_retry_button.size = Vector2(66, 26)
	if _remove_placeholder_button == null:
		_remove_placeholder_button = Button.new()
		_remove_placeholder_button.name = "RemovePlaceholderButton"
		_remove_placeholder_button.text = Strings.text("ACTION_REMOVE_PLACEHOLDER")
		_remove_placeholder_button.pressed.connect(
			func() -> void: run_action_requested.emit(graph_id, node_id, "remove")
		)
		add_child(_remove_placeholder_button)
	_remove_placeholder_button.visible = retryable
	_remove_placeholder_button.position = Vector2(CARD_WIDTH - 92, 7)
	_remove_placeholder_button.size = Vector2(60, 26)


func _graph_has_edge_error() -> bool:
	if graph_id.is_empty() or node_id.is_empty():
		return false
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		return false
	var graph: PFGraph = GraphScript.from_json(graph_data)
	return not graph.validate_edges_for_node(node_id).is_empty()


func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
	var lane_height := minf(
		THUMB_SIZE, maxf(0.0, float(_card_height()) - HEADER_HEIGHT - PADDING * 2)
	)
	var y := HEADER_HEIGHT + PADDING + lane_height * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else CARD_WIDTH, y)


func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
	var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
	var count := ports.size()
	for index in range(count):
		var anchor := position + _graph_port_position(index, count, is_input)
		if anchor.distance_to(world_position) <= PORT_HIT_RADIUS:
			return {"port_name": ports[index], "is_input": is_input, "port_index": index}
	return {}


func _rebuild_thumbnails() -> void:
	_thumbnail_textures.clear()
	_asset_hints.clear()
	var texture_asset_ids := asset_ids.duplicate()
	for compare_asset_id in compare_asset_ids:
		if not texture_asset_ids.has(compare_asset_id):
			texture_asset_ids.append(compare_asset_id)
	for asset_id in texture_asset_ids:
		var image := AssetLibrary.get_image(asset_id)
		if image == null:
			continue
		_asset_hints[asset_id] = {
			"size": image.get_size(),
			"color_count": _count_limited_colors(image, MAX_INSPECT_COLOR_HINTS),
		}
		var thumb := image.duplicate()
		var longest := maxi(thumb.get_width(), thumb.get_height())
		if longest > THUMB_TEXTURE_SIZE:
			var ratio := float(THUMB_TEXTURE_SIZE) / float(longest)
			thumb.resize(
				maxi(1, int(round(thumb.get_width() * ratio))),
				maxi(1, int(round(thumb.get_height() * ratio))),
				Image.INTERPOLATE_NEAREST
			)
		_thumbnail_textures[asset_id] = ImageTexture.create_from_image(thumb)


func _asset_hint_for(asset_id: String) -> String:
	var hint: Dictionary = _asset_hints.get(asset_id, {})
	if hint.is_empty():
		return ""
	var image_size: Vector2i = hint.get("size", Vector2i.ZERO)
	var color_count := int(hint.get("color_count", 0))
	if color_count > MAX_INSPECT_COLOR_HINTS:
		return (
			Strings.BATCH_INSPECT_HINT_CAPPED_FORMAT
			% [image_size.x, image_size.y, MAX_INSPECT_COLOR_HINTS]
		)
	return Strings.BATCH_INSPECT_HINT_FORMAT % [image_size.x, image_size.y, color_count]


func _count_limited_colors(image: Image, max_colors: int) -> int:
	var colors := {}
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			colors[image.get_pixel(x, y).to_html(true)] = true
			if colors.size() > max_colors:
				return colors.size()
	return colors.size()


func _resolve_graph_batch_node_data() -> Dictionary:
	if not has_graph_binding():
		return {}
	var graph_data := ProjectService.get_graph_data(graph_id)
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node_data: Dictionary = raw_node
		if (
			String(node_data.get("id", "")) == node_id
			and String(node_data.get("type", "")) == "batch"
		):
			return node_data
	return {}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in Array(value):
			result.append(String(item))
	return result


func _review_state_map(value: Variant, valid_asset_ids: Array[String]) -> Dictionary:
	var result := {}
	if not (value is Dictionary):
		return result
	var valid_lookup := {}
	for asset_id in valid_asset_ids:
		valid_lookup[asset_id] = true
	var raw_states: Dictionary = value
	for key in raw_states.keys():
		var asset_id := String(key)
		if not valid_lookup.has(asset_id):
			continue
		var review_state := _normalize_review_state(String(raw_states[key]))
		if not review_state.is_empty():
			result[asset_id] = review_state
	return result


func _normalize_review_state(review_state: String) -> String:
	match review_state:
		REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
			return review_state
		_:
			return REVIEW_NONE


func _normalize_review_filter(value: String) -> String:
	match value:
		FILTER_ALL, FILTER_PENDING, REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
			return value
		_:
			return FILTER_ALL


func _normalize_review_layout(value: String) -> String:
	match value:
		LAYOUT_CONTACT, LAYOUT_FOCUS:
			return value
		_:
			return LAYOUT_CONTACT


func _normalize_focus_asset_id(new_focus_asset_id: String) -> String:
	return new_focus_asset_id if asset_ids.has(new_focus_asset_id) else ""


func _normalize_compare_mode(new_compare_mode: String) -> String:
	if not compare_asset_ids.is_empty():
		match new_compare_mode:
			COMPARE_PREVIOUS, COMPARE_SPLIT:
				return new_compare_mode
	return COMPARE_CURRENT


func _aligned_compare_asset_ids(value: Variant) -> Array[String]:
	var result := _string_array(value)
	if result.size() != asset_ids.size():
		return []
	return result


func _prune_selected_to_visible() -> void:
	var visible_lookup := _visible_lookup()
	for selected_id in selected_asset_ids.duplicate():
		if not visible_lookup.has(selected_id):
			selected_asset_ids.erase(selected_id)


func _prune_focus_to_visible() -> void:
	if focus_asset_id.is_empty():
		return
	if not _visible_lookup().has(focus_asset_id):
		focus_asset_id = ""


func _focus_anchor_index(visible_ids: Array[String]) -> int:
	var focus_index := visible_ids.find(focus_asset_id)
	if focus_index >= 0:
		return focus_index
	for selected_id in selected_asset_ids:
		var selected_index := visible_ids.find(selected_id)
		if selected_index >= 0:
			return selected_index
	return -1


func _focused_visible_asset_id() -> String:
	var visible_ids := get_visible_asset_ids()
	if visible_ids.is_empty():
		return ""
	var anchor_index := _focus_anchor_index(visible_ids)
	if anchor_index >= 0:
		return visible_ids[anchor_index]
	return visible_ids[0]


func _initial_focus_asset_id() -> String:
	return _focused_visible_asset_id()


func _focus_layout_asset_index_at_local(local: Vector2) -> int:
	var visible_ids := get_visible_asset_ids()
	if visible_ids.is_empty():
		return -1
	if _focus_rect().has_point(local):
		return visible_ids.find(_focused_visible_asset_id())
	var start_index := _filmstrip_start_index(visible_ids)
	var end_index := mini(visible_ids.size(), start_index + FOCUS_FILMSTRIP_VISIBLE)
	for index in range(start_index, end_index):
		if _filmstrip_rect(index - start_index).has_point(local):
			return index
	return -1


func _filmstrip_start_index(visible_ids: Array[String]) -> int:
	if visible_ids.size() <= FOCUS_FILMSTRIP_VISIBLE:
		return 0
	var anchor_index := _focus_anchor_index(visible_ids)
	if anchor_index < 0:
		anchor_index = 0
	var half_window := int(floor(float(FOCUS_FILMSTRIP_VISIBLE) * 0.5))
	return clampi(anchor_index - half_window, 0, visible_ids.size() - FOCUS_FILMSTRIP_VISIBLE)


func _visible_selected_array(value: Array) -> Array[String]:
	var visible_lookup := _visible_lookup()
	var result: Array[String] = []
	for raw_id in value:
		var asset_id := String(raw_id)
		if visible_lookup.has(asset_id) and not result.has(asset_id):
			result.append(asset_id)
	return result


func _texture_asset_id_for(asset_id: String) -> String:
	if compare_mode != COMPARE_PREVIOUS:
		return asset_id
	var compare_asset_id := _compare_asset_id_for(asset_id)
	return asset_id if compare_asset_id.is_empty() else compare_asset_id


func _compare_asset_id_for(asset_id: String) -> String:
	var index := asset_ids.find(asset_id)
	if index < 0 or index >= compare_asset_ids.size():
		return ""
	return compare_asset_ids[index]


func _visible_lookup() -> Dictionary:
	return _lookup(get_visible_asset_ids())


func _lookup(values: Array[String]) -> Dictionary:
	var result := {}
	for value in values:
		result[value] = true
	return result
