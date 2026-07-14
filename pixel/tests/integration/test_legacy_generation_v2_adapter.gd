extends "res://addons/gut/test.gd"

const Adapter := preload("res://services/legacy_generation_v2_adapter.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("B7-2 Adapter")


func test_single_terminal_items_become_final_slots_without_legacy_truth() -> void:
	var image := Image.create(12, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color("4ac7c1"))
	var adapter := Adapter.new()
	var result: Dictionary = adapter.materialize_terminal(
		"graph-main",
		"generate-1",
		{"label": "Result", "asset_ids": ["legacy-must-not-survive"]},
		[
			{
				"image": image,
				"metadata": {
					"provider": "mock",
					"model": "pixel_mock_v1",
					"prompt": "tower",
					"seed": 700,
					"cost": 99.5,
					"source_row_id": "row-tower",
					"reference_asset_ids": ["reference-a"],
					"reference_content_sha256s": ["abc123"],
					"generation_snapshot": {
						"width": 12,
						"height": 10,
						"seed": 700,
					},
				},
			},
			{
				"image": null,
				"metadata": {
					"provider": "mock",
					"model": "pixel_mock_v1",
					"prompt": "barrel",
					"source_row_id": "row-barrel",
					"generation_snapshot": {"width": 12, "height": 10},
				},
				"error": {"code": "mock_failed", "message": "unsafe legacy detail"},
			},
		],
		get_tree().root.get_node("AssetLibrary")
	)

	assert_true(result["ok"])
	var params: Dictionary = result["batch_params"]
	assert_false(params.has("asset_ids"))
	assert_eq(params.keys().size(), 7)
	assert_eq(params["label"], "Result")
	assert_eq(params["source_node_id"], "generate-1")
	assert_eq(params["role"], "current")
	assert_eq(params["result_slots"].size(), 2)
	assert_eq(params["request_records"].size(), 1)

	var success: Dictionary = params["result_slots"][0]
	var failure: Dictionary = params["result_slots"][1]
	assert_eq(success["status"], "succeeded")
	assert_true(success.has("asset_id"))
	assert_eq(failure["status"], "failed")
	assert_false(failure.has("asset_id"))
	assert_eq(failure["error"]["code"], "ambiguous_result")
	assert_false(failure["error"].has("message"))
	for slot in params["result_slots"]:
		assert_false(String(slot["status"]) in ["queued", "running", "canceled"])

	var meta: Dictionary = AssetLibrary.get_asset_meta(String(success["asset_id"]))
	var provenance: Dictionary = meta["provenance"]
	assert_eq(provenance.keys().size(), 3)
	assert_eq(provenance["graph_id"], "graph-main")
	var snapshot: Dictionary = provenance["generation_snapshot"]
	assert_eq(snapshot["source_node_id"], "generate-1")
	assert_eq(snapshot["source_row_id"], "row-tower")
	assert_eq(snapshot["reference_asset_ids"], ["reference-a"])
	assert_eq(snapshot["reference_content_sha256s"], ["abc123"])
	assert_eq(snapshot["target_width"], 12)
	assert_eq(snapshot["target_height"], 10)
	assert_eq(snapshot["provider_output_size"], [12, 10])
	assert_eq(snapshot["actual_width"], 12)
	assert_eq(snapshot["actual_height"], 10)
	assert_eq(snapshot["requested_seed"], 700)
	assert_eq(snapshot["actual_seed"], 700)
	assert_false(snapshot.has("cost"))
	var record: Dictionary = params["request_records"][0]
	assert_eq(record["slot_ids"].size(), 2)
	assert_eq(record["requested_count"], 2)
	assert_eq(record["received_count"], 1)
	assert_eq(record["state"], "partial")
	assert_null(record["actual_cost_usd"])
	assert_eq(record["charge_id"], "")


func test_empty_terminal_result_is_rejected_without_mutating_assets() -> void:
	var before: Dictionary = AssetLibrary.get_all_meta()
	var result: Dictionary = Adapter.new().materialize_terminal(
		"graph-main", "generate-1", {}, [], AssetLibrary
	)
	assert_false(result["ok"])
	assert_eq(result["error"], {"code": "empty_terminal_result", "args": {}})
	assert_eq(AssetLibrary.get_all_meta(), before)


func test_mixed_terminal_providers_fail_before_asset_registration() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var before: Dictionary = AssetLibrary.get_all_meta()
	var result: Dictionary = Adapter.new().materialize_terminal(
		"graph-main",
		"generate-1",
		{},
		[
			{"image": image, "metadata": {"provider": "mock-a"}},
			{"image": image, "metadata": {"provider": "mock-b"}},
		],
		AssetLibrary
	)
	assert_false(result["ok"])
	assert_eq(result["error"], {"code": "mixed_terminal_providers", "args": {}})
	assert_eq(AssetLibrary.get_all_meta(), before)
