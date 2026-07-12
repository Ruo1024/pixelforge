class_name PFOfflineExampleGraph
extends RefCounted

## Builds the bundled self-contained Beta workspace graph and deterministic reference asset.

const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const IdUtil := preload("res://core/util/id_util.gd")


static func build(reference_asset_id: String, batch_label: String) -> PFGraph:
	var graph := GraphScript.new()
	graph.id = "graph_mock_%s" % IdUtil.uuid_v4().left(8)
	graph.name = "Mock Generate Batch"
	graph.add_node(
		ObjectListNodeScript.new(),
		"objects",
		{"items": "barrel\nfence\nscarecrow\ncrate\nwell"},
		Vector2(0, 0)
	)
	graph.add_node(
		SizeSpecNodeScript.new(),
		"size",
		{"width": 32, "height": 32, "per_subject": 1},
		Vector2(0, 150)
	)
	graph.add_node(
		ImageInputNodeScript.new(), "reference", {"asset_id": reference_asset_id}, Vector2(0, 300)
	)
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 2, "seed": 1000},
		Vector2(280, 75)
	)
	graph.add_node(BatchNodeScript.new(), "batch_1", {"label": batch_label}, Vector2(560, 29))
	graph.add_edge("objects", "items", "generate", "items")
	graph.add_edge("size", "spec", "generate", "spec")
	graph.add_edge("reference", "image", "generate", "image")
	graph.add_edge("generate", "images", "batch_1", "in")
	return graph


static func make_reference_image() -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var checker := int(x / 4) + int(y / 4)
			image.set_pixel(x, y, Color8(56, 92, 138) if checker % 2 == 0 else Color8(228, 174, 82))
	return image
