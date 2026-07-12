extends "res://addons/gut/test.gd"

const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const MockRunnerScript := preload("res://services/graph_mock_runner.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")
const FileIOScript := preload("res://infra/file_io.gd")


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


func test_structured_object_rows_override_batch_size_and_persist_source_provenance() -> void:
	var graph := _make_mock_graph()
	(
		graph
		. set_node_params(
			"objects",
			{
				"items": "tower\nbarrel\nignored",
				"rows":
				[
					{"id": "row-tower", "text": "tower", "count": 2, "enabled": true},
					{"id": "row-barrel", "text": "barrel", "count": 3, "enabled": true},
					{"id": "row-off", "text": "ignored", "count": 9, "enabled": false},
				],
			},
		)
	)
	graph.set_node_params("generate", {"provider_id": "mock", "batch_size": 7, "seed": 900})

	var result: Dictionary = MockRunnerScript.new().run_to_batch(graph, AssetLibrary, "batch_1")

	assert_true(result["ok"])
	assert_eq(result["asset_ids"].size(), 5)
	var source_rows: Array[String] = []
	for asset_id in result["asset_ids"]:
		var provenance: Dictionary = AssetLibrary.get_asset_meta(String(asset_id))["provenance"]
		assert_eq(provenance["source_node_id"], "objects")
		source_rows.append(String(provenance["source_row_id"]))
	assert_eq(source_rows, ["row-tower", "row-tower", "row-barrel", "row-barrel", "row-barrel"])


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


func test_reference_image_changes_mock_output_and_persists_provenance() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var red_id: String = asset_library.register_image(red, "red_reference")
	var blue_id: String = asset_library.register_image(blue, "blue_reference")
	var red_graph := _make_mock_graph_with_reference(red_id)
	var blue_graph := _make_mock_graph_with_reference(blue_id)
	var runner := MockRunnerScript.new()

	var red_result: Dictionary = runner.run_to_batch(red_graph, asset_library, "batch_1")
	var blue_result: Dictionary = runner.run_to_batch(blue_graph, asset_library, "batch_1")
	assert_true(red_result["ok"])
	assert_true(blue_result["ok"])
	var red_output: Image = asset_library.get_image(String(red_result["asset_ids"][0]))
	var blue_output: Image = asset_library.get_image(String(blue_result["asset_ids"][0]))
	assert_ne(red_output.get_data(), blue_output.get_data())
	var provenance: Dictionary = (
		asset_library.get_asset_meta(String(red_result["asset_ids"][0]))["provenance"]
	)
	assert_eq(provenance["reference_asset_id"], red_id)
	assert_eq(provenance["reference_content_sha256"], GraphContextScript.image_content_sha256(red))


func test_ordered_reference_set_reaches_mock_and_persists_plural_provenance() -> void:
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var red_id := AssetLibrary.register_image(red, "red")
	var blue_id := AssetLibrary.register_image(blue, "blue")
	var graph := _make_mock_graph()
	graph.add_node(
		ReferenceSetNodeScript.new(), "references", {"asset_ids": [blue_id, red_id]}, Vector2.ZERO
	)
	assert_true(bool(graph.add_edge("references", "images", "generate", "image")["ok"]))
	var result: Dictionary = MockRunnerScript.new().run_to_batch(graph, AssetLibrary, "batch_1")
	assert_true(result["ok"])
	var provenance: Dictionary = (
		AssetLibrary.get_asset_meta(String(result["asset_ids"][0]))["provenance"]
	)
	assert_eq(provenance["reference_asset_ids"], [blue_id, red_id])
	assert_eq(
		provenance["reference_content_sha256s"],
		[
			GraphContextScript.image_content_sha256(blue),
			GraphContextScript.image_content_sha256(red),
		]
	)


func test_unconnected_empty_reference_does_not_block_target_batch() -> void:
	var graph := _make_mock_graph()
	graph.add_node(ImageInputNodeScript.new(), "unused_reference", {}, Vector2.ZERO)
	var result: Dictionary = MockRunnerScript.new().run_to_batch(graph, AssetLibrary, "batch_1")
	assert_true(result["ok"])
	assert_eq(result["asset_ids"].size(), 10)


func test_connected_reference_reports_missing_not_found_and_decode_errors() -> void:
	var graph := _make_mock_graph_with_reference("")
	var runner := MockRunnerScript.new()
	var missing: Dictionary = runner.run_to_batch(graph, AssetLibrary, "batch_1")
	assert_false(missing["ok"])
	assert_eq(missing["error"]["code"], "missing_asset_reference")
	assert_eq(missing["error"]["node_id"], "reference")

	graph.set_node_params("reference", {"asset_id": "missing-id"})
	var not_found: Dictionary = runner.run_to_batch(graph, AssetLibrary, "batch_1")
	assert_eq(not_found["error"]["code"], "asset_not_found")

	var meta := {"id": "broken-id", "name": "broken", "origin": "imported", "provenance": {}}
	assert_eq(
		(
			AssetLibrary
			. load_from_zip_files(
				{
					"assets/broken-id.meta.json": FileIOScript.json_to_bytes(meta),
					"assets/broken-id.png": PackedByteArray([1, 2, 3]),
				}
			)
		),
		OK
	)
	graph.set_node_params("reference", {"asset_id": "broken-id"})
	var decode_failed: Dictionary = runner.run_to_batch(graph, AssetLibrary, "batch_1")
	assert_eq(decode_failed["error"]["code"], "asset_decode_failed")
	assert_eq(decode_failed["error"]["node_id"], "reference")


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


func _make_mock_graph_with_reference(asset_id: String) -> PFGraph:
	var graph := _make_mock_graph()
	graph.add_node(ImageInputNodeScript.new(), "reference", {"asset_id": asset_id}, Vector2.ZERO)
	assert_true(bool(graph.add_edge("reference", "image", "generate", "image")["ok"]))
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
