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
	assert_eq(
		registry.get_registered_types(),
		["ai_generate", "batch", "comfyui.run_workflow", "image_input", "object_list", "size_spec"]
	)


func test_image_input_asset_ref_and_unknown_params_roundtrip() -> void:
	var graph := (
		GraphScript
		. from_json(
			{
				"graph_version": 1,
				"id": "reference_graph",
				"nodes":
				[
					{
						"id": "reference",
						"type": "image_input",
						"position": [0, 0],
						"params": {"asset_id": 1234, "file_path": "/legacy/path.png"},
					}
				],
				"edges": [],
			}
		)
	)
	assert_false(graph.get_node("reference").is_ghost())
	assert_eq(graph.get_node_params("reference")["asset_id"], "1234")
	assert_eq(graph.to_json()["nodes"][0]["params"]["file_path"], "/legacy/path.png")
	assert_eq(graph.get_node("reference").get_param_schema()[0]["kind"], PFNode.KIND_ASSET_REF)


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


func test_input_port_allows_only_one_source_edge() -> void:
	var graph := GraphScript.new()
	graph.add_node(PortNode.new("source_a", "", "image"), "source_a")
	graph.add_node(PortNode.new("source_b", "", "image"), "source_b")
	graph.add_node(PortNode.new("target", "image", ""), "target")

	assert_true(bool(graph.add_edge("source_a", "out", "target", "in")["ok"]))

	var result := graph.can_connect("source_b", "out", "target", "in")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Input port already has a connection")
	assert_eq(graph.edges, [{"from": ["source_a", "out"], "to": ["target", "in"]}])


func test_duplicate_edge_reports_duplicate_connection_reason() -> void:
	var graph := GraphScript.new()
	graph.add_node(PortNode.new("source", "", "image"), "source")
	graph.add_node(PortNode.new("target", "image", ""), "target")

	assert_true(bool(graph.add_edge("source", "out", "target", "in")["ok"]))

	var result := graph.add_edge("source", "out", "target", "in")
	assert_false(bool(result["ok"]))
	assert_eq(String(result["reason"]), "Connection already exists")
	assert_eq(graph.edges, [{"from": ["source", "out"], "to": ["target", "in"]}])


func test_output_port_can_fan_out_to_multiple_inputs() -> void:
	var graph := GraphScript.new()
	graph.add_node(PortNode.new("source", "", "image"), "source")
	graph.add_node(PortNode.new("target_a", "image", ""), "target_a")
	graph.add_node(PortNode.new("target_b", "image", ""), "target_b")

	assert_true(bool(graph.add_edge("source", "out", "target_a", "in")["ok"]))
	assert_true(bool(graph.add_edge("source", "out", "target_b", "in")["ok"]))
	assert_eq(graph.edges.size(), 2)


func test_validate_edges_reports_loaded_invalid_type_without_dropping_edge() -> void:
	var graph := GraphScript.new()
	graph.add_node(PortNode.new("source", "", "text_list"), "source")
	graph.add_node(PortNode.new("target", "image_list", ""), "target")
	var invalid_edge := {"from": ["source", "out"], "to": ["target", "in"]}
	graph.edges.append(invalid_edge)

	var errors := graph.validate_edges()

	assert_eq(errors.size(), 1)
	assert_eq(String(errors[0]["code"]), "invalid_port")
	assert_eq(String(errors[0]["message"]), "Cannot connect text_list to image_list")
	assert_eq(graph.edges, [invalid_edge])


func test_loaded_edge_schema_is_normalized_before_validation() -> void:
	var graph_data := {
		"graph_version": 1,
		"id": "graph_dirty_edge",
		"name": "Dirty Edge",
		"nodes":
		[
			{"id": "source", "type": "object_list", "params": {}, "position": [0, 0]},
			{"id": "target", "type": "ai_generate", "params": {}, "position": [0, 0]},
		],
		"edges":
		[
			{"from": ["source"], "to": ["target", "in", "ignored"]},
			{"from": "not-an-endpoint", "to": []},
		],
	}

	var graph: PFGraph = GraphScript.from_json(graph_data, NodeRegistryScript.new())
	var errors := graph.validate_edges()

	assert_eq(
		graph.edges,
		[
			{"from": ["source", ""], "to": ["target", "in"]},
			{"from": ["", ""], "to": ["", ""]},
		]
	)
	assert_eq(errors.size(), 2)
	assert_eq(String(errors[0]["code"]), "invalid_port")
	assert_eq(String(errors[1]["code"]), "missing_endpoint")


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


func test_known_graph_node_and_edge_unknown_fields_survive_roundtrip() -> void:
	var source_graph := {
		"graph_version": 1,
		"id": "future_graph",
		"name": "Forward Compatible",
		"future_graph_field": {"mode": "keep"},
		"nodes":
		[
			{
				"id": "objects",
				"type": "object_list",
				"position": [0, 0],
				"params": {"items": "barrel"},
				"future_node_field": [1, 2, 3],
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"position": [200, 0],
				"params": {},
			},
		],
		"edges":
		[
			{
				"from": ["objects", "items"],
				"to": ["generate", "items"],
				"future_edge_field": {"label": "keep"},
			}
		],
	}

	var graph: PFGraph = GraphScript.from_json(source_graph, NodeRegistryScript.new())
	var saved: Dictionary = graph.to_json()
	assert_eq(saved["future_graph_field"], {"mode": "keep"})
	assert_eq(saved["nodes"][0]["future_node_field"], [1, 2, 3])
	assert_eq(saved["edges"][0]["future_edge_field"], {"label": "keep"})
