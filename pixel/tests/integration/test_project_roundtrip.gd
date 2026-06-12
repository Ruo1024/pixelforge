extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Round Trip")


func test_project_save_open_roundtrip_matches_manifest_canvas_and_assets() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var ids := []

	for index in range(3):
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(float(index) / 3.0, 0.25, 0.75, 1.0))
		ids.append(asset_library.register_image(image, "asset_%d" % index, {"origin": "imported"}))

	var canvas_data := {
		"camera": {"center": [12, -8], "zoom": 2.0},
		"items":
		[
			_make_item("item_0", ids[0], Vector2(0, 0), 0),
			_make_item("item_1", ids[1], Vector2(16, 8), 1),
			_make_item("item_2", ids[2], Vector2(-4, 24), 2),
		],
	}
	project_service.set_canvas_data(canvas_data)

	var path := "user://tests/roundtrip_m0.pxproj"
	assert_eq(project_service.save_project(path), OK)

	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	assert_true(unpacked["ok"])
	assert_true(unpacked["files"].has("manifest.json"))
	assert_true(unpacked["files"].has("canvas/canvas.json"))

	var manifest: Dictionary = FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])
	assert_eq(int(manifest["format_version"]), 1)
	assert_eq(int(manifest["entries"]["asset_count"]), 3)

	assert_eq(project_service.open_project(path), OK)
	assert_eq(project_service.current_project.manifest["name"], "Round Trip")
	assert_eq(project_service.current_project.canvas["camera"], canvas_data["camera"])
	assert_eq(project_service.current_project.canvas["items"].size(), 3)

	for asset_id in ids:
		assert_true(asset_library.has_asset(asset_id))
		assert_not_null(asset_library.get_image(asset_id))


func test_project_open_rejects_future_format_version() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var path := "user://tests/future_format.pxproj"
	var manifest := {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION + 1,
		"app_version": "future",
		"id": "future-project",
		"name": "Future Format",
		"entries": {"asset_count": 0},
	}
	var canvas := {
		"camera": {"center": [0, 0], "zoom": 1.0},
		"items": [],
	}

	assert_eq(
		FileIOScript.zip_pack({"manifest.json": manifest, "canvas/canvas.json": canvas}, path), OK
	)
	assert_eq(project_service.open_project(path), ERR_FILE_UNRECOGNIZED)


func _make_item(item_id: String, asset_id: String, position: Vector2, z_index: int) -> Dictionary:
	return {
		"id": item_id,
		"type": "sprite",
		"asset_id": asset_id,
		"position": [int(position.x), int(position.y)],
		"scale_factor": 1,
		"z_index": z_index,
		"locked": false,
		"frame_id": null,
	}
