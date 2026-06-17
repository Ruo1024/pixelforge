extends "res://addons/gut/test.gd"

const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")

const PORT_TYPES := ["style", "text", "text_list", "spec", "image", "image_list", "asset_list"]


class PortNode:
	extends PFNode

	var node_type := "test_port"
	var input_type := ""
	var output_type := ""

	func _init(type_name: String, input_port_type: String, output_port_type: String) -> void:
		node_type = type_name
		input_type = input_port_type
		output_type = output_port_type

	func get_type() -> String:
		return node_type

	func get_input_ports() -> Array[Dictionary]:
		if input_type.is_empty():
			return []
		return [{"name": "in", "type": input_type, "required": false}]

	func get_output_ports() -> Array[Dictionary]:
		if output_type.is_empty():
			return []
		return [{"name": "out", "type": output_type}]


func test_node_registry_registers_batch_and_rejects_duplicate_type() -> void:
	var registry := NodeRegistryScript.new()

	assert_true(registry.has_type("batch"))
	assert_false(registry.register("batch", BatchNodeScript))
	assert_eq(registry.get_registered_types(), ["ai_generate", "batch", "object_list", "size_spec"])


func test_connection_matrix_follows_graph_schema_port_rules() -> void:
	for source_type in PORT_TYPES:
		for target_type in PORT_TYPES:
			var graph := GraphScript.new()
			graph.add_node(PortNode.new("source_%s" % source_type, "", source_type), "from")
			graph.add_node(PortNode.new("target_%s" % target_type, target_type, ""), "to")

			var result: Dictionary = graph.can_connect("from", "out", "to", "in")
			var expected_ok: bool = (
				source_type == target_type
				or (source_type == "image" and target_type == "image_list")
			)
			assert_eq(
				bool(result["ok"]),
				expected_ok,
				"%s -> %s connection result" % [source_type, target_type]
			)
			assert_eq(
				bool(result["auto_wrap"]),
				source_type == "image" and target_type == "image_list",
				"%s -> %s auto_wrap flag" % [source_type, target_type]
			)


func test_cycle_detection_blocks_back_edges() -> void:
	var graph := GraphScript.new()
	graph.add_node(PortNode.new("a", "image", "image"), "a")
	graph.add_node(PortNode.new("b", "image", "image"), "b")

	assert_true(bool(graph.add_edge("a", "out", "b", "in")["ok"]))
	assert_false(bool(graph.can_connect("b", "out", "a", "in")["ok"]))


func test_batch_node_asset_ids_roundtrip_through_graph_json() -> void:
	var graph := GraphScript.new()
	var node_id := graph.add_node(
		BatchNodeScript.new(),
		"batch_1",
		{"asset_ids": ["asset-a", "asset-b"], "label": "Candidates"},
		Vector2(128, -32)
	)

	assert_eq(node_id, "batch_1")
	assert_true(graph.get_node("batch_1").is_canvas_resident())

	var parsed: PFGraph = GraphScript.from_json(graph.to_json(), NodeRegistryScript.new())
	assert_eq(parsed.get_node_params("batch_1")["asset_ids"], ["asset-a", "asset-b"])
	assert_eq(parsed.get_node_params("batch_1")["label"], "Candidates")
	assert_eq(parsed.to_json(), graph.to_json())


func test_unknown_node_becomes_ghost_and_keeps_raw_fields() -> void:
	var source_graph := {
		"graph_version": 1,
		"id": "graph_main",
		"name": "Ghost Test",
		"nodes":
		[
			{
				"id": "plugin_1",
				"type": "missing.plugin_node",
				"position": [4, 8],
				"params": {"seed": 42},
				"plugin_payload": {"kept": true},
			},
		],
		"edges": [],
	}

	var graph: PFGraph = GraphScript.from_json(source_graph, NodeRegistryScript.new())
	assert_true(graph.get_node("plugin_1").is_ghost())
	assert_eq(graph.to_json()["nodes"][0]["plugin_payload"], {"kept": true})
	assert_eq(graph.to_json(), source_graph)
