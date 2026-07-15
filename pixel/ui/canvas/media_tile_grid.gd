# gdlint: disable=max-public-methods
class_name PFMediaTileGrid
extends Control

## Shared virtualized image grid for Reference and Output cards.

signal item_pressed(item_id: String)
signal reorder_requested(item_id: String, before_item_id: String)
signal replace_requested(item_id: String)
signal remove_requested(item_id: String)

const Layout := preload("res://ui/canvas/output_layout_calculator.gd")
const Strings := preload("res://ui/shell/strings.gd")
const ACTION_MIN_SIZE := Vector2(32, 28)
const STATE_COLORS := {
	"queued": Color(0.24, 0.27, 0.32),
	"running": Color(0.22, 0.42, 0.62),
	"succeeded": Color(0.12, 0.14, 0.18),
	"failed": Color(0.64, 0.2, 0.22),
	"canceled": Color(0.32, 0.32, 0.34),
	"reference": Color(0.12, 0.14, 0.18),
}

var scroll_offset := 0.0
var _items: Array[Dictionary] = []
var _active_tiles := {}
var _tile_pool: Array[Button] = []
var _all_tiles: Array[Button] = []
var _texture_cache := {}
var _reorder_enabled := false
var _actions_enabled := false
var _drag_item_id := ""
var _drag_position := Vector2.ZERO
var _insert_before_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	gui_input.connect(_on_grid_input)
	set_process(false)
	_refresh_visible_tiles()


func configure_items(
	items: Array,
	preserve_scroll: bool = false,
	reorder_enabled: bool = false,
	actions_enabled: bool = false
) -> void:
	var previous := scroll_offset
	_items = _normalized_items(items)
	_reorder_enabled = reorder_enabled
	_actions_enabled = actions_enabled
	scroll_offset = clampf(previous if preserve_scroll else 0.0, 0.0, max_scroll_offset())
	_refresh_visible_tiles()
	queue_redraw()


func item_ids() -> Array[String]:
	var result: Array[String] = []
	for item in _items:
		result.append(String(item["id"]))
	return result


func visible_item_ids() -> Array[String]:
	var result: Array[String] = []
	var viewport := Rect2(Vector2.ZERO, size)
	for index in range(_items.size()):
		if viewport.intersects(item_rect(index)):
			result.append(String(_items[index]["id"]))
	return result


func item_rect(index: int) -> Rect2:
	if index < 0 or index >= _items.size():
		return Rect2()
	var layout := _layout()
	var columns := maxi(1, int(layout["columns"]))
	var tile_size := int(layout["tile_size"])
	var column := index % columns
	var row := int(index / columns)
	return Rect2(
		Vector2(
			Layout.HORIZONTAL_PADDING + column * (tile_size + Layout.TILE_GAP),
			row * (tile_size + Layout.TILE_GAP) - scroll_offset,
		),
		Vector2(tile_size, tile_size)
	)


func item_id_at(local_position: Vector2) -> String:
	for index in range(_items.size()):
		if item_rect(index).has_point(local_position):
			return String(_items[index]["id"])
	return ""


func max_scroll_offset() -> float:
	return maxf(0.0, float(_layout()["content_height"]) - size.y)


func set_scroll_offset(value: float) -> void:
	scroll_offset = clampf(value, 0.0, max_scroll_offset())
	_refresh_visible_tiles()
	queue_redraw()


func handle_wheel(direction: int, zoom_modifier: bool) -> bool:
	if zoom_modifier or direction == 0:
		return false
	var step := float(maxi(48, int(_layout()["tile_size"]) + Layout.TILE_GAP))
	set_scroll_offset(scroll_offset + step * float(-direction))
	return true


func created_tile_count() -> int:
	return _all_tiles.size()


func active_tile_count() -> int:
	return _active_tiles.size()


func loaded_texture_count() -> int:
	return _texture_cache.size()


func request_reorder(item_id: String, before_item_id: String) -> bool:
	if (
		not _reorder_enabled
		or not item_ids().has(item_id)
		or (not before_item_id.is_empty() and not item_ids().has(before_item_id))
		or item_id == before_item_id
	):
		return false
	reorder_requested.emit(item_id, before_item_id)
	return true


func cancel_drag() -> void:
	_drag_item_id = ""
	_insert_before_id = ""
	set_process(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		set_scroll_offset(scroll_offset)


func _draw() -> void:
	var viewport := Rect2(Vector2.ZERO, size)
	for index in range(_items.size()):
		var rect := item_rect(index)
		if not rect.intersects(viewport):
			continue
		var status := String(_items[index].get("status", "reference"))
		draw_rect(rect, STATE_COLORS.get(status, STATE_COLORS["reference"]), true)
		draw_rect(rect, Color(0.72, 0.75, 0.8), false, 1.0)
	if not _drag_item_id.is_empty():
		var insert_index := _before_index(_insert_before_id)
		var marker := _insertion_marker(insert_index)
		draw_line(marker[0], marker[1], Color(0.35, 0.72, 1.0), 4.0)
		draw_rect(Rect2(_drag_position - Vector2(32, 32), Vector2(64, 64)), Color(1, 1, 1, 0.22))
	_draw_scrollbar()


func _process(_delta: float) -> void:
	if _drag_item_id.is_empty():
		set_process(false)
		return
	var margin := 40.0
	if _drag_position.y < margin:
		set_scroll_offset(scroll_offset - 16.0)
	elif _drag_position.y > size.y - margin:
		set_scroll_offset(scroll_offset + 16.0)


func _refresh_visible_tiles() -> void:
	if not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	var needed := _buffered_indices()
	for index_value in _active_tiles.keys():
		var index := int(index_value)
		if needed.has(index):
			continue
		var released: Button = _active_tiles[index]
		_active_tiles.erase(index)
		released.visible = false
		_tile_pool.append(released)
	for index in needed:
		var tile: Button = _active_tiles.get(index)
		if tile == null:
			tile = _acquire_tile()
			_active_tiles[index] = tile
		_configure_tile(tile, index)
	_prune_texture_cache()


func _acquire_tile() -> Button:
	if not _tile_pool.is_empty():
		return _tile_pool.pop_back()
	var tile := Button.new()
	tile.flat = true
	tile.set_meta("actions_hover_epoch", 0)
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.pressed.connect(_on_tile_pressed.bind(tile))
	tile.gui_input.connect(_on_tile_input.bind(tile))
	tile.mouse_entered.connect(_set_tile_actions_visible.bind(tile, true))
	tile.mouse_exited.connect(_defer_tile_actions_hide.bind(tile))
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(preview)
	var order := Label.new()
	order.name = "Order"
	order.position = Vector2(8, 4)
	order.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(order)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	actions.offset_left = -76
	actions.offset_bottom = 32
	for spec in [["Replace", "↻"], ["Remove", "×"]]:
		var action := Button.new()
		action.name = String(spec[0])
		action.text = String(spec[1])
		action.tooltip_text = (
			Strings.text("ACTION_REPLACE")
			if String(spec[0]) == "Replace"
			else Strings.text("ACTION_REMOVE")
		)
		action.focus_mode = Control.FOCUS_NONE
		action.mouse_filter = Control.MOUSE_FILTER_STOP
		action.custom_minimum_size = ACTION_MIN_SIZE
		action.pressed.connect(_on_action_pressed.bind(String(spec[0]), tile))
		action.mouse_entered.connect(_set_tile_actions_visible.bind(tile, true))
		action.mouse_exited.connect(_defer_tile_actions_hide.bind(tile))
		actions.add_child(action)
	actions.mouse_entered.connect(_set_tile_actions_visible.bind(tile, true))
	actions.mouse_exited.connect(_defer_tile_actions_hide.bind(tile))
	tile.add_child(actions)
	add_child(tile)
	_all_tiles.append(tile)
	return tile


func _configure_tile(tile: Button, index: int) -> void:
	var item: Dictionary = _items[index]
	tile.set_meta("actions_hover_epoch", int(tile.get_meta("actions_hover_epoch", 0)) + 1)
	tile.set_meta("index", index)
	tile.set_meta("item_id", String(item["id"]))
	tile.position = item_rect(index).position
	tile.size = item_rect(index).size
	tile.visible = true
	var preview: TextureRect = tile.get_node("Preview")
	preview.texture = _texture_for(String(item.get("asset_id", "")))
	var order: Label = tile.get_node("Order")
	order.text = String(item.get("order_label", ""))
	var actions: HBoxContainer = tile.get_node("Actions")
	actions.visible = false


func _texture_for(asset_id: String) -> Texture2D:
	if asset_id.is_empty() or not AssetLibrary.has_asset(asset_id):
		return null
	if _texture_cache.has(asset_id):
		return _texture_cache[asset_id]
	var image: Image = AssetLibrary.get_image(asset_id)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[asset_id] = texture
	return texture


func _prune_texture_cache() -> void:
	var active_assets := {}
	for index in _active_tiles:
		var asset_id := String(_items[int(index)].get("asset_id", ""))
		if not asset_id.is_empty():
			active_assets[asset_id] = true
	for asset_id in _texture_cache.keys():
		if not active_assets.has(asset_id):
			_texture_cache.erase(asset_id)


func _buffered_indices() -> Array[int]:
	var result: Array[int] = []
	if _items.is_empty():
		return result
	var layout := _layout()
	var columns := maxi(1, int(layout["columns"]))
	var stride := maxi(1, int(layout["tile_size"]) + Layout.TILE_GAP)
	var first_row := maxi(0, int(floor(scroll_offset / float(stride))) - 1)
	var last_row := int(ceil((scroll_offset + size.y) / float(stride))) + 1
	var first_index := first_row * columns
	var last_index := mini(_items.size(), (last_row + 1) * columns)
	for index in range(first_index, last_index):
		result.append(index)
	return result


func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			if handle_wheel(direction, event.ctrl_pressed or event.meta_pressed):
				accept_event()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _drag_item_id.is_empty():
			cancel_drag()
			accept_event()


func _on_tile_pressed(tile: Button) -> void:
	if _drag_item_id.is_empty():
		item_pressed.emit(String(tile.get_meta("item_id", "")))


func _on_tile_input(event: InputEvent, tile: Button) -> void:
	if not _reorder_enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_item_id = String(tile.get_meta("item_id", ""))
			_drag_position = event.position + tile.position
			_insert_before_id = _target_before_id(_drag_position)
			set_process(true)
		else:
			var dragged := _drag_item_id
			var before := _insert_before_id
			cancel_drag()
			request_reorder(dragged, before)
		tile.accept_event()
	elif event is InputEventMouseMotion and not _drag_item_id.is_empty():
		_drag_position = event.position + tile.position
		_insert_before_id = _target_before_id(_drag_position)
		queue_redraw()
		tile.accept_event()


func _on_action_pressed(action_name: String, tile: Button) -> void:
	var item_id := String(tile.get_meta("item_id", ""))
	if action_name == "Replace":
		replace_requested.emit(item_id)
	else:
		remove_requested.emit(item_id)


func _set_tile_actions_visible(tile: Button, visible_value: bool) -> void:
	if tile != null and tile.visible:
		if visible_value:
			tile.set_meta("actions_hover_epoch", int(tile.get_meta("actions_hover_epoch", 0)) + 1)
		tile.get_node("Actions").visible = _actions_enabled and visible_value


func _defer_tile_actions_hide(tile: Button) -> void:
	var hover_epoch := int(tile.get_meta("actions_hover_epoch", 0))
	call_deferred("_hide_tile_actions_if_pointer_left", tile, hover_epoch)


func _hide_tile_actions_if_pointer_left(tile: Button, hover_epoch: int) -> void:
	if tile == null or not is_instance_valid(tile) or not tile.visible:
		return
	if int(tile.get_meta("actions_hover_epoch", 0)) != hover_epoch:
		return
	var pointer_inside := Rect2(Vector2.ZERO, tile.size).has_point(tile.get_local_mouse_position())
	if not pointer_inside:
		tile.get_node("Actions").visible = false


func _target_before_id(local_position: Vector2) -> String:
	var layout := _layout()
	var columns := maxi(1, int(layout["columns"]))
	var stride := maxi(1, int(layout["tile_size"]) + Layout.TILE_GAP)
	var column := clampi(int(local_position.x / float(stride)), 0, columns - 1)
	var row := maxi(0, int((local_position.y + scroll_offset) / float(stride)))
	var index := clampi(row * columns + column, 0, _items.size())
	return "" if index >= _items.size() else String(_items[index]["id"])


func _before_index(item_id: String) -> int:
	if item_id.is_empty():
		return _items.size()
	for index in range(_items.size()):
		if String(_items[index]["id"]) == item_id:
			return index
	return _items.size()


func _insertion_marker(index: int) -> Array[Vector2]:
	if _items.is_empty():
		return [Vector2(Layout.HORIZONTAL_PADDING, 8), Vector2(size.x - 8, 8)]
	if index >= _items.size():
		var last := item_rect(_items.size() - 1)
		return [Vector2(last.end.x + 3, last.position.y), Vector2(last.end.x + 3, last.end.y)]
	var rect := item_rect(index)
	return [Vector2(rect.position.x - 3, rect.position.y), Vector2(rect.position.x - 3, rect.end.y)]


func _draw_scrollbar() -> void:
	if max_scroll_offset() <= 0.0:
		return
	var ratio := size.y / maxf(size.y + max_scroll_offset(), 1.0)
	var thumb_height := maxf(24.0, size.y * ratio)
	var travel := maxf(0.0, size.y - thumb_height)
	var y := travel * scroll_offset / maxf(max_scroll_offset(), 1.0)
	draw_rect(
		Rect2(
			size.x - Layout.SCROLLBAR_VISUAL_WIDTH, y, Layout.SCROLLBAR_VISUAL_WIDTH, thumb_height
		),
		Color(0.72, 0.75, 0.8, 0.72),
		true
	)


func _layout() -> Dictionary:
	return Layout.calculate(int(size.x), _items.size())


func _normalized_items(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_value in value:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("id", ""))
		if item_id.is_empty():
			continue
		result.append(item.duplicate(true))
	return result
