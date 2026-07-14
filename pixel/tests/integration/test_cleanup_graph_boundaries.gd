extends "res://addons/gut/test.gd"

const GraphScript := preload("res://core/graph/pf_graph.gd")
const AiNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const RunnerScript := preload("res://services/graph_mock_runner.gd")


func test_graph_rejects_direct_ai_generate_to_cleanup() -> void:
	var graph := GraphScript.new()
	graph.add_node(AiNodeScript.new(), "generate", {})
	graph.add_node(CleanupNodeScript.new(), "cleanup", {})
	var result: Dictionary = graph.add_edge("generate", "assets", "cleanup", "assets")
	assert_false(result.get("ok", true))
	assert_eq(result.get("code", ""), "cleanup_requires_output_source")


func test_normal_graph_run_stops_manual_cleanup_ready_without_pipeline() -> void:
	AssetLibrary.clear()
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var asset_id := AssetLibrary.register_image(image, "source")
	var graph := GraphScript.new()
	graph.add_node(ImageInputNodeScript.new(), "input", {"asset_id": asset_id})
	graph.add_node(CleanupNodeScript.new(), "cleanup", {})
	assert_true(graph.add_edge("input", "assets", "cleanup", "assets")["ok"])
	var result: Dictionary = RunnerScript.new().run_to_batch(graph, AssetLibrary)
	assert_true(result.get("ok", false))
	assert_eq(result.get("ready_node_ids", []), ["cleanup"])
	assert_eq(result.get("terminal_items", []), [])
