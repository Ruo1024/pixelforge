extends "res://addons/gut/test.gd"

const GraphScript := preload("res://core/graph/pf_graph.gd")
const Builder := preload("res://services/result_branch_builder.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func test_single_result_becomes_reference_without_touching_source_branch() -> void:
	var graph := _source_graph()
	var before := graph.to_json()
	var result := Builder.build(graph, "as_reference", ["asset-a"], {}, Vector2(800, 40))
	assert_true(result["ok"])
	assert_eq(result["created_node_ids"].size(), 1)
	var node_id := String(result["focus_node_id"])
	assert_eq(graph.get_node(node_id).get_type(), "image_input")
	assert_eq(graph.get_node_params(node_id)["asset_id"], "asset-a")
	assert_eq(
		BatchNodeScript.get_visible_asset_ids(graph.get_node_params("source_batch")), ["asset-a"]
	)
	assert_eq(before["edges"], graph.to_json()["edges"])


func test_multiple_results_build_runnable_independent_continue_branch() -> void:
	var graph := _source_graph()
	var result := (
		Builder
		. build(
			graph,
			"continue_branch",
			["asset-a", "asset-b"],
			{
				"provider_id": "openai_image",
				"model_id": "gpt-image-2",
				"prompt": "small observatory",
				"prompt_preset_id": "prompt-16bit-db32",
				"prompt_prefix": "pixel art",
				"target_width": 1280,
				"target_height": 720,
				"batch_size": 3,
				"requested_seed": 17,
				"extra": {},
			},
			Vector2(800, 40)
		)
	)
	assert_true(result["ok"])
	assert_eq(result["created_node_ids"].size(), 5)
	var type_ids := {}
	for node_id in result["created_node_ids"]:
		type_ids[graph.get_node(String(node_id)).get_type()] = String(node_id)
	assert_eq(graph.get_node_params(type_ids["reference_set"])["asset_ids"], ["asset-a", "asset-b"])
	assert_eq(graph.get_node_params(type_ids["text_prompt"])["text"], "small observatory")
	assert_eq(graph.get_node_params(type_ids["prompt_preset"])["preset"]["prefix"], "pixel art")
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["model_id"], "gpt-image-2")
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["resolution_preset"], "720p")
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["orientation"], "landscape")
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["batch_size"], 1)
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["seed"], -1)
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["extra"], {})
	assert_true(graph.get_node_params(type_ids["batch"])["result_slots"].is_empty())
	assert_eq(graph.validate_edges(), [])
	assert_eq(
		BatchNodeScript.get_visible_asset_ids(graph.get_node_params("source_batch")), ["asset-a"]
	)


func _source_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_result_branch"
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			"source_batch",
			{
				"label": "Source",
				"source_node_id": "source",
				"source_run_id": "run-source",
				"role": "current",
				"input_snapshots": {},
				"request_records": [],
				"result_slots": [{"status": "succeeded", "detached": false, "asset_id": "asset-a"}],
			},
			Vector2.ZERO
		)
	)
	return graph
