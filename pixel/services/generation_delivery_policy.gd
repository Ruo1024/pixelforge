class_name PFGenerationDeliveryPolicy
extends RefCounted

## Fixed user-facing delivery sizes and GPT Image 2 request/crop rules.

const RESOLUTION_PRESETS: Array[String] = ["720p", "1080p", "2K", "4K"]
const ORIENTATIONS: Array[String] = ["landscape", "portrait", "square"]
const DELIVERY_SIZES := {
	"720p": {"landscape": [1280, 720], "portrait": [720, 1280], "square": [720, 720]},
	"1080p": {"landscape": [1920, 1080], "portrait": [1080, 1920], "square": [1080, 1080]},
	"2K": {"landscape": [2560, 1440], "portrait": [1440, 2560], "square": [1440, 1440]},
	"4K": {"landscape": [3840, 2160], "portrait": [2160, 3840], "square": [2160, 2160]},
}
const REQUEST_1080P := {"landscape": [1920, 1088], "portrait": [1088, 1920], "square": [1088, 1088]}


static func is_valid(resolution_preset: String, orientation: String) -> bool:
	return RESOLUTION_PRESETS.has(resolution_preset) and ORIENTATIONS.has(orientation)


static func delivery_size(resolution_preset: String, orientation: String) -> Array:
	if not is_valid(resolution_preset, orientation):
		return []
	return Array(DELIVERY_SIZES[resolution_preset][orientation]).duplicate()


static func request_size(resolution_preset: String, orientation: String) -> Array:
	if not is_valid(resolution_preset, orientation):
		return []
	if resolution_preset == "1080p":
		return Array(REQUEST_1080P[orientation]).duplicate()
	return delivery_size(resolution_preset, orientation)


static func preset_for_delivery(width: int, height: int) -> Dictionary:
	for resolution_preset in RESOLUTION_PRESETS:
		for orientation in ORIENTATIONS:
			if delivery_size(resolution_preset, orientation) == [width, height]:
				return {"resolution_preset": resolution_preset, "orientation": orientation}
	return {"resolution_preset": "1080p", "orientation": "square"}


static func center_crop_to_delivery(image: Image, delivery: Array) -> Image:
	if image == null or image.is_empty() or not _is_positive_pair(delivery):
		return null
	var width := int(delivery[0])
	var height := int(delivery[1])
	if image.get_width() < width or image.get_height() < height:
		return null
	var x := int((image.get_width() - width) / 2.0)
	var y := int((image.get_height() - height) / 2.0)
	return image.get_region(Rect2i(x, y, width, height))


static func _is_positive_pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value[0] is int
		and value[1] is int
		and int(value[0]) > 0
		and int(value[1]) > 0
	)
