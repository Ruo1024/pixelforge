extends "res://addons/gut/test.gd"

const PixelOperations := preload("res://services/pixel_operations.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Pixel Operations")


func test_independent_matting_operation_processes_assets_and_registers_provenance() -> void:
	var source_id := AssetLibrary.register_image(
		_make_source_image(), "source", {"origin": "imported"}
	)
	var result: Dictionary = PixelOperations.apply_to_assets(
		[source_id], AssetLibrary, PixelOperations.OP_MATTING, {}
	)

	assert_false(bool(result.get("canceled", false)))
	assert_eq(result["items"].size(), 1)

	var output_id := PixelOperations.register_result_asset(
		AssetLibrary, source_id, result["items"][0]
	)
	var meta := AssetLibrary.get_asset_meta(output_id)
	var provenance: Dictionary = meta["provenance"]

	assert_eq(meta["origin"], "edited")
	assert_eq(meta["tags"], ["matting"])
	assert_eq(provenance["parent_asset"], source_id)
	assert_eq(provenance["matting"]["source_asset"], source_id)
	assert_true(provenance["matting"]["params"].has("mode"))


func test_matting_report_is_metadata_safe() -> void:
	var result: Dictionary = PixelOperations.apply_image(
		PixelOperations.OP_MATTING, _make_source_image(), {}
	)
	var report: Dictionary = result["report"]

	assert_true(bool(result.get("ok", false)))
	assert_false(report.has("image"))
	assert_eq(String(result.get("provenance_key", "")), "matting")


func _make_source_image() -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.set_pixel(1, 1, Color.RED)
	image.set_pixel(2, 1, Color.RED)
	image.set_pixel(1, 2, Color.RED)
	image.set_pixel(2, 2, Color.RED)
	return image


func _disabled_cleanup_params() -> Dictionary:
	return {
		Pipeline.STEP_DETECT_GRID: {"enabled": false},
		Pipeline.STEP_RESAMPLE: {"enabled": false},
		Pipeline.STEP_QUANTIZE: {"enabled": false},
	}
