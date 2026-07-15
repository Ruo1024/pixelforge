extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


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
	assert_eq(int(manifest["format_version"]), 2)
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
		"graph_version": 2,
		"id": "graph_main",
		"name": "M3 Foundation",
		"nodes":
		[
			{
				"id": "batch_1",
				"type": "batch",
				"params":
				{
					"label": "Candidates",
					"source_node_id": "",
					"source_run_id": "",
					"role": "standalone",
					"input_snapshots": {},
					"request_records": [],
					"result_slots": [],
				},
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
	assert_false(loaded_node.has("position"))
	assert_eq(loaded_node["params"], expected_node["params"])
	assert_eq(loaded_graph["edges"], graph_data["edges"])
	assert_eq(project_service.current_project.canvas["items"][0]["type"], "node")
	assert_eq(project_service.current_project.canvas["items"][0]["node_id"], "batch_1")


func test_stage_frames_and_membership_survive_roundtrip_with_unknown_fields() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var graph_data := {
		"graph_version": 2,
		"id": "graph_main",
		"name": "Two branches",
		"nodes":
		[
			{"id": "prompt_a", "type": "object_list", "params": {"rows": []}},
			{
				"id": "batch_a",
				"type": "batch",
				"params":
				{
					"label": "",
					"source_node_id": "",
					"source_run_id": "",
					"role": "standalone",
					"input_snapshots": {},
					"request_records": [],
					"result_slots": [],
				},
			},
		],
		"edges": [],
	}
	var canvas_data := {
		"camera": {"center": [80, 40], "zoom": 0.5},
		"items":
		[
			{
				"id": "frame_inputs",
				"type": "frame",
				"graph_id": "graph_main",
				"title": "Inputs",
				"color": "486f8fff",
				"position": [-32, -48],
				"size": [640, 360],
				"z_index": -1,
				"future_frame_field": {"keep": true},
			},
			{
				"id": "prompt_item",
				"type": "node",
				"graph_id": "graph_main",
				"node_id": "prompt_a",
				"position": [0, 0],
				"z_index": 1,
				"collapsed": false,
				"frame_id": "frame_inputs",
				"future_node_field": "preserve-me",
			},
			{
				"id": "batch_item",
				"type": "node",
				"graph_id": "graph_main",
				"node_id": "batch_a",
				"position": [320, 0],
				"z_index": 2,
				"collapsed": false,
				"frame_id": "frame_inputs",
				"future_batch_field": "preserve-batch",
			},
		],
	}
	project_service.set_graph_data("graph_main", graph_data)
	project_service.set_canvas_data(canvas_data)
	var path := "user://tests/frame_roundtrip_beta_0_3.pxproj"

	assert_eq(project_service.save_project(path), OK)
	assert_eq(project_service.open_project(path), OK, str(project_service.last_load_error))

	var items: Array = project_service.current_project.canvas["items"]
	assert_eq(items[0]["title"], "Inputs")
	assert_eq(items[0]["size"], [640, 360])
	assert_eq(items[0]["future_frame_field"], {"keep": true})
	assert_eq(items[1]["frame_id"], "frame_inputs")
	assert_false(items[1].has("future_node_field"))
	assert_eq(items[2]["frame_id"], "frame_inputs")
	assert_false(items[2].has("future_batch_field"))
	assert_true(project_service.get_validation_warnings().is_empty())

	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(960, 640)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	canvas.load_canvas_data(project_service.current_project.canvas)
	var runtime_items: Array = canvas.export_canvas_data()["items"]
	assert_eq(_item_by_id(runtime_items, "frame_inputs")["future_frame_field"], {"keep": true})
	assert_false(_item_by_id(runtime_items, "prompt_item").has("future_node_field"))
	assert_false(_item_by_id(runtime_items, "batch_item").has("future_batch_field"))
	assert_eq(_item_by_id(runtime_items, "batch_item")["frame_id"], "frame_inputs")


func test_old_canvas_defaults_to_ungrouped_and_invalid_frame_ids_warn_without_rewrite() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	(
		project_service
		. set_graphs_data(
			{
				"graph_main":
				{
					"graph_version": 2,
					"id": "graph_main",
					"name": "Frame warnings",
					"nodes":
					[
						{"id": "old", "type": "object_list", "params": {"rows": []}},
						{"id": "missing", "type": "object_list", "params": {"rows": []}},
						{"id": "wrong", "type": "object_list", "params": {"rows": []}},
					],
					"edges": [],
				}
			}
		)
	)
	(
		project_service
		. set_canvas_data(
			{
				"camera": {"center": [0, 0], "zoom": 1.0},
				"items":
				[
					{
						"id": "other_graph_frame",
						"type": "frame",
						"graph_id": "graph_other",
						"title": "Other",
						"color": "335577ff",
						"position": [0, 0],
						"size": [200, 100],
						"z_index": -1,
					},
					{
						"id": "old_item",
						"type": "node",
						"graph_id": "graph_main",
						"node_id": "old",
						"position": [0, 0],
						"z_index": 0,
					},
					{
						"id": "missing_item",
						"type": "node",
						"graph_id": "graph_main",
						"node_id": "missing",
						"position": [1, 0],
						"z_index": 1,
						"frame_id": "does_not_exist",
					},
					{
						"id": "wrong_item",
						"type": "node",
						"graph_id": "graph_main",
						"node_id": "wrong",
						"position": [2, 0],
						"z_index": 2,
						"frame_id": "other_graph_frame",
					},
				],
			}
		)
	)
	var path := "user://tests/frame_compat_beta_0_3.pxproj"
	assert_eq(project_service.save_project(path), OK)
	assert_eq(project_service.open_project(path), OK, str(project_service.last_load_error))

	var items: Array = project_service.current_project.canvas["items"]
	assert_false(Dictionary(items[1]).has("frame_id"))
	assert_eq(items[2]["frame_id"], "does_not_exist")
	assert_eq(items[3]["frame_id"], "other_graph_frame")
	var warning_codes := []
	for warning in project_service.get_validation_warnings():
		warning_codes.append(String(warning.get("code", "")))
	assert_has(warning_codes, "frame_reference_not_found")
	assert_has(warning_codes, "frame_graph_mismatch")


func test_simplified_chinese_project_path_name_and_prompt_roundtrip() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	project_service.new_project("像素农场")
	(
		project_service
		. set_graph_data(
			"graph_main",
			{
				"graph_version": 2,
				"id": "graph_main",
				"name": "农场道具生成",
				"nodes":
				[
					{
						"id": "objects",
						"type": "object_list",
						"params":
						{
							"rows":
							[
								{"id": "barrel", "text": "木桶", "count": 1, "enabled": true},
								{"id": "fence", "text": "栅栏", "count": 1, "enabled": true},
								{"id": "scarecrow", "text": "稻草人", "count": 1, "enabled": true},
							]
						},
					}
				],
				"edges": [],
			},
			true
		)
	)
	var directory := "user://tests/中文项目目录"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("像素农场.pxproj")

	assert_eq(project_service.save_project(path), OK)
	assert_true(FileAccess.file_exists(path))
	assert_eq(project_service.open_project(path), OK, str(project_service.last_load_error))
	assert_eq(project_service.current_project.manifest["name"], "像素农场")
	var graph: Dictionary = project_service.current_project.graphs["graph_main"]
	assert_eq(graph["name"], "农场道具生成")
	assert_eq(graph["nodes"][0]["params"]["rows"].size(), 3)


func test_board_and_animation_documents_survive_zip_roundtrip() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var board_data := {
		"id": "board_farm",
		"name": "Farm",
		"grid": {"tile_size": 16, "cols": 60, "rows": 40},
		"layers":
		[
			{
				"id": "terrain",
				"name": "Terrain",
				"kind": "tile",
				"visible": true,
				"opacity": 1.0,
				"blend": "normal",
				"cells": {"12,7": {"asset_id": "tile-a", "variant": 3}},
			}
		],
	}
	var anim_data := {
		"id": "anim_fire",
		"name": "Fire",
		"frames": ["frame-a", "frame-b"],
		"durations_ms": [100, 120],
		"loop": true,
	}
	project_service.set_document_data("boards", "board_farm", board_data)
	project_service.set_document_data("animations", "anim_fire", anim_data)
	var path := "user://tests/board_anim_roundtrip_m5.pxproj"
	assert_eq(project_service.save_project(path), OK)
	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	assert_true(unpacked["files"].has("boards/board_farm.json"))
	assert_true(unpacked["files"].has("anim/anim_fire.anim.json"))
	assert_eq(project_service.open_project(path), OK)
	var loaded_board: Dictionary = project_service.get_document_data("boards", "board_farm")
	var loaded_anim: Dictionary = project_service.get_document_data("animations", "anim_fire")
	assert_eq(String(loaded_board["id"]), "board_farm")
	assert_eq(int(loaded_board["grid"]["cols"]), 60)
	assert_eq(int(loaded_board["layers"][0]["cells"]["12,7"]["variant"]), 3)
	assert_eq(String(loaded_anim["id"]), "anim_fire")
	assert_eq(Array(loaded_anim["frames"]), ["frame-a", "frame-b"])
	assert_eq(
		[int(loaded_anim["durations_ms"][0]), int(loaded_anim["durations_ms"][1])], [100, 120]
	)


func test_project_open_rejects_malformed_graph_edge_schema_without_partial_open() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var graph_data := {
		"graph_version": 2,
		"id": "graph_dirty_edges",
		"name": "Dirty Edges",
		"nodes":
		[
			{"id": "objects", "type": "object_list", "params": {"rows": []}},
			{
				"id": "generate",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "openai_image",
					"model_id": "gpt-image-2",
					"resolution_preset": "1080p",
					"orientation": "square",
					"batch_size": 1,
					"seed": -1,
					"extra": {}
				}
			},
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
	var original_id: String = project_service.current_project.get_id()
	assert_eq(project_service.open_project(path), ERR_FILE_UNRECOGNIZED)
	assert_eq(project_service.last_load_error.get("code", ""), "invalid_graph_edge")
	assert_eq(project_service.current_project.get_id(), original_id)


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
						"input_source_kind": "image_input",
						"input_source_node_id": "image-source",
						"source_batch_node_id": "",
						"source_slot_id": "",
						"cleanup_node_id": "cleanup",
						"run_id": "cleanup-run",
						"request_id": "cleanup-request",
						"preset_id": "",
						"effective_target_size": [4, 4],
						"settings": {"steps": ["detect_grid", "resample", "quantize"]},
						"palette_snapshot": {},
						"report":
						{
							"input_size": [4, 4],
							"output_size": [4, 4],
							"effective_target_size": [4, 4],
							"detected_grid": null,
							"steps": ["detect_grid", "resample", "quantize"],
							"input_color_count": 1,
							"output_color_count": 1,
							"elapsed_ms": 1,
						},
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


func test_broken_sprite_asset_opens_and_resaves_without_losing_bytes_or_item() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var source_path := "user://tests/broken_asset_source.pxproj"
	var saved_path := "user://tests/broken_asset_saved.pxproj"
	var asset_id := "broken-reference"
	var broken_bytes := PackedByteArray([1, 2, 3, 4, 5])
	var manifest := {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION,
		"app_version": AppInfo.APP_VERSION,
		"id": "broken-project",
		"name": "Broken Asset",
		"entries":
		{"canvases": ["canvas"], "graphs": [], "boards": [], "animations": [], "asset_count": 1},
	}
	var canvas_data := {
		"camera": {"center": [0, 0], "zoom": 1.0},
		"items": [_make_item("broken-sprite", asset_id, Vector2.ZERO, 0)],
	}
	var meta := {"id": asset_id, "name": "broken", "origin": "imported", "provenance": {}}
	assert_eq(
		(
			FileIOScript
			. zip_pack(
				{
					"manifest.json": manifest,
					"canvas/canvas.json": canvas_data,
					"assets/%s.meta.json" % asset_id: meta,
					"assets/%s.png" % asset_id: broken_bytes,
				},
				source_path
			)
		),
		OK
	)
	assert_eq(project_service.open_project(source_path), OK)
	assert_eq(project_service.get_validation_warnings()[0]["code"], "asset_decode_failed")
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	canvas.load_canvas_data(project_service.current_project.canvas)
	assert_eq(canvas.get_item_count(), 0)
	assert_eq(canvas.export_canvas_data()["items"][0]["asset_id"], asset_id)
	project_service.set_canvas_data(canvas.export_canvas_data(), true)
	assert_eq(project_service.save_project(saved_path), OK)
	var unpacked: Dictionary = FileIOScript.zip_unpack(saved_path)
	assert_eq(unpacked["files"]["assets/%s.png" % asset_id], broken_bytes)
	var saved_canvas: Dictionary = FileIOScript.bytes_to_json(
		unpacked["files"]["canvas/canvas.json"]
	)
	assert_eq(saved_canvas["items"][0]["asset_id"], asset_id)


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


func _item_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if item is Dictionary and String(item.get("id", "")) == item_id:
			return item
	return {}
