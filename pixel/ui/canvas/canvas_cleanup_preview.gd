class_name PFCanvasCleanupPreview
extends RefCounted

## 清洗预览 sprite 管理器。
## 输入：源画布元素与预览 Image；输出：挂在 item_layer 上的半透明预览 Sprite2D。

const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CLEANUP_PREVIEW_Z_INDEX := 4095

var source_item_id := ""

var _sprite: Sprite2D = null


func show(
	item_layer: Node2D,
	items_by_id: Dictionary,
	source_id: String,
	preview_image: Image,
	opacity: float
) -> void:
	if not items_by_id.has(source_id):
		clear()
		return
	var source_item: Node = items_by_id[source_id]
	if source_item.get_script() != CanvasItemSpriteScript:
		clear()
		return

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "CleanupPreview"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		item_layer.add_child(_sprite)

	source_item_id = source_id
	_sprite.texture = ImageTexture.create_from_image(preview_image)
	_sprite.position = source_item.position
	_sprite.scale = source_item.scale
	_sprite.z_index = CLEANUP_PREVIEW_Z_INDEX
	_sprite.modulate = Color(1.0, 1.0, 1.0, clampf(opacity, 0.0, 1.0))
	update_alt_state()


func clear() -> void:
	source_item_id = ""
	if _sprite == null:
		return
	if is_instance_valid(_sprite):
		_sprite.queue_free()
	_sprite = null


func update_alt_state() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	_sprite.visible = not Input.is_key_pressed(KEY_ALT)
