extends "res://addons/gut/test.gd"

const Scanner := preload("res://services/asset_reference_scanner.gd")
const ProjectModel := preload("res://services/pf_project.gd")


class FakeAssetLibrary:
	extends Node

	var metadata := {}

	func has_asset(asset_id: String) -> bool:
		return metadata.has(asset_id)

	func get_bitmap_status(asset_id: String) -> String:
		return "ready" if metadata.has(asset_id) else "missing"

	func get_all_meta() -> Dictionary:
		return metadata.duplicate(true)

	func get_asset_meta(asset_id: String) -> Dictionary:
		return Dictionary(metadata.get(asset_id, {})).duplicate(true)


func test_generation_live_and_history_scanner() -> void:
	var project := ProjectModel.new()
	project.reset("Reference contract v2")
	project.canvas["items"] = [{"id": "sprite", "type": "sprite", "asset_id": "asset-sprite"}]
	project.graphs = {
		"graph-main":
		{
			"graph_version": 2,
			"id": "graph-main",
			"name": "References",
			"nodes":
			[
				{"id": "image", "type": "image_input", "params": {"asset_id": "asset-input"}},
				{
					"id": "refs",
					"type": "reference_set",
					"params": {"asset_ids": ["asset-reference"]},
				},
				{
					"id": "output",
					"type": "batch",
					"params":
					{
						"result_slots":
						[
							{
								"asset_id": "asset-visible",
								"status": "succeeded",
								"detached": false,
							},
							{
								"asset_id": "asset-detached",
								"status": "succeeded",
								"detached": true,
							},
						],
						"input_snapshots":
						{
							"snapshot":
							{
								"kind": "generation",
								"reference_asset_ids": ["asset-snapshot-reference"],
							}
						},
					},
				},
			],
			"edges": [],
		}
	}
	var library := FakeAssetLibrary.new()
	add_child_autofree(library)
	for asset_id in [
		"asset-sprite",
		"asset-input",
		"asset-reference",
		"asset-visible",
		"asset-detached",
		"asset-snapshot-reference",
		"asset-provenance-reference",
		"asset-generated-owner",
	]:
		library.metadata[asset_id] = {"id": asset_id, "provenance": {}}
	library.metadata["asset-generated-owner"]["provenance"] = {
		"generation_snapshot": {"reference_asset_ids": ["asset-provenance-reference"]}
	}

	var result := Scanner.scan(project, library)
	for asset_id in ["asset-sprite", "asset-input", "asset-reference", "asset-visible"]:
		assert_true(result["live_by_asset"].has(asset_id), asset_id)
	for asset_id in ["asset-detached", "asset-snapshot-reference", "asset-provenance-reference"]:
		assert_true(result["history_by_asset"].has(asset_id), asset_id)
	assert_false(result["live_by_asset"].has("asset-detached"))
	assert_eq(result["warnings"], [])


func test_live_and_history_references_keep_asset_bytes_across_roundtrip() -> void:
	ProjectService.new_project("Reference bytes v2")
	AssetLibrary.clear()
	var visible := Image.create(3, 2, false, Image.FORMAT_RGBA8)
	visible.fill(Color.RED)
	var detached := Image.create(2, 3, false, Image.FORMAT_RGBA8)
	detached.fill(Color.BLUE)
	AssetLibrary.register_image(visible, "visible", {"id": "asset-visible", "origin": "generated"})
	AssetLibrary.register_image(
		detached, "detached", {"id": "asset-detached", "origin": "generated"}
	)
	(
		ProjectService
		. set_graph_data(
			"graph-main",
			{
				"graph_version": 2,
				"id": "graph-main",
				"name": "References",
				"nodes":
				[
					{
						"id": "output",
						"type": "batch",
						"params":
						{
							"label": "",
							"source_node_id": "",
							"source_run_id": "",
							"role": "standalone",
							"input_snapshots": {},
							"request_records": [],
							"result_slots":
							[
								_slot("slot-visible", "asset-visible", false, [3, 2]),
								_slot("slot-detached", "asset-detached", true, [2, 3]),
							],
						},
					}
				],
				"edges": [],
			},
			false
		)
	)
	var path := "user://tests/b7_asset_reference_bytes.pxproj"
	assert_eq(ProjectService.save_project(path), OK)
	AssetLibrary.clear()
	assert_eq(ProjectService.open_project(path), OK, JSON.stringify(ProjectService.last_load_error))
	assert_eq(AssetLibrary.get_image("asset-visible").get_size(), Vector2i(3, 2))
	assert_eq(AssetLibrary.get_image("asset-detached").get_size(), Vector2i(2, 3))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _slot(slot_id: String, asset_id: String, detached: bool, size: Array) -> Dictionary:
	return {
		"slot_id": slot_id,
		"run_id": "",
		"request_id": "",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "",
		"planned_size": size,
		"status": "succeeded",
		"detached": detached,
		"unexpected": false,
		"error": null,
		"asset_id": asset_id,
	}
