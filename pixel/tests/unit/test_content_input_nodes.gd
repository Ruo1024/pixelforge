extends "res://addons/gut/test.gd"

const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")


func test_text_prompt_preserves_multiline_content_and_validates_missing_text() -> void:
	var node := TextPromptNodeScript.new()
	var authored := "barrel beside the barn\nsoft morning light"

	assert_eq(node.execute({}, node.validate_params({"text": authored}), {})["prompt"], authored)
	assert_eq(node.execute({}, node.validate_params({"text": null}), {})["prompt"], "")
	assert_eq(node.get_output_ports(), [{"name": "prompt", "type": "text"}])


func test_object_list_rejects_legacy_items_and_rows_are_execution_truth() -> void:
	var node := ObjectListNodeScript.new()
	var legacy := node.validate_params({"items": "tower\nbarrel\n"})
	assert_eq(legacy, {"rows": []})
	assert_eq(node.rows_for_params(legacy), [])
	var structured := (
		node
		. validate_params(
			{
				"rows":
				[
					{"id": "row-a", "text": "tower", "count": 4, "enabled": true},
					{"id": "row-b", "text": "barrel", "count": 2, "enabled": false},
				],
			}
		)
	)
	assert_eq(
		Array(node.execute({}, structured, {})["subjects"]),
		[{"id": "row-a", "text": "tower", "count": 4}]
	)
	assert_eq(structured["rows"][0]["count"], 4)
	assert_eq(structured["rows"][1]["id"], "row-b")


func test_prompt_preset_outputs_detached_prefix_snapshot() -> void:
	var node := PromptPresetNodeScript.new()
	var params := (
		node
		. validate_params(
			{
				"preset":
				{
					"prompt_preset_version": 1,
					"id": "prompt-custom-farm",
					"name": "Farm",
					"prefix": "16-bit farming game sprite",
				},
			}
		)
	)
	var result: Dictionary = node.execute({}, params, {})

	assert_eq(result["prefix"]["preset_id"], "prompt-custom-farm")
	assert_eq(result["prefix"]["prefix"], "16-bit farming game sprite")
	result["prefix"]["prefix"] = "Changed downstream"
	assert_eq(params["preset"]["name"], "Farm")
	assert_eq(node.validate_params({"preset": "invalid"})["preset"], node.DEFAULT_PRESET)


func test_content_nodes_roundtrip_as_registered_nodes_with_edge_contracts() -> void:
	var source_graph := {
		"graph_version": 2,
		"id": "content_graph",
		"name": "Content Graph",
		"nodes":
		[
			{
				"id": "prompt",
				"type": "text_prompt",
				"params": {"text": "small windmill"},
			},
			{
				"id": "preset",
				"type": "prompt_preset",
				"params":
				{
					"preset":
					{
						"prompt_preset_version": 1,
						"id": "prompt-custom-farm",
						"name": "Farm",
						"prefix": "16-bit farming game sprite",
					},
				},
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"resolution_preset": "1080p",
					"orientation": "square",
					"batch_size": 1,
					"seed": -1,
					"extra": {},
				},
			},
		],
		"edges":
		[
			{"from": ["prompt", "prompt"], "to": ["generate", "prompt"]},
			{"from": ["preset", "prefix"], "to": ["generate", "prefix"]},
		],
	}

	var parsed := GraphScript.parse_v2(source_graph, NodeRegistryScript.new())
	assert_true(parsed["ok"])
	var graph: PFGraph = parsed["graph"]
	assert_false(graph.get_node("prompt").is_ghost())
	assert_false(graph.get_node("preset").is_ghost())
	assert_eq(graph.validate_edges(), [])

	var saved: Dictionary = graph.to_json()
	var reopened: PFGraph = GraphScript.parse_v2(saved, NodeRegistryScript.new())["graph"]
	assert_eq(reopened.to_json(), saved)
	assert_eq(reopened.get_node_params("prompt")["text"], "small windmill")
	assert_eq(reopened.get_node_params("preset")["preset"]["id"], "prompt-custom-farm")
