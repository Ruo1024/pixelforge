extends "res://addons/gut/test.gd"

const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const MockRunnerScript := preload("res://services/graph_mock_runner.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("M3 Mock Runner")


func test_mock_generate_chain_materializes_images_into_batch_node() -> void:
	var graph := _make_mock_graph()
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var runner := MockRunnerScript.new()

	var result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1")

	assert_true(bool(result["ok"]))
	assert_eq(result["asset_ids"].size(), 10)
	assert_eq(graph.get_node_params("batch_1")["asset_ids"], result["asset_ids"])

	var first_asset_id := String(result["asset_ids"][0])
	assert_true(asset_library.has_asset(first_asset_id))
	assert_eq(asset_library.get_image(first_asset_id).get_size(), Vector2i(12, 10))
	var meta: Dictionary = asset_library.get_asset_meta(first_asset_id)
	assert_eq(meta["origin"], "generated")
	assert_eq(meta["provenance"]["provider"], "mock")
	assert_eq(meta["provenance"]["graph_id"], "graph_main")
	assert_eq(meta["provenance"]["seed"], 700)


func test_mock_generate_chain_can_replace_existing_batch_assets() -> void:
	var graph := _make_mock_graph()
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var runner := MockRunnerScript.new()

	var first_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1")
	assert_true(bool(first_result["ok"]))
	var first_ids: Array = graph.get_node_params("batch_1")["asset_ids"].duplicate()
	assert_eq(first_ids.size(), 10)

	var second_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1", true)
	assert_true(bool(second_result["ok"]))
	var second_ids: Array = graph.get_node_params("batch_1")["asset_ids"]

	assert_eq(second_result["asset_ids"].size(), 10)
	assert_eq(second_ids.size(), 10)
	assert_ne(second_ids, first_ids)


func test_mock_generate_chain_rejects_missing_required_spec_input() -> void:
	var graph := _make_mock_graph()
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var runner := MockRunnerScript.new()
	var existing_ids := ["asset_existing"]
	graph.set_node_params("batch_1", {"label": "Mock Batch", "asset_ids": existing_ids})
	_remove_edge(graph, "size", "spec", "generate", "spec")

	var result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1", true)

	assert_false(bool(result["ok"]))
	assert_eq(result["error"]["code"], "missing_required_input")
	assert_eq(graph.get_node_params("batch_1")["asset_ids"], existing_ids)


func test_mock_generate_chain_rejects_loaded_invalid_edge_before_run() -> void:
	var graph := _make_mock_graph()
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var runner := MockRunnerScript.new()
	var existing_ids := ["asset_existing"]
	graph.set_node_params("batch_1", {"label": "Mock Batch", "asset_ids": existing_ids})
	_remove_edge(graph, "generate", "images", "batch_1", "in")
	graph.edges.append({"from": ["objects", "items"], "to": ["batch_1", "in"]})

	var result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1", true)

	assert_false(bool(result["ok"]))
	assert_eq(result["error"]["code"], "invalid_edge")
	assert_string_contains(
		String(result["error"]["message"]), "Cannot connect text_list to image_list"
	)
	assert_eq(graph.get_node_params("batch_1")["asset_ids"], existing_ids)


func test_mock_generate_chain_survives_project_roundtrip_after_materialization() -> void:
	var project_service := get_tree().root.get_node("ProjectService")
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var graph := _make_mock_graph()
	var runner := MockRunnerScript.new()
	var result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1")

	assert_true(bool(result["ok"]))
	project_service.set_graph_data(graph.id, graph.to_json())
	var path := "user://tests/m3_mock_graph_roundtrip.pxproj"
	assert_eq(project_service.save_project(path), OK)

	assert_eq(project_service.open_project(path), OK)
	var loaded_graph: Dictionary = project_service.current_project.graphs["graph_main"]
	var loaded_batch: Dictionary = loaded_graph["nodes"][3]
	assert_eq(loaded_batch["params"]["asset_ids"].size(), 10)
	assert_true(asset_library.has_asset(String(loaded_batch["params"]["asset_ids"][0])))


func _make_mock_graph() -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_main"
	graph.name = "M3 Mock Generate"
	graph.add_node(
		ObjectListNodeScript.new(),
		"objects",
		{"items": "barrel\nfence\nscarecrow\ncrate\nwell"},
		Vector2(0, 0)
	)
	graph.add_node(
		SizeSpecNodeScript.new(),
		"size",
		{"width": 12, "height": 10, "per_subject": 1},
		Vector2(220, 0)
	)
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 2, "seed": 700},
		Vector2(440, 0)
	)
	graph.add_node(BatchNodeScript.new(), "batch_1", {"label": "Mock Batch"}, Vector2(660, 0))
	assert_true(bool(graph.add_edge("objects", "items", "generate", "items")["ok"]))
	assert_true(bool(graph.add_edge("size", "spec", "generate", "spec")["ok"]))
	assert_true(bool(graph.add_edge("generate", "images", "batch_1", "in")["ok"]))
	return graph


func _remove_edge(
	graph: PFGraph, from_node: String, from_port: String, to_node: String, to_port: String
) -> void:
	var kept: Array[Dictionary] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if (
			String(from_data[0]) == from_node
			and String(from_data[1]) == from_port
			and String(to_data[0]) == to_node
			and String(to_data[1]) == to_port
		):
			continue
		kept.append(edge)
	graph.edges = kept
