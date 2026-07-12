extends "res://addons/gut/test.gd"

const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const StylePresetNodeScript := preload("res://core/graph/nodes/style_preset_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")


func test_text_prompt_preserves_multiline_content_and_validates_missing_text() -> void:
	var node := TextPromptNodeScript.new()
	var authored := "barrel beside the barn\nsoft morning light"

	assert_eq(node.execute({}, node.validate_params({"text": authored}), {})["text"], authored)
	assert_eq(node.execute({}, node.validate_params({"text": null}), {})["text"], "")
	assert_eq(node.get_output_ports(), [{"name": "text", "type": "text"}])


func test_object_list_preserves_legacy_batch_semantics_and_rows_are_execution_truth() -> void:
	var node := ObjectListNodeScript.new()
	var legacy := node.validate_params({"items": "tower\nbarrel\n"})
	assert_false(legacy.has("rows"))
	var display_rows := node.rows_for_params(legacy)
	assert_eq(display_rows.size(), 2)
	assert_eq(display_rows[0]["text"], "tower")
	assert_true(String(display_rows[0]["id"]).begins_with("legacy_"))
	assert_eq(node.rows_for_params(legacy), display_rows)
	var structured := (
		node
		. validate_params(
			{
				"items": "ignored legacy value",
				"rows":
				[
					{"id": "row-a", "text": "tower", "count": 4, "enabled": true},
					{"id": "row-b", "text": "barrel", "count": 2, "enabled": false},
				],
			}
		)
	)
	assert_eq(Array(node.execute({}, structured, {})["items"]), ["tower"])
	assert_eq(structured["rows"][0]["count"], 4)
	assert_eq(structured["rows"][1]["id"], "row-b")


func test_style_preset_outputs_detached_validated_embedded_data() -> void:
	var node := StylePresetNodeScript.new()
	var params := (
		node
		. validate_params(
			{
				"preset_ref": "embedded",
				"preset":
				{
					"style_version": 1,
					"id": "custom_farm",
					"name": "Farm",
					"base_size": 32,
					"palette": {"ref": "db32", "colors": []},
					"auto_k_strategy": "future_strategy",
				},
			}
		)
	)
	var result: Dictionary = node.execute({}, params, {})

	assert_eq(result["style"]["id"], "custom_farm")
	assert_eq(result["style"]["auto_k_strategy"], "median_cut")
	result["style"]["name"] = "Changed downstream"
	assert_eq(params["preset"]["name"], "Farm")
	assert_eq(node.validate_params({"preset": "invalid"})["preset"], {})


func test_content_nodes_roundtrip_as_registered_nodes_with_edge_contracts() -> void:
	var source_graph := {
		"graph_version": 1,
		"id": "content_graph",
		"name": "Content Graph",
		"nodes":
		[
			{
				"id": "prompt",
				"type": "text_prompt",
				"position": [16, 24],
				"params": {"text": "small windmill", "future_prompt_field": true},
			},
			{
				"id": "style",
				"type": "style_preset",
				"position": [16, 160],
				"params":
				{
					"preset_ref": "embedded",
					"preset":
					{
						"style_version": 1,
						"id": "preset_16bit_db32",
						"name": "16-bit / DB32",
						"auto_k_strategy": "median_cut",
					},
				},
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"position": [320, 80],
				"params": {},
			},
		],
		"edges":
		[
			{"from": ["prompt", "text"], "to": ["generate", "text"]},
			{"from": ["style", "style"], "to": ["generate", "style"]},
		],
	}

	var graph: PFGraph = GraphScript.from_json(source_graph, NodeRegistryScript.new())
	assert_false(graph.get_node("prompt").is_ghost())
	assert_false(graph.get_node("style").is_ghost())
	assert_eq(graph.validate_edges(), [])

	var saved: Dictionary = graph.to_json()
	var reopened: PFGraph = GraphScript.from_json(saved, NodeRegistryScript.new())
	assert_eq(reopened.to_json(), saved)
	assert_eq(reopened.get_node_params("prompt")["future_prompt_field"], true)
	assert_eq(reopened.get_node_params("style")["preset"]["id"], "preset_16bit_db32")
