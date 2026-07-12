extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")


func before_each() -> void:
	ProjectService.new_project("Asset reference contract")


func test_live_references_block_delete_but_history_only_allows_it() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var source_id: String = AssetLibrary.register_image(image, "source")
	ProjectService.current_project.canvas["items"] = [
		{"id": "sprite", "type": "sprite", "asset_id": source_id, "position": [0, 0]}
	]
	assert_eq(AssetLibrary.remove_asset(source_id), ERR_BUSY)

	ProjectService.current_project.canvas["items"] = []
	AssetLibrary.register_image(
		image,
		"derived",
		{"provenance": {"parent_asset": source_id, "reference_content_sha256": "hash"}}
	)
	assert_eq(AssetLibrary.remove_asset(source_id), OK)
	var locations := ProjectService.get_asset_reference_locations(source_id)
	assert_eq(locations.size(), 1)
	assert_eq(locations[0]["strength"], "history")


func test_graph_batch_board_animation_and_transition_batch_are_live() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var ids := []
	for index in range(5):
		ids.append(AssetLibrary.register_image(image, "asset_%d" % index))
	ProjectService.current_project.canvas["items"] = [
		{"id": "legacy", "type": "batch_card", "asset_ids": [ids[0]], "position": [0, 0]}
	]
	ProjectService.current_project.graphs["graph"] = {
		"graph_version": 1,
		"id": "graph",
		"nodes":
		[
			{"id": "reference", "type": "image_input", "params": {"asset_id": ids[1]}},
			{"id": "batch", "type": "batch", "params": {"asset_ids": [ids[2]]}},
		],
		"edges": [],
	}
	ProjectService.current_project.boards["board"] = {
		"layers": [{"id": "layer", "cells": {"0,0": {"asset_id": ids[3]}}}]
	}
	ProjectService.current_project.animations["anim"] = {"frames": [ids[4]]}
	for asset_id in ids:
		assert_eq(AssetLibrary.remove_asset(String(asset_id)), ERR_BUSY)


func test_reference_set_is_live_and_plural_provenance_is_history_in_order() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var first_id: String = AssetLibrary.register_image(image, "first")
	var second_id: String = AssetLibrary.register_image(image, "second")
	ProjectService.current_project.graphs["graph"] = {
		"graph_version": 1,
		"id": "graph",
		"nodes":
		[
			{
				"id": "references",
				"type": "reference_set",
				"params": {"asset_ids": [second_id, first_id]},
			}
		],
		"edges": [],
	}
	AssetLibrary.register_image(
		image, "derived", {"provenance": {"reference_asset_ids": [first_id, second_id]}}
	)

	var first_locations := ProjectService.get_asset_reference_locations(first_id)
	var second_locations := ProjectService.get_asset_reference_locations(second_id)

	assert_eq(first_locations.size(), 2)
	assert_eq(first_locations[0]["strength"], "live")
	assert_eq(first_locations[0]["path"], "graphs/graph/nodes/references/params/asset_ids/1")
	assert_eq(first_locations[1]["strength"], "history")
	assert_true(String(first_locations[1]["path"]).ends_with("/reference_asset_ids/0"))
	assert_eq(second_locations.size(), 2)
	assert_eq(second_locations[0]["path"], "graphs/graph/nodes/references/params/asset_ids/0")
	assert_true(String(second_locations[1]["path"]).ends_with("/reference_asset_ids/1"))
	assert_eq(AssetLibrary.remove_asset(first_id), ERR_BUSY)
	assert_eq(AssetLibrary.remove_asset(second_id), ERR_BUSY)

	ProjectService.current_project.graphs.clear()
	assert_eq(AssetLibrary.remove_asset(first_id), OK)
	assert_eq(AssetLibrary.remove_asset(second_id), OK)


func test_bad_and_missing_png_remain_exportable_with_health_status() -> void:
	var broken_meta := {"id": "broken", "name": "broken", "provenance": {}}
	var missing_meta := {"id": "missing", "name": "missing", "provenance": {}}
	var broken_bytes := PackedByteArray([1, 2, 3, 4])
	assert_eq(
		(
			AssetLibrary
			. load_from_zip_files(
				{
					"assets/broken.meta.json": FileIOScript.json_to_bytes(broken_meta),
					"assets/broken.png": broken_bytes,
					"assets/missing.meta.json": FileIOScript.json_to_bytes(missing_meta),
				}
			)
		),
		OK
	)
	assert_true(AssetLibrary.has_asset("broken"))
	assert_null(AssetLibrary.get_image("broken"))
	assert_eq(AssetLibrary.get_bitmap_status("broken"), "decode_failed")
	assert_eq(AssetLibrary.get_bitmap_status("missing"), "missing")
	var entries: Dictionary = AssetLibrary.export_zip_entries()
	assert_eq(entries["assets/broken.png"], broken_bytes)
	assert_false(entries.has("assets/missing.png"))


func test_validation_warnings_are_structured_and_defensive_copies() -> void:
	ProjectService.current_project.canvas["items"] = [
		{"id": "sprite", "type": "sprite", "asset_id": "absent", "position": [0, 0]}
	]
	var path := "user://tests/reference_warning.pxproj"
	assert_eq(ProjectService.save_project(path), OK)
	var warnings := ProjectService.get_validation_warnings()
	assert_eq(warnings.size(), 1)
	assert_eq(warnings[0]["code"], "asset_reference_not_found")
	assert_eq(warnings[0]["strength"], "live")
	warnings[0]["code"] = "mutated"
	assert_eq(ProjectService.get_validation_warnings()[0]["code"], "asset_reference_not_found")
