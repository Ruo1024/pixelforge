class_name PFCanvasBatchCard
extends Node2D

## M2.1 批次内容卡（无连线 MVP）。
## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。

const IdUtil := preload("res://core/util/id_util.gd")
const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
const Strings := preload("res://ui/shell/strings.gd")

const CARD_WIDTH := 600
const HEADER_HEIGHT := 40
const PADDING := 16
const THUMB_SIZE := 128
const THUMB_TEXTURE_SIZE := 192
const THUMB_GAP := 12
const MIN_CARD_HEIGHT := 216
const BACKGROUND := Color(0.16, 0.17, 0.18, 0.96)
const BORDER := Color(0.52, 0.62, 0.72, 1.0)
const SELECTED_BORDER := Color(0.1, 0.85, 0.65, 1.0)
const THUMB_BACKGROUND := Color(0.08, 0.085, 0.09, 1.0)
const OVERVIEW_BACKGROUND := Color(0.095, 0.105, 0.115, 1.0)
const OVERVIEW_PENDING := Color(0.48, 0.54, 0.56, 0.9)
const INSPECT_CHECKER_A := Color(0.18, 0.18, 0.18, 1.0)
const INSPECT_CHECKER_B := Color(0.28, 0.28, 0.28, 1.0)
const INSPECT_GRID := Color(1.0, 1.0, 1.0, 0.22)
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
const CHECKER_SIZE := 8.0

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

var _thumbnail_textures := {}
var _font: Font = null
var _lod_profile_override := ""


func setup_from_data(data: Dictionary) -> void:
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	var graph_node_data := _resolve_graph_batch_node_data()
	var graph_params: Dictionary = graph_node_data.get("params", {})
	label = String(graph_params.get("label", data.get("label", "Batch")))
	asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
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
	_prune_selected_to_visible()
	_prune_focus_to_visible()
	locked = bool(data.get("locked", false))
	z_index = int(data.get("z_index", 0))
	var raw_position: Variant = data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rebuild_thumbnails()
	queue_redraw()


func to_canvas_data() -> Dictionary:
	if has_graph_binding():
		return {
			"id": item_id,
			"type": "node",
			"graph_id": graph_id,
			"node_id": node_id,
			"position": [int(round(position.x)), int(round(position.y))],
			"z_index": z_index,
			"collapsed": false,
			"review_layout": review_layout,
			"locked": locked,
		}
	return {
		"id": item_id,
		"type": "batch_card",
		"asset_ids": asset_ids.duplicate(),
		"selected_asset_ids": selected_asset_ids.duplicate(),
		"review_states": review_states.duplicate(true),
		"review_filter": review_filter,
		"focus_asset_id": focus_asset_id,
		"compare_asset_ids": compare_asset_ids.duplicate(),
		"compare_mode": compare_mode,
		"review_layout": review_layout,
		"label": label,
		"position": [int(round(position.x)), int(round(position.y))],
		"z_index": z_index,
		"locked": locked,
	}


func has_graph_binding() -> bool:
	return not graph_id.is_empty() and not node_id.is_empty()


func get_canvas_bounds() -> Rect2:
	return Rect2(position, Vector2(CARD_WIDTH, _card_height()))


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
	var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
	var count := ports.size()
	if count <= 0:
		return position + Vector2(0.0 if is_input else CARD_WIDTH, _card_height() * 0.5)
	var index := ports.find(port_name)
	if index < 0:
		index = 0
	return position + _graph_port_position(index, count, is_input)


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


func _get_lod_profile() -> String:
	if not _lod_profile_override.is_empty():
		return LODProfile.normalize_profile(_lod_profile_override)
	return LODProfile.profile_for_art_scale(_current_art_scale())


func _set_lod_profile_override_for_test(lod_profile: String) -> void:
	_lod_profile_override = (
		"" if lod_profile.is_empty() else LODProfile.normalize_profile(lod_profile)
	)
	queue_redraw()


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


func _draw() -> void:
	_font = ThemeDB.fallback_font if _font == null else _font
	var card_rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, _card_height()))
	draw_rect(card_rect, BACKGROUND, true)
	draw_rect(card_rect, BORDER, false, 1.0)
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, HEADER_HEIGHT)), Color(0.21, 0.22, 0.24, 1.0), true
	)
	if _font != null:
		var visible_count := get_visible_asset_ids().size()
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

	var columns := _columns()
	var visible_ids := get_visible_asset_ids()
	var lod_profile := _get_lod_profile()
	if lod_profile == LODProfile.PROFILE_OVERVIEW:
		_draw_overview_layout(visible_ids)
	elif review_layout == LAYOUT_FOCUS:
		_draw_focus_layout(visible_ids, lod_profile)
	else:
		for index in range(visible_ids.size()):
			_draw_thumbnail(visible_ids[index], _thumb_rect(index, columns), lod_profile)
	if has_graph_binding():
		_draw_graph_ports()


func _draw_overview_layout(visible_ids: Array[String]) -> void:
	var body := Rect2(
		Vector2(PADDING, HEADER_HEIGHT + PADDING),
		Vector2(
			CARD_WIDTH - PADDING * 2, maxf(0.0, float(_card_height() - HEADER_HEIGHT - PADDING * 2))
		)
	)
	if body.size.y <= 0.0:
		return
	draw_rect(body, OVERVIEW_BACKGROUND, true)
	if asset_ids.is_empty():
		return
	var bar := Rect2(body.position + Vector2(0.0, 8.0), Vector2(body.size.x, 10.0))
	_draw_overview_segments(bar, _overview_counts(asset_ids), asset_ids.size())
	if _font != null:
		draw_string(
			_font,
			body.position + Vector2(0.0, 48.0),
			"%d / %d" % [visible_ids.size(), asset_ids.size()],
			HORIZONTAL_ALIGNMENT_LEFT,
			body.size.x,
			32,
			Color(0.86, 0.9, 0.9, 1.0)
		)


func _draw_overview_segments(bar: Rect2, counts: Dictionary, total: int) -> void:
	if total <= 0:
		return
	var specs := [
		{"count": int(counts.get(REVIEW_KEEP, 0)), "color": KEEP_MARK},
		{"count": int(counts.get(REVIEW_FLAG, 0)), "color": FLAG_MARK},
		{"count": int(counts.get(REVIEW_REJECT, 0)), "color": REJECT_MARK},
		{"count": int(counts.get(FILTER_PENDING, 0)), "color": OVERVIEW_PENDING},
	]
	var cursor_x := bar.position.x
	var remaining_width := bar.size.x
	for spec in specs:
		var count := int(spec["count"])
		if count <= 0:
			continue
		var width := minf(remaining_width, maxf(1.0, bar.size.x * float(count) / float(total)))
		draw_rect(
			Rect2(Vector2(cursor_x, bar.position.y), Vector2(width, bar.size.y)), spec["color"]
		)
		cursor_x += width
		remaining_width = maxf(0.0, bar.end.x - cursor_x)


func _draw_focus_layout(visible_ids: Array[String], lod_profile: String) -> void:
	if visible_ids.is_empty():
		return
	var focused_asset_id := _focused_visible_asset_id()
	if focused_asset_id.is_empty():
		return
	_draw_thumbnail(focused_asset_id, _focus_rect(), lod_profile)
	var start_index := _filmstrip_start_index(visible_ids)
	var end_index := mini(visible_ids.size(), start_index + FOCUS_FILMSTRIP_VISIBLE)
	for index in range(start_index, end_index):
		_draw_thumbnail(visible_ids[index], _filmstrip_rect(index - start_index), lod_profile)


func _draw_thumbnail(asset_id: String, rect: Rect2, lod_profile: String) -> void:
	draw_rect(rect, THUMB_BACKGROUND, true)
	if lod_profile == LODProfile.PROFILE_INSPECT:
		_draw_checker_background(rect)
	if compare_mode == COMPARE_SPLIT:
		_draw_split_compare_thumbnail(asset_id, rect, lod_profile)
	else:
		_draw_thumbnail_texture(_texture_asset_id_for(asset_id), rect, lod_profile)
	var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
	draw_rect(rect, border_color, false, 1.5)
	_draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
	if focus_asset_id == asset_id:
		draw_rect(rect.grow(3.0), FOCUS_BORDER, false, 2.5)


func _draw_split_compare_thumbnail(asset_id: String, rect: Rect2, lod_profile: String) -> void:
	var compare_asset_id := _compare_asset_id_for(asset_id)
	if compare_asset_id.is_empty():
		_draw_thumbnail_texture(asset_id, rect, lod_profile)
		return
	var left_rect := Rect2(rect.position, Vector2(floor(rect.size.x * 0.5), rect.size.y))
	var right_rect := Rect2(
		Vector2(rect.position.x + left_rect.size.x, rect.position.y),
		Vector2(rect.size.x - left_rect.size.x, rect.size.y)
	)
	_draw_thumbnail_texture(compare_asset_id, left_rect, lod_profile)
	_draw_thumbnail_texture(asset_id, right_rect, lod_profile)
	var divider_x := rect.position.x + left_rect.size.x
	draw_line(
		Vector2(divider_x, rect.position.y), Vector2(divider_x, rect.end.y), COMPARE_DIVIDER, 2.0
	)


func _draw_thumbnail_texture(asset_id: String, rect: Rect2, lod_profile: String) -> void:
	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
	if texture != null:
		var image_size := texture.get_size()
		var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
		var draw_size := image_size * scale
		var draw_pos := rect.position + (rect.size - draw_size) * 0.5
		draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
		var pixel_size := Vector2i(int(image_size.x), int(image_size.y))
		var draw_rect := Rect2(draw_pos, draw_size)
		if LODProfile.should_draw_pixel_grid(lod_profile, pixel_size, draw_rect):
			_draw_inspect_pixel_grid(draw_rect, pixel_size)


func _draw_checker_background(rect: Rect2) -> void:
	var columns := int(ceil(rect.size.x / CHECKER_SIZE))
	var rows := int(ceil(rect.size.y / CHECKER_SIZE))
	for row in range(rows):
		for column in range(columns):
			var color := INSPECT_CHECKER_A if (row + column) % 2 == 0 else INSPECT_CHECKER_B
			draw_rect(
				Rect2(
					rect.position + Vector2(float(column), float(row)) * CHECKER_SIZE,
					Vector2(CHECKER_SIZE, CHECKER_SIZE)
				),
				color,
				true
			)


func _draw_inspect_pixel_grid(draw_rect: Rect2, pixel_size: Vector2i) -> void:
	var cell_width := draw_rect.size.x / float(pixel_size.x)
	var cell_height := draw_rect.size.y / float(pixel_size.y)
	for column in range(1, pixel_size.x):
		var line_x := draw_rect.position.x + float(column) * cell_width
		draw_line(
			Vector2(line_x, draw_rect.position.y), Vector2(line_x, draw_rect.end.y), INSPECT_GRID
		)
	for row in range(1, pixel_size.y):
		var line_y := draw_rect.position.y + float(row) * cell_height
		draw_line(
			Vector2(draw_rect.position.x, line_y), Vector2(draw_rect.end.x, line_y), INSPECT_GRID
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
	var visible_count := get_visible_asset_ids().size()
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


func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
	var lane_height := minf(
		THUMB_SIZE, maxf(0.0, float(_card_height()) - HEADER_HEIGHT - PADDING * 2)
	)
	var y := HEADER_HEIGHT + PADDING + lane_height * float(index + 1) / float(count + 1)
	return Vector2(0.0 if is_input else CARD_WIDTH, y)


func _rebuild_thumbnails() -> void:
	_thumbnail_textures.clear()
	var texture_asset_ids := asset_ids.duplicate()
	for compare_asset_id in compare_asset_ids:
		if not texture_asset_ids.has(compare_asset_id):
			texture_asset_ids.append(compare_asset_id)
	for asset_id in texture_asset_ids:
		var image := AssetLibrary.get_image(asset_id)
		if image == null:
			continue
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


func _overview_counts(ids: Array[String]) -> Dictionary:
	var result := {REVIEW_KEEP: 0, REVIEW_REJECT: 0, REVIEW_FLAG: 0, FILTER_PENDING: 0}
	for asset_id in ids:
		var review_state := String(review_states.get(asset_id, REVIEW_NONE))
		if review_state.is_empty():
			result[FILTER_PENDING] = int(result[FILTER_PENDING]) + 1
		elif result.has(review_state):
			result[review_state] = int(result[review_state]) + 1
	return result


func _current_art_scale() -> float:
	var parent_node := get_parent()
	if parent_node is Node2D:
		return absf((parent_node as Node2D).scale.x)
	return absf(scale.x)


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
