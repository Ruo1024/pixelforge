class_name PFCanvasItemSprite
extends Sprite2D

## 无限画布上的 sprite 元素。
## contract: 02-contracts/PROJECT-FORMAT.md §4；position 始终是整数世界坐标，texture_filter 始终最近邻。

const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")
const UIFont := preload("res://ui/widgets/ui_font.gd")

signal display_title_change_requested(item_id: String, display_title: String)
signal size_change_requested(item_id: String, requested_size: Vector2i)

var item_id := ""
var asset_id := ""
var scale_factor := 1
var locked := false
var frame_id: Variant = null
var source_image: Image = null
var display_title := ""
var requested_size := Vector2i(320, 380)
var _raw_data := {}
var _preview_sprite: Sprite2D = null
var _lod_camera_zoom := 1.0
var _title_button: Button = null
var _title_edit: LineEdit = null


func setup_from_image(item_data: Dictionary, image: Image) -> void:
	_raw_data = item_data.duplicate(true)
	item_id = String(item_data.get("id", IdUtil.uuid_v4()))
	asset_id = String(item_data.get("asset_id", ""))
	scale_factor = maxi(1, int(item_data.get("scale_factor", 1)))
	display_title = CardContract.normalize_display_title(item_data.get("display_title", ""))
	locked = bool(item_data.get("locked", false))
	frame_id = item_data.get("frame_id", null)
	z_index = int(item_data.get("z_index", 0))

	var raw_position: Variant = item_data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	scale = Vector2.ONE
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	source_image = ImageMath.duplicate_rgba8(image)
	requested_size = CardContract.normalize_requested_size(
		"sprite",
		item_data.get("size", null),
		source_image.get_size() if source_image != null else Vector2i.ZERO,
		scale_factor
	)
	texture = null
	_rebuild_preview()
	_rebuild_header_controls()
	queue_redraw()


func get_canvas_bounds() -> Rect2:
	return Rect2(position, Vector2(requested_size))


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func to_canvas_data() -> Dictionary:
	var result := _raw_data.duplicate(true)
	result["id"] = item_id
	result["type"] = "sprite"
	result["asset_id"] = asset_id
	result["position"] = [int(round(position.x)), int(round(position.y))]
	result["scale_factor"] = scale_factor
	result["z_index"] = z_index
	result["locked"] = locked
	result["frame_id"] = frame_id
	result["size"] = CardContract.size_array(requested_size)
	if display_title.is_empty():
		result.erase("display_title")
	else:
		result["display_title"] = display_title
	return result


func duplicate_image() -> Image:
	if source_image == null:
		return null
	return source_image.duplicate()


func set_requested_size(value: Variant) -> void:
	requested_size = CardContract.normalize_requested_size(
		"sprite",
		value,
		source_image.get_size() if source_image != null else Vector2i.ZERO,
		scale_factor
	)
	_rebuild_preview()
	_rebuild_header_controls()
	queue_redraw()


func set_display_title(value: Variant) -> void:
	display_title = CardContract.normalize_display_title(value)
	_rebuild_header_controls()
	queue_redraw()


func set_lod_camera_zoom(value: float) -> void:
	_lod_camera_zoom = maxf(0.0, value)
	_rebuild_header_controls()
	queue_redraw()


func resize_handle_contains_world(world_position: Vector2) -> bool:
	if locked or _lod_camera_zoom < 0.75:
		return false
	var hit_world := 16.0 / maxf(_lod_camera_zoom, 0.01)
	var local := world_position - position
	return Rect2(
		Vector2(requested_size) - Vector2.ONE * hit_world, Vector2.ONE * hit_world
	).has_point(local)


func default_requested_size() -> Vector2i:
	return CardContract.default_size_for_type(
		"sprite",
		source_image.get_size() if source_image != null else Vector2i.ZERO,
		scale_factor
	)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(requested_size))
	draw_rect(rect, AppTheme.CARD, true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(requested_size.x, 32)), AppTheme.MEDIA_RAIL, true)
	draw_rect(rect, AppTheme.BORDER, false, 1.0)
	if not locked and _lod_camera_zoom >= 0.75:
		var end := Vector2(requested_size) - Vector2(4, 4)
		draw_line(end - Vector2(8, 0), end, AppTheme.TEXT_MUTED, 2.0)
		draw_line(end - Vector2(0, 8), end, AppTheme.TEXT_MUTED, 2.0)
	var font: Font = UIFont.get_font()
	if font == null:
		return
	var fallback := String(AssetLibrary.get_asset_meta(asset_id).get("name", ""))
	var title := display_title if not display_title.is_empty() else fallback
	draw_string(
		font,
		Vector2(16, 22),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		requested_size.x - 32,
		15,
		AppTheme.MEDIA_RAIL_TEXT
	)
	var meta := ""
	if source_image != null:
		meta = "%d×%d" % [source_image.get_width(), source_image.get_height()]
	draw_string(
		font,
		Vector2(16, requested_size.y - 9),
		meta,
		HORIZONTAL_ALIGNMENT_LEFT,
		requested_size.x - 32,
		12,
		AppTheme.TEXT_SECONDARY
	)


func _rebuild_preview() -> void:
	if _preview_sprite != null:
		remove_child(_preview_sprite)
		_preview_sprite.free()
		_preview_sprite = null
	if source_image == null:
		return
	_preview_sprite = Sprite2D.new()
	_preview_sprite.texture = ImageTexture.create_from_image(source_image)
	_preview_sprite.centered = false
	_preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var available := Vector2(requested_size.x - 32, requested_size.y - 60)
	var image_size := Vector2(source_image.get_size())
	var fit := minf(available.x / image_size.x, available.y / image_size.y)
	fit = maxf(fit, 0.0001)
	_preview_sprite.scale = Vector2.ONE * fit
	_preview_sprite.position = Vector2(16, 32) + (available - image_size * fit) * 0.5
	add_child(_preview_sprite)


func _rebuild_header_controls() -> void:
	if _title_button == null:
		_title_button = Button.new()
		_title_button.name = "TitleButton"
		_title_button.flat = true
		_title_button.focus_mode = Control.FOCUS_NONE
		_title_button.gui_input.connect(_on_title_button_input)
		add_child(_title_button)
	_title_button.position = Vector2(8, 2)
	_title_button.size = Vector2(maxf(32.0, requested_size.x - 16.0), 28)
	_title_button.visible = not locked and _lod_camera_zoom >= 0.75
	_title_button.tooltip_text = display_title


func begin_title_edit() -> void:
	if locked or _lod_camera_zoom < 0.75:
		return
	if _title_edit == null:
		_title_edit = LineEdit.new()
		_title_edit.name = "TitleEdit"
		_title_edit.text_submitted.connect(func(_value: String) -> void: _commit_title_edit())
		_title_edit.focus_exited.connect(_commit_title_edit)
		_title_edit.gui_input.connect(_on_title_edit_input)
		add_child(_title_edit)
	var fallback := String(AssetLibrary.get_asset_meta(asset_id).get("name", ""))
	_title_edit.position = Vector2(8, 2)
	_title_edit.size = Vector2(maxf(64.0, requested_size.x - 16.0), 28)
	_title_edit.text = display_title if not display_title.is_empty() else fallback
	_title_edit.visible = true
	_title_edit.grab_focus()
	_title_edit.select_all()


func _on_title_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click:
		begin_title_edit()


func _on_title_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_title_edit.visible = false
		get_viewport().set_input_as_handled()


func _commit_title_edit() -> void:
	if _title_edit == null or not _title_edit.visible:
		return
	var normalized := CardContract.normalize_display_title(_title_edit.text)
	_title_edit.visible = false
	if normalized != display_title:
		display_title_change_requested.emit(item_id, normalized)
