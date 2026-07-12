class_name PFGraphContext
extends RefCounted

## Controlled graph execution adapter. Nodes receive capabilities, never service autoloads.

var _asset_library: Node = null


func _init(asset_library: Node = null) -> void:
	_asset_library = asset_library


func has_asset(asset_id: String) -> bool:
	return (
		_asset_library != null
		and _asset_library.has_method("has_asset")
		and _asset_library.has_asset(asset_id)
	)


func get_asset_image(asset_id: String) -> Image:
	if not has_asset(asset_id) or not _asset_library.has_method("get_image"):
		return null
	var image: Image = _asset_library.get_image(asset_id)
	if image == null or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image.duplicate()


static func image_content_sha256(image: Image) -> String:
	if image == null or image.is_empty():
		return ""
	var normalized := image.duplicate()
	if normalized.get_format() != Image.FORMAT_RGBA8:
		normalized.convert(Image.FORMAT_RGBA8)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(
		PackedInt32Array([normalized.get_width(), normalized.get_height()]).to_byte_array()
	)
	context.update(normalized.get_data())
	return context.finish().hex_encode()
