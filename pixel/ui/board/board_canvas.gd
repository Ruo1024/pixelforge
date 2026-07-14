class_name PFBoardCanvas
extends Control

## Finite board viewport with nearest-neighbor pan/zoom and tile/free placement.

signal board_changed
signal fallback_warning(count: int)
signal palette_warning(asset_palette: String, project_palette: String)

const AnimationScript := preload("res://core/animation/pf_animation.gd")
const ExporterScript := preload("res://services/board_exporter.gd")
const TerrainBrushScript := preload("res://core/board/terrain_brush.gd")

var board: PFBoard = null
var selected_layer_id := ""
var selected_asset_id := ""
var selected_anim_id := ""
var terrain_group: PFTerrainGroup = null
var playing := true
var playback_speed := 1.0
var brush_mode := "paint"
var camera_offset := Vector2(32, 32)
var camera_zoom := 1.0

var _textures := {}
var _panning := false
var _last_mouse := Vector2.ZERO
var _playback_started_msec := 0
var _rectangle_start := Vector2i(-1, -1)
var _composite_cache_key := 0
var _composite_texture: ImageTexture = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_playback_started_msec = Time.get_ticks_msec()
	set_process(true)


func set_board(value: PFBoard) -> void:
	board = value
	selected_layer_id = String(board.layers[0].get("id", "")) if not board.layers.is_empty() else ""
	queue_redraw()


func set_selected_asset(asset_id: String, anim_id: String = "") -> void:
	selected_asset_id = asset_id
	selected_anim_id = anim_id
	terrain_group = null
	_warn_palette_mismatch(asset_id)


func set_terrain_group(group: PFTerrainGroup) -> void:
	terrain_group = group
	selected_anim_id = ""


func set_brush_mode(value: String) -> void:
	brush_mode = value if value in ["paint", "rectangle", "fill"] else "paint"


func set_playing(value: bool) -> void:
	playing = value
	if playing:
		_playback_started_msec = Time.get_ticks_msec()
	queue_redraw()


func _process(_delta: float) -> void:
	if playing and board != null and not ProjectService.get_document_data("animations").is_empty():
		queue_redraw()


func _draw() -> void:
	if board == null:
		return
	var tile_size := int(board.grid["tile_size"])
	var board_size := Vector2(int(board.grid["cols"]), int(board.grid["rows"])) * tile_size
	draw_rect(Rect2(camera_offset, board_size * camera_zoom), Color(0.08, 0.09, 0.11), true)
	if _has_special_blend():
		_draw_composite()
	else:
		for layer_value in board.layers:
			var layer: Dictionary = layer_value
			if not bool(layer.get("visible", true)):
				continue
			if String(layer.get("kind", "")) == PFBoard.LAYER_TILE:
				_draw_tile_layer(layer, tile_size)
			else:
				_draw_free_layer(layer)
	if camera_zoom >= 1.0 and tile_size * camera_zoom >= 8.0:
		_draw_grid(tile_size)
	draw_rect(Rect2(camera_offset, board_size * camera_zoom), Color(0.5, 0.55, 0.65), false, 1.0)


func _draw_tile_layer(layer: Dictionary, tile_size: int) -> void:
	var opacity := float(layer.get("opacity", 1.0))
	for key in Dictionary(layer.get("cells", {})).keys():
		var cell := PFBoard.parse_cell_key(String(key))
		var screen_pos := camera_offset + Vector2(cell * tile_size) * camera_zoom
		var rect := Rect2(screen_pos, Vector2(tile_size, tile_size) * camera_zoom)
		if not rect.intersects(Rect2(Vector2.ZERO, size)):
			continue
		var cell_data: Dictionary = layer["cells"][key]
		var texture := _asset_texture(String(cell_data.get("asset_id", "")))
		if texture != null:
			draw_texture_rect(texture, rect, false, Color(1, 1, 1, opacity))
		if bool(cell_data.get("fallback", false)):
			draw_circle(rect.position + Vector2(5, 5), 3.0, Color.YELLOW)


func _draw_free_layer(layer: Dictionary) -> void:
	var opacity := float(layer.get("opacity", 1.0))
	var time_ms := _current_time_ms()
	for item_value in layer.get("items", []):
		var item: Dictionary = item_value
		var asset_id := _item_asset_id(item, time_ms)
		var texture := _asset_texture(asset_id)
		if texture == null:
			continue
		var raw_pos: Array = item.get("pos", [0, 0])
		var screen_pos := (
			camera_offset + Vector2(float(raw_pos[0]), float(raw_pos[1])) * camera_zoom
		)
		var draw_size := Vector2(texture.get_width(), texture.get_height()) * camera_zoom
		draw_texture_rect(texture, Rect2(screen_pos, draw_size), false, Color(1, 1, 1, opacity))


func _draw_grid(tile_size: int) -> void:
	var cols := int(board.grid["cols"])
	var rows := int(board.grid["rows"])
	var step := tile_size * camera_zoom
	for x in range(cols + 1):
		var px := camera_offset.x + x * step
		draw_line(
			Vector2(px, camera_offset.y),
			Vector2(px, camera_offset.y + rows * step),
			Color(1, 1, 1, 0.08)
		)
	for y in range(rows + 1):
		var py := camera_offset.y + y * step
		draw_line(
			Vector2(camera_offset.x, py),
			Vector2(camera_offset.x + cols * step, py),
			Color(1, 1, 1, 0.08)
		)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = button.pressed
			_last_mouse = button.position
			accept_event()
		elif (
			button.pressed
			and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		):
			_zoom_at(button.position, 1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8)
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if button.pressed:
				if (
					button.button_index == MOUSE_BUTTON_LEFT
					and brush_mode == "rectangle"
					and terrain_group != null
				):
					_rectangle_start = _screen_to_cell(button.position)
				else:
					_place_at(button.position, button.button_index == MOUSE_BUTTON_RIGHT)
			elif button.button_index == MOUSE_BUTTON_LEFT and _rectangle_start.x >= 0:
				_apply_terrain_rectangle(_rectangle_start, _screen_to_cell(button.position))
				_rectangle_start = Vector2i(-1, -1)
			accept_event()
	elif event is InputEventMouseMotion and _panning:
		var motion: InputEventMouseMotion = event
		camera_offset += motion.position - _last_mouse
		_last_mouse = motion.position
		queue_redraw()
		accept_event()


func _place_at(screen_position: Vector2, erase: bool) -> void:
	if board == null or selected_layer_id.is_empty():
		return
	var local := ((screen_position - camera_offset) / camera_zoom).round()
	var layer := board.get_layer(selected_layer_id)
	if String(layer.get("kind", "")) == PFBoard.LAYER_TILE:
		var cell := _screen_to_cell(screen_position)
		if terrain_group != null:
			var brush := TerrainBrushScript.new()
			var result := (
				brush.flood_fill(board, selected_layer_id, cell, terrain_group)
				if brush_mode == "fill" and not erase
				else brush.paint(board, selected_layer_id, cell, terrain_group, erase)
			)
			var fallback_count := Array(result.get("fallback_cells", [])).size()
			if fallback_count > 0:
				fallback_warning.emit(fallback_count)
		else:
			board.set_cell(selected_layer_id, cell, "" if erase else selected_asset_id)
	elif not erase:
		board.add_free_item(selected_layer_id, selected_asset_id, Vector2i(local), selected_anim_id)
	else:
		_remove_nearest_free_item(layer, Vector2i(local))
	ProjectService.set_document_data("boards", board.id, board.to_json(), true)
	board_changed.emit()
	queue_redraw()


func _apply_terrain_rectangle(start: Vector2i, finish: Vector2i) -> void:
	if board == null or terrain_group == null:
		return
	var position := Vector2i(mini(start.x, finish.x), mini(start.y, finish.y))
	var extent := Vector2i(absi(finish.x - start.x) + 1, absi(finish.y - start.y) + 1)
	var result := TerrainBrushScript.new().rectangle_fill(
		board, selected_layer_id, Rect2i(position, extent), terrain_group
	)
	var fallback_count := Array(result.get("fallback_cells", [])).size()
	if fallback_count > 0:
		fallback_warning.emit(fallback_count)
	_commit_change()


func _commit_change() -> void:
	ProjectService.set_document_data("boards", board.id, board.to_json(), true)
	board_changed.emit()
	queue_redraw()


func _screen_to_cell(screen_position: Vector2) -> Vector2i:
	var local := (screen_position - camera_offset) / camera_zoom
	var tile_size := int(board.grid["tile_size"])
	return Vector2i(floori(local.x / tile_size), floori(local.y / tile_size))


func _has_special_blend() -> bool:
	for layer_value in board.layers:
		var layer: Dictionary = layer_value
		if bool(layer.get("visible", true)) and String(layer.get("blend", "normal")) != "normal":
			return true
	return false


func _draw_composite() -> void:
	var time_ms := _current_time_ms()
	var cache_key := hash(JSON.stringify(board.to_json())) ^ (int(time_ms / 50) if playing else 0)
	if _composite_texture == null or cache_key != _composite_cache_key:
		var image: Image = ExporterScript.new().compose(
			board, AssetLibrary, ProjectService.get_document_data("animations"), time_ms
		)
		if image == null:
			return
		_composite_texture = ImageTexture.create_from_image(image)
		_composite_cache_key = cache_key
	draw_texture_rect(
		_composite_texture,
		Rect2(camera_offset, Vector2(_composite_texture.get_size()) * camera_zoom),
		false
	)


func _remove_nearest_free_item(layer: Dictionary, position: Vector2i) -> void:
	var items: Array = layer.get("items", [])
	var best_index := -1
	var best_distance := 24.0
	for index in range(items.size()):
		var raw_pos: Array = Dictionary(items[index]).get("pos", [0, 0])
		var distance := Vector2(position).distance_to(Vector2(float(raw_pos[0]), float(raw_pos[1])))
		if distance < best_distance:
			best_distance = distance
			best_index = index
	if best_index >= 0:
		items.remove_at(best_index)


func _zoom_at(anchor: Vector2, factor: float) -> void:
	var world_anchor := (anchor - camera_offset) / camera_zoom
	camera_zoom = clampf(camera_zoom * factor, 0.125, 8.0)
	camera_offset = anchor - world_anchor * camera_zoom
	queue_redraw()


func _asset_texture(asset_id: String) -> ImageTexture:
	if asset_id.is_empty():
		return null
	if _textures.has(asset_id):
		return _textures[asset_id]
	var image: Image = AssetLibrary.get_image(asset_id)
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[asset_id] = texture
	return texture


func _item_asset_id(item: Dictionary, time_ms: int) -> String:
	var raw_anim_id: Variant = item.get("anim_id", "")
	var anim_id := "" if raw_anim_id == null else String(raw_anim_id)
	var animations := ProjectService.get_document_data("animations")
	if not anim_id.is_empty() and animations.has(anim_id):
		return AnimationScript.from_json(animations[anim_id]).get_frame_asset_id(
			time_ms, int(item.get("anim_offset_ms", 0))
		)
	return String(item.get("asset_id", ""))


func _current_time_ms() -> int:
	return (
		roundi((Time.get_ticks_msec() - _playback_started_msec) * playback_speed) if playing else 0
	)


func _warn_palette_mismatch(asset_id: String) -> void:
	if asset_id.is_empty():
		return
	var asset_palette := String(AssetLibrary.get_asset_meta(asset_id).get("palette_ref", ""))
	var project_palette := "db32"
	if (
		not asset_palette.is_empty()
		and not project_palette.is_empty()
		and asset_palette != project_palette
	):
		palette_warning.emit(asset_palette, project_palette)
