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
	assert_eq(graph.get_node_params("source_batch"), {"label": "Source", "asset_ids": ["asset-a"]})
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
				"style": {"name": "16-bit"},
				"width": 48,
				"height": 32,
				"batch_size": 3,
				"seed": 17,
			},
			Vector2(800, 40)
		)
	)
	assert_true(result["ok"])
	assert_eq(result["created_node_ids"].size(), 6)
	var type_ids := {}
	for node_id in result["created_node_ids"]:
		type_ids[graph.get_node(String(node_id)).get_type()] = String(node_id)
	assert_eq(graph.get_node_params(type_ids["reference_set"])["asset_ids"], ["asset-a", "asset-b"])
	assert_eq(graph.get_node_params(type_ids["text_prompt"])["text"], "small observatory")
	assert_eq(graph.get_node_params(type_ids["size_spec"])["width"], 48)
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["model_id"], "gpt-image-2")
	assert_eq(graph.get_node_params(type_ids["ai_generate"])["batch_size"], 3)
	assert_true(graph.get_node_params(type_ids["batch"])["asset_ids"].is_empty())
	assert_eq(graph.validate_edges(), [])
	assert_eq(graph.get_node_params("source_batch")["asset_ids"], ["asset-a"])


func _source_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_result_branch"
	graph.add_node(
		BatchNodeScript.new(),
		"source_batch",
		{"label": "Source", "asset_ids": ["asset-a"]},
		Vector2.ZERO
	)
	return graph
