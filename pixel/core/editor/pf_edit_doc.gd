class_name PFEditDoc
extends RefCounted

## Transient frame-by-layer edit document; persisted outputs remain Asset and Animation records.

const CompositorScript := preload("res://services/compositor.gd")
const ImageMath := preload("res://core/util/image_math.gd")

var size := Vector2i(16, 16)
var layers: Array = []
var frame_durations: Array = [100]
var palette: Array[Color] = []
var tags: Array = []
var source_asset_id := ""
var source_animation_id := ""
var dirty := false


static func from_asset(image: Image, asset_id: String, colors: Array[Color] = []) -> PFEditDoc:
	var document := PFEditDoc.new()
	document.size = image.get_size()
	document.source_asset_id = asset_id
	document.palette = colors.duplicate()
	document.layers = [document._make_layer("Artwork", [ImageMath.duplicate_rgba8(image)])]
	return document


static func from_animation(
	animation: PFAnimation, asset_library: Node, colors: Array[Color] = []
) -> PFEditDoc:
	var frames: Array[Image] = []
	for asset_id in animation.frames:
		var image: Image = asset_library.get_image(String(asset_id))
		if image != null:
			frames.append(ImageMath.duplicate_rgba8(image))
	if frames.is_empty():
		return null
	var document := PFEditDoc.new()
	document.size = frames[0].get_size()
	document.source_animation_id = animation.id
	document.source_asset_id = String(animation.frames[0])
	document.frame_durations = animation.durations_ms.duplicate()
	document.palette = colors.duplicate()
	document.layers = [document._make_layer("Artwork", frames)]
	return document


func add_layer(layer_name: String, source: Image = null) -> int:
	var frames: Array[Image] = []
	for _index in range(frame_count()):
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		if source != null:
			CompositorScript.blend_image(image, source)
		frames.append(image)
	layers.append(_make_layer(layer_name, frames))
	dirty = true
	return layers.size() - 1


func add_frame(copy_index: int = -1, duration_ms: int = 100) -> int:
	var source_index := clampi(copy_index, 0, frame_count() - 1)
	for layer_value in layers:
		var layer: Dictionary = layer_value
		var frames: Array = layer["frames"]
		var image: Image
		if copy_index >= 0 and not frames.is_empty():
			image = ImageMath.duplicate_rgba8(frames[source_index])
		else:
			image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			image.fill(Color.TRANSPARENT)
		frames.append(image)
	frame_durations.append(maxi(1, duration_ms))
	dirty = true
	return frame_count() - 1


func remove_frame(index: int) -> bool:
	if frame_count() <= 1 or index < 0 or index >= frame_count():
		return false
	for layer_value in layers:
		Dictionary(layer_value)["frames"].remove_at(index)
	frame_durations.remove_at(index)
	dirty = true
	return true


func move_frame(from_index: int, to_index: int) -> bool:
	if from_index < 0 or from_index >= frame_count():
		return false
	var target := clampi(to_index, 0, frame_count() - 1)
	for layer_value in layers:
		var frames: Array = Dictionary(layer_value)["frames"]
		var frame: Image = frames.pop_at(from_index)
		frames.insert(target, frame)
	var duration: int = frame_durations.pop_at(from_index)
	frame_durations.insert(target, duration)
	dirty = true
	return true


func frame_count() -> int:
	return frame_durations.size()


func get_frame(layer_index: int, frame_index: int) -> Image:
	if layer_index < 0 or layer_index >= layers.size():
		return null
	var frames: Array = Dictionary(layers[layer_index]).get("frames", [])
	return frames[frame_index] if frame_index >= 0 and frame_index < frames.size() else null


func flatten(frame_index: int) -> Image:
	var output := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for layer_value in layers:
		var layer: Dictionary = layer_value
		if not bool(layer.get("visible", true)):
			continue
		var frames: Array = layer.get("frames", [])
		if frame_index >= 0 and frame_index < frames.size():
			CompositorScript.blend_image(
				output,
				frames[frame_index],
				Vector2i.ZERO,
				float(layer.get("opacity", 1.0)),
				String(layer.get("blend", "normal"))
			)
	return output


func snapshot() -> Dictionary:
	var layer_copies := []
	for layer_value in layers:
		var layer: Dictionary = layer_value
		var copy := layer.duplicate(true)
		copy["frames"] = []
		for frame in layer.get("frames", []):
			copy["frames"].append(ImageMath.duplicate_rgba8(frame))
		layer_copies.append(copy)
	return {
		"layers": layer_copies,
		"frame_durations": frame_durations.duplicate(),
		"palette": palette.duplicate(),
		"tags": tags.duplicate(true),
	}


func restore(state: Dictionary) -> void:
	layers = state.get("layers", []).duplicate(true)
	frame_durations = state.get("frame_durations", [100]).duplicate()
	palette = state.get("palette", []).duplicate()
	tags = state.get("tags", []).duplicate(true)
	dirty = true


func _make_layer(layer_name: String, frames: Array) -> Dictionary:
	return {
		"name": layer_name,
		"frames": frames,
		"visible": true,
		"opacity": 1.0,
		"blend": "normal",
		"locked": false,
	}
