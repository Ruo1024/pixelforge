extends "res://addons/gut/test.gd"

const Matting := preload("res://core/pixel/matting.gd")
const Segmenter := preload("res://core/pixel/segmenter.gd")
const Outliner := preload("res://core/pixel/outliner.gd")
const Exporter := preload("res://services/exporter.gd")
const IdUtil := preload("res://core/util/id_util.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("M2 Flow")


func test_white_background_multi_object_image_mattes_slices_and_registers_assets() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var source := _make_multi_object_white_sheet()
	var parent_id: String = asset_library.register_image(
		source, "source_sheet", {"origin": "imported"}
	)

	var matte_result: Dictionary = Matting.matte(
		source, {"mode": Matting.MODE_FLOOD, "tolerance": 0.0, "feather": 0}
	)
	assert_true(bool(matte_result["is_flat_bg"]))
	var transparent: Image = matte_result["image"]
	var segments: Array = Segmenter.segment(transparent, {"merge_distance": 0, "min_area": 4})
	assert_eq(segments.size(), 3)

	var exported_items := []
	for i in range(segments.size()):
		var segment: Dictionary = segments[i]
		var outlined: Image = Outliner.add_outline(
			segment["image"], {"type": Outliner.TYPE_OUTER, "color": Color.BLACK}
		)
		var child_id: String = (
			asset_library
			. register_image(
				outlined,
				"source_sheet_%02d" % (i + 1),
				{
					"origin": "edited",
					"tags": ["matting", "slicing", "outline"],
					"provenance":
					{
						"provider": null,
						"model": null,
						"prompt": "",
						"seed": null,
						"parent_asset": parent_id,
						"graph_id": null,
						"created_at": IdUtil.utc_now_iso(),
						"slice": {"source_rect": _rect_to_array(segment["rect"])},
					},
				}
			)
		)
		var meta: Dictionary = asset_library.get_asset_meta(child_id)
		assert_eq(meta["provenance"]["parent_asset"], parent_id)
		exported_items.append({"name": meta["name"], "image": outlined})

	var packed: Dictionary = Exporter.pack_spritesheet(
		exported_items, {"columns": 3, "padding": 1, "image": "m2_flow.png"}
	)
	assert_eq(Dictionary(packed["json"])["frames"].size(), 3)
	var sheet: Image = packed["image"]
	assert_gt(sheet.get_width(), 0)


func _make_multi_object_white_sheet() -> Image:
	var image := Image.create(24, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_fill_rect(image, Rect2i(1, 2, 4, 4), Color.RED)
	_fill_rect(image, Rect2i(9, 1, 5, 5), Color.BLUE)
	_fill_rect(image, Rect2i(18, 3, 4, 3), Color.GREEN)
	return image


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			image.set_pixel(x, y, color)


func _rect_to_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
