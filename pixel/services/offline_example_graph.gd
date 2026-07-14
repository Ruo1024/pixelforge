class_name PFOfflineExampleGraph
extends RefCounted

## Builds the bundled Beta 0.7 starter graph without running it or creating outputs.

const GraphScript := preload("res://core/graph/pf_graph.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const PixelCleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")
const IdUtil := preload("res://core/util/id_util.gd")

const HORIZONTAL_GAP := 80.0
const VERTICAL_GAP := 80.0
const RUNTIME_OUTPUT_WIDTH := 600.0
const INPUT_NODE_IDS := ["prompt_preset", "text_prompt", "reference_set"]


static func build(example_prompt: String, graph_name: String) -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_example_%s" % IdUtil.uuid_v4().left(8)
	graph.name = graph_name
	graph.add_node(
		PromptPresetNodeScript.new(),
		"prompt_preset",
		{"preset": PromptPresetNodeScript.DEFAULT_PRESET.duplicate(true)}
	)
	graph.add_node(TextPromptNodeScript.new(), "text_prompt", {"text": example_prompt})
	graph.add_node(ReferenceSetNodeScript.new(), "reference_set", {"asset_ids": []})
	graph.add_node(AiGenerateNodeScript.new(), "generate", {})
	graph.add_node(PixelCleanupNodeScript.new(), "cleanup", {})
	graph.add_edge("prompt_preset", "prefix", "generate", "prefix")
	graph.add_edge("text_prompt", "prompt", "generate", "prompt")
	graph.add_edge("reference_set", "assets", "generate", "references")
	return graph


static func layout_positions(effective_sizes: Dictionary) -> Dictionary:
	var positions: Dictionary = {}
	var next_y: float = 0.0
	var input_right: float = 0.0
	for node_id in INPUT_NODE_IDS:
		var size: Vector2 = _size_for(effective_sizes, node_id)
		positions[node_id] = Vector2(0.0, next_y)
		next_y += size.y + VERTICAL_GAP
		input_right = maxf(input_right, size.x)
	var input_bottom: float = next_y - VERTICAL_GAP
	var generate_size: Vector2 = _size_for(effective_sizes, "generate")
	var generate_y: float = roundf((input_bottom - generate_size.y) * 0.5)
	positions["generate"] = Vector2(input_right + HORIZONTAL_GAP, generate_y)
	positions["cleanup"] = Vector2(
		(
			positions["generate"].x
			+ generate_size.x
			+ HORIZONTAL_GAP
			+ RUNTIME_OUTPUT_WIDTH
			+ HORIZONTAL_GAP
		),
		generate_y
	)
	return positions


static func _size_for(effective_sizes: Dictionary, node_id: String) -> Vector2:
	var value: Variant = effective_sizes.get(node_id, Vector2.ONE)
	if value is Vector2i:
		return Vector2(maxi(1, value.x), maxi(1, value.y))
	if value is Vector2:
		return Vector2(maxf(1.0, value.x), maxf(1.0, value.y))
	return Vector2.ONE
