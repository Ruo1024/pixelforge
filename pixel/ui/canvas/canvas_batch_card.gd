class_name PFCanvasBatchCard
extends Node2D

## M2.1 批次内容卡（无连线 MVP）。
## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。

const IdUtil := preload("res://core/util/id_util.gd")

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

var item_id := ""
var graph_id := ""
var node_id := ""
var asset_ids: Array[String] = []
var selected_asset_ids: Array[String] = []
var label := ""
var locked := false

var _thumbnail_textures := {}
var _font: Font = null


func setup_from_data(data: Dictionary) -> void:
	item_id = String(data.get("id", IdUtil.uuid_v4()))
	graph_id = String(data.get("graph_id", ""))
	node_id = String(data.get("node_id", ""))
	var graph_node_data := _resolve_graph_batch_node_data()
	var graph_params: Dictionary = graph_node_data.get("params", {})
	label = String(graph_params.get("label", data.get("label", "Batch")))
	asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
	selected_asset_ids = _string_array(data.get("selected_asset_ids", []))
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
			"locked": locked,
		}
	return {
		"id": item_id,
		"type": "batch_card",
		"asset_ids": asset_ids.duplicate(),
		"selected_asset_ids": selected_asset_ids.duplicate(),
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


func set_asset_ids(new_asset_ids: Array) -> void:
	asset_ids = _string_array(new_asset_ids)
	for selected_id in selected_asset_ids.duplicate():
		if not asset_ids.has(selected_id):
			selected_asset_ids.erase(selected_id)
	_rebuild_thumbnails()
	queue_redraw()


func get_selected_or_all_asset_ids() -> Array[String]:
	if selected_asset_ids.is_empty():
		return asset_ids.duplicate()
	return selected_asset_ids.duplicate()


func toggle_asset_at_world(world_position: Vector2) -> bool:
	var index := asset_index_at_world(world_position)
	if index < 0 or index >= asset_ids.size():
		return false
	var asset_id := asset_ids[index]
	if selected_asset_ids.has(asset_id):
		selected_asset_ids.erase(asset_id)
	else:
		selected_asset_ids.append(asset_id)
	queue_redraw()
	return true


func asset_index_at_world(world_position: Vector2) -> int:
	var local := world_position - position
	if local.y < HEADER_HEIGHT:
		return -1
	var columns := _columns()
	for index in range(asset_ids.size()):
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
		draw_string(
			_font,
			Vector2(PADDING, 28),
			"%s (%d)" % [label, asset_ids.size()],
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - PADDING * 2,
			18,
			Color(0.9, 0.92, 0.92, 1.0)
		)

	var columns := _columns()
	for index in range(asset_ids.size()):
		_draw_thumbnail(index, _thumb_rect(index, columns))


func _draw_thumbnail(index: int, rect: Rect2) -> void:
	var asset_id := asset_ids[index]
	draw_rect(rect, THUMB_BACKGROUND, true)
	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
	if texture != null:
		var image_size := texture.get_size()
		var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
		var draw_size := image_size * scale
		var draw_pos := rect.position + (rect.size - draw_size) * 0.5
		draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
	var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
	draw_rect(rect, border_color, false, 1.5)


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


func _card_height() -> int:
	if asset_ids.is_empty():
		return MIN_CARD_HEIGHT
	var rows := int(ceil(float(asset_ids.size()) / float(_columns())))
	return maxi(
		MIN_CARD_HEIGHT, HEADER_HEIGHT + PADDING * 2 + rows * THUMB_SIZE + (rows - 1) * THUMB_GAP
	)


func _columns() -> int:
	return maxi(1, int((CARD_WIDTH - PADDING * 2 + THUMB_GAP) / (THUMB_SIZE + THUMB_GAP)))


func _rebuild_thumbnails() -> void:
	_thumbnail_textures.clear()
	for asset_id in asset_ids:
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
