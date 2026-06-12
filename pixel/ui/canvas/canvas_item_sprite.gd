class_name PFCanvasItemSprite
extends Sprite2D

## 无限画布上的 sprite 元素。
## contract: 02-contracts/PROJECT-FORMAT.md §4；position 始终是整数世界坐标，texture_filter 始终最近邻。

const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")

var item_id := ""
var asset_id := ""
var scale_factor := 1
var locked := false
var frame_id: Variant = null
var source_image: Image = null


func setup_from_image(item_data: Dictionary, image: Image) -> void:
	item_id = String(item_data.get("id", IdUtil.uuid_v4()))
	asset_id = String(item_data.get("asset_id", ""))
	scale_factor = maxi(1, int(item_data.get("scale_factor", 1)))
	locked = bool(item_data.get("locked", false))
	frame_id = item_data.get("frame_id", null)
	z_index = int(item_data.get("z_index", 0))

	var raw_position: Variant = item_data.get("position", [0, 0])
	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
	scale = Vector2.ONE * float(scale_factor)
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	source_image = ImageMath.duplicate_rgba8(image)
	texture = ImageTexture.create_from_image(source_image)


func get_canvas_bounds() -> Rect2:
	if source_image == null:
		return Rect2(position, Vector2.ZERO)
	return Rect2(
		position, Vector2(source_image.get_width(), source_image.get_height()) * float(scale_factor)
	)


func contains_world_point(world_position: Vector2) -> bool:
	return get_canvas_bounds().has_point(world_position)


func to_canvas_data() -> Dictionary:
	return {
		"id": item_id,
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(round(position.x)), int(round(position.y))],
		"scale_factor": scale_factor,
		"z_index": z_index,
		"locked": locked,
		"frame_id": frame_id,
	}


func duplicate_image() -> Image:
	if source_image == null:
		return null
	return source_image.duplicate()
