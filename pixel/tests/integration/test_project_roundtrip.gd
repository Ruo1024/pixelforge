extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")


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


func test_project_graphs_survive_zip_roundtrip() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var graph_data := {
		"graph_version": 1,
		"id": "graph_main",
		"name": "M3 Foundation",
		"nodes":
		[
			{
				"id": "batch_1",
				"type": "batch",
				"position": [32, 64],
				"params": {"asset_ids": ["asset-a", "asset-b"], "label": "Candidates"},
			},
		],
		"edges": [],
	}
	var canvas_data := {
		"camera": {"center": [0, 0], "zoom": 1.0},
		"items":
		[
			{
				"id": "node_item_1",
				"type": "node",
				"node_id": "batch_1",
				"graph_id": "graph_main",
				"position": [32, 64],
				"z_index": 2,
				"collapsed": false,
			},
		],
	}

	project_service.set_graph_data("graph_main", graph_data)
	project_service.set_canvas_data(canvas_data)

	var path := "user://tests/graph_roundtrip_m3.pxproj"
	assert_eq(project_service.save_project(path), OK)

	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	assert_true(unpacked["ok"])
	assert_true(unpacked["files"].has("graphs/graph_main.json"))

	var manifest: Dictionary = FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])
	assert_eq(manifest["entries"]["graphs"], ["graph_main"])

	assert_eq(project_service.open_project(path), OK)
	var loaded_graph: Dictionary = project_service.current_project.graphs["graph_main"]
	assert_eq(int(loaded_graph["graph_version"]), int(graph_data["graph_version"]))
	assert_eq(String(loaded_graph["id"]), String(graph_data["id"]))
	assert_eq(String(loaded_graph["name"]), String(graph_data["name"]))
	var loaded_node: Dictionary = loaded_graph["nodes"][0]
	var expected_node: Dictionary = graph_data["nodes"][0]
	assert_eq(String(loaded_node["id"]), String(expected_node["id"]))
	assert_eq(String(loaded_node["type"]), String(expected_node["type"]))
	assert_eq(_int_pair(loaded_node["position"]), _int_pair(expected_node["position"]))
	assert_eq(loaded_node["params"], expected_node["params"])
	assert_eq(loaded_graph["edges"], graph_data["edges"])
	assert_eq(project_service.current_project.canvas["items"][0]["type"], "node")
	assert_eq(project_service.current_project.canvas["items"][0]["node_id"], "batch_1")


func test_project_open_normalizes_graph_edge_schema() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var graph_data := {
		"graph_version": 1,
		"id": "graph_dirty_edges",
		"name": "Dirty Edges",
		"nodes":
		[
			{"id": "objects", "type": "object_list", "position": [0, 0], "params": {}},
			{"id": "generate", "type": "ai_generate", "position": [100, 0], "params": {}},
		],
		"edges":
		[
			{"from": ["objects"], "to": ["generate", "items", "ignored"]},
			"not-a-dictionary",
			{"from": ["objects", "items"], "to": ["generate", "items"]},
		],
	}

	project_service.set_graph_data("graph_dirty_edges", graph_data)
	project_service.set_canvas_data({"camera": {"center": [0, 0], "zoom": 1.0}, "items": []})

	var path := "user://tests/graph_dirty_edges_m3.pxproj"
	assert_eq(project_service.save_project(path), OK)
	assert_eq(project_service.open_project(path), OK)

	var loaded_graph: Dictionary = project_service.current_project.graphs["graph_dirty_edges"]
	assert_eq(
		loaded_graph["edges"],
		[
			{"from": ["objects", ""], "to": ["generate", "items"]},
			{"from": ["objects", "items"], "to": ["generate", "items"]},
		]
	)


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


func test_recovery_opens_unsaved_copy_and_never_targets_original_project() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	project_service.new_project("Recovery Safety")
	project_service.set_canvas_data({"camera": {"center": [1, 2], "zoom": 1.0}, "items": []})
	var original_path := "user://tests/recovery_original.pxproj"
	assert_eq(project_service.save_project(original_path), OK)
	var original_bytes := FileAccess.get_file_as_bytes(original_path)

	project_service.set_canvas_data({"camera": {"center": [99, 42], "zoom": 2.0}, "items": []})
	assert_eq(project_service.autosave_now(), OK)
	var autosaves: Array = project_service.list_autosaves(project_service.current_project.get_id())
	assert_false(autosaves.is_empty())
	var recovery_path := String(autosaves.back())

	assert_eq(project_service.recover_project(recovery_path), OK)
	assert_eq(project_service.current_project.project_path, "")
	assert_eq(project_service.current_project.recovered_from_path, recovery_path)
	assert_true(project_service.current_project.dirty)
	assert_eq(project_service.save_project(), ERR_FILE_BAD_PATH)

	var recovered_path := "user://tests/recovery_copy.pxproj"
	assert_eq(project_service.save_project(recovered_path), OK)
	assert_eq(project_service.current_project.project_path, recovered_path)
	assert_eq(project_service.current_project.recovered_from_path, "")
	assert_eq(FileAccess.get_file_as_bytes(original_path), original_bytes)


func test_cleanup_provenance_survives_project_roundtrip() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.CYAN)
	var asset_id: String = (
		asset_library
		. register_image(
			image,
			"cleaned",
			{
				"origin": "edited",
				"provenance":
				{
					"provider": null,
					"model": null,
					"prompt": "",
					"seed": null,
					"parent_asset": "source-asset",
					"graph_id": null,
					"created_at": "2026-06-13T00:00:00Z",
					"cleanup":
					{
						"source_asset": "source-asset",
						"params": {"steps": ["detect_grid", "resample", "quantize"]},
						"report": {"output_size": [4, 4]},
					},
				},
			}
		)
	)

	var path := "user://tests/cleanup_provenance.pxproj"
	assert_eq(project_service.save_project(path), OK)
	assert_eq(project_service.open_project(path), OK)

	var meta: Dictionary = asset_library.get_asset_meta(asset_id)
	var provenance: Dictionary = meta["provenance"]
	var cleanup: Dictionary = provenance["cleanup"]
	assert_eq(cleanup["source_asset"], "source-asset")
	assert_eq(
		Vector2(cleanup["report"]["output_size"][0], cleanup["report"]["output_size"][1]),
		Vector2(4, 4)
	)


func test_custom_palette_survives_project_roundtrip() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var palette := PFPalette.new(
		"harvest", "Harvest", PackedColorArray([Color8(32, 24, 16), Color8(224, 192, 96)])
	)
	var registered := PaletteRegistry.register_custom_palette(palette)
	var path := "user://tests/custom_palette_roundtrip.pxproj"

	assert_eq(project_service.save_project(path), OK)

	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	assert_true(unpacked["ok"])
	assert_true(unpacked["files"].has("palettes/%s.json" % registered.id))
	var manifest: Dictionary = FileIOScript.bytes_to_json(unpacked["files"]["manifest.json"])
	assert_eq(String(manifest["custom_palettes"][0]["id"]), registered.id)

	PaletteRegistry.clear_custom_palettes()
	assert_eq(project_service.open_project(path), OK)

	var resolved := PaletteRegistry.resolve({"palette_id": registered.id})
	assert_not_null(resolved)
	assert_eq(resolved.name, "Harvest")
	assert_eq(resolved.colors[1].to_html(false), "e0c060")


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


func _int_pair(value: Array) -> Array:
	return [int(value[0]), int(value[1])]
