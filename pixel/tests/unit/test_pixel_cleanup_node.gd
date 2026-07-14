extends "res://addons/gut/test.gd"

const BUILDER_PATH := "res://services/cleanup_run_plan_builder.gd"
const GraphScript := preload("res://core/graph/pf_graph.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ImageNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const ReferenceNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")
const GenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")


class AssetSource:
	extends RefCounted

	var metas := {}

	func has_asset(asset_id: String) -> bool:
		return metas.has(asset_id)

	func get_asset_meta(asset_id: String) -> Dictionary:
		return Dictionary(metas.get(asset_id, {})).duplicate(true)

	func get_bitmap_status(asset_id: String) -> String:
		return "ready" if metas.has(asset_id) else "not_found"


func test_manual_policy_and_valid_sources() -> void:
	assert_eq(CleanupNodeScript.new().get_execution_policy(), "manual")
	var builder: Variant = _builder()
	if builder == null:
		return
	for source_type in ["batch", "image_input", "reference_set"]:
		var fixture := _fixture(source_type)
		var plan: Dictionary = builder.build(fixture.graph, "cleanup", fixture.assets)
		assert_true(plan.get("ok", false), source_type)
	var generated := _fixture("ai_generate")
	var rejected: Dictionary = builder.build(generated.graph, "cleanup", generated.assets)
	assert_false(rejected.get("ok", false))
	assert_eq(rejected.get("code"), "cleanup_requires_output_source")
	assert_null(generated.graph.get_node("output"), "validation must happen before Output creation")


func test_source_projection_and_effective_target_are_frozen_per_asset() -> void:
	var builder: Variant = _builder()
	if builder == null:
		return
	var fixture := _fixture("batch")
	var plan: Dictionary = builder.build(fixture.graph, "cleanup", fixture.assets)
	assert_true(plan.get("ok", false))
	assert_eq(plan["slots"].size(), 2)
	assert_eq(plan["slots"][0]["source_asset_id"], "generated")
	assert_eq(plan["slots"][0]["input_snapshot"]["source_batch_id"], "source")
	assert_eq(plan["slots"][0]["input_snapshot"]["source_slot_id"], "source-slot-a")
	assert_eq(plan["slots"][0]["input_snapshot"]["effective_target_size"], [32, 24])
	assert_eq(plan["slots"][1]["input_snapshot"]["effective_target_size"], [16, 12])
	assert_eq(plan["slots"][0]["planned_size"], [32, 24])
	var direct := _fixture("image_input")
	var direct_plan: Dictionary = builder.build(direct.graph, "cleanup", direct.assets)
	assert_eq(direct_plan["slots"][0]["input_snapshot"]["source_batch_id"], "")
	assert_eq(direct_plan["slots"][0]["input_snapshot"]["source_slot_id"], "")
	assert_eq(direct_plan["slots"][0]["input_snapshot"]["effective_target_size"], [0, 0])


func test_zero_and_thousand_rejected_before_output() -> void:
	var builder: Variant = _builder()
	if builder == null:
		return
	for count in [0, 1000]:
		var fixture := _fixture("reference_set", count)
		var result: Dictionary = builder.build(fixture.graph, "cleanup", fixture.assets)
		assert_false(result.get("ok", false))
		assert_eq(result.get("code"), "missing_cleanup_input" if count == 0 else "cleanup_input_limit_exceeded")
		assert_null(fixture.graph.get_node("output"))


func _builder() -> Variant:
	assert_true(ResourceLoader.exists(BUILDER_PATH), "B7-6 must add the cleanup plan builder")
	return load(BUILDER_PATH) if ResourceLoader.exists(BUILDER_PATH) else null


func _fixture(source_type: String, count: int = 1) -> Dictionary:
	var graph: PFGraph = GraphScript.new()
	graph.id = "cleanup-graph"
	graph.add_node(CleanupNodeScript.new(), "cleanup", {})
	var assets := AssetSource.new()
	var ids := []
	for index in range(count):
		var asset_id := "asset-%d" % index
		ids.append(asset_id)
		assets.metas[asset_id] = {"size": [8, 8], "provenance": {}}
	if source_type == "image_input":
		ids = ["plain"]
		assets.metas["plain"] = {"size": [8, 8], "provenance": {}}
		graph.add_node(ImageNodeScript.new(), "source", {"asset_id": "plain"})
	elif source_type == "reference_set":
		graph.add_node(ReferenceNodeScript.new(), "source", {"asset_ids": ids})
	elif source_type == "ai_generate":
		graph.add_node(GenerateNodeScript.new(), "source", {})
	else:
		assets.metas["generated"] = {
			"size": [1024, 1024],
			"provenance": {"generation_snapshot": {"target_width": 32, "target_height": 24}},
		}
		assets.metas["cleaned"] = {
			"size": [24, 20],
			"provenance": {"cleanup": {"effective_target_size": [16, 12]}},
		}
		var params := _empty_output()
		params["result_slots"] = [
			_slot("source-slot-a", "generated"),
			_slot("source-slot-b", "cleaned"),
			_slot("source-slot-detached", "plain", true),
		]
		graph.add_node(BatchNodeScript.new(), "source", params)
	assert_true(graph.add_edge("source", "assets", "cleanup", "assets")["ok"])
	return {"graph": graph, "assets": assets}


func _slot(slot_id: String, asset_id: String, detached: bool = false) -> Dictionary:
	return {
		"slot_id": slot_id,
		"run_id": "",
		"request_id": "",
		"source_row_id": "",
		"source_asset_id": "",
		"input_snapshot_id": "",
		"planned_size": [8, 8],
		"status": "succeeded",
		"detached": detached,
		"unexpected": false,
		"error": null,
		"asset_id": asset_id,
	}


func _empty_output() -> Dictionary:
	return {
		"label": "Source",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}
