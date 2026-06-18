extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Batch Card")


func test_canvas_batch_card_exports_asset_queue_and_can_split_subset() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
	card.selected_asset_ids.append(ids[0])

	assert_gte(card.get_canvas_bounds().size.x, 600.0)
	assert_gte(card.get_canvas_bounds().size.y, 216.0)

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["type"], "batch_card")
	assert_eq(item["asset_ids"], ids)
	assert_eq(canvas._get_batch_asset_ids("batch_1", true), [ids[0]])

	var child: Node = canvas._split_batch_selection("batch_1")
	assert_not_null(child)
	assert_eq(child.asset_ids, [ids[0]])
	assert_eq(canvas.get_item_count(), 2)


func test_canvas_batch_card_marks_review_state_and_splits_kept_subset() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [
		_register_asset(Color.RED, "red"),
		_register_asset(Color.BLUE, "blue"),
		_register_asset(Color.GREEN, "green"),
	]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	assert_eq(
		canvas._set_batch_review_state(
			"batch_1", [ids[0], ids[2]], CanvasBatchCardScript.REVIEW_KEEP, false
		),
		2
	)
	assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_KEEP), [ids[0], ids[2]])

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["review_states"][ids[0]], CanvasBatchCardScript.REVIEW_KEEP)
	assert_eq(item["review_states"][ids[2]], CanvasBatchCardScript.REVIEW_KEEP)

	var child: Node = canvas._split_batch_marked(
		"batch_1", CanvasBatchCardScript.REVIEW_KEEP, "keep"
	)
	assert_not_null(child)
	assert_eq(child.asset_ids, [ids[0], ids[2]])
	assert_eq(canvas.get_item_count(), 2)


func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var graph := GraphScript.new()
	graph.id = "graph_batch_test"
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	assert_eq(card.asset_ids, ids)

	var canvas_data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = canvas_data["items"][0]
	assert_eq(item["type"], "node")
	assert_eq(item["graph_id"], graph.id)
	assert_eq(item["node_id"], "batch_1")
	assert_false(item.has("asset_ids"))

	var green_id := _register_asset(Color.GREEN, "green")
	canvas._replace_batch_asset_ids("node_item_1", [green_id], false)

	assert_eq(card.asset_ids, [green_id])
	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_eq(batch_node["params"]["asset_ids"], [green_id])

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)

	assert_eq(reloaded_canvas.get_item_count(), 1)
	assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])


func test_graph_batch_card_persists_review_state_in_graph_params() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var graph := GraphScript.new()
	graph.id = "graph_batch_review_test"
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	assert_eq(
		canvas._set_batch_review_state(
			"node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
		),
		1
	)
	assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])

	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_eq(batch_node["params"]["review_states"][ids[1]], CanvasBatchCardScript.REVIEW_FLAG)

	var canvas_data: Dictionary = canvas.export_canvas_data()
	assert_false(Dictionary(canvas_data["items"][0]).has("review_states"))

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)
	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]

	assert_eq(reloaded_card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])


func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var graph := GraphScript.new()
	graph.id = "graph_node_card_test"
	graph.add_node(
		ObjectListNodeScript.new(), "objects", {"items": "barrel\ncrate"}, Vector2(24, 32)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var node_card: Node = canvas._add_graph_node_card(
		graph.id, "objects", Vector2(24, 32), "node_item_objects", false
	)
	assert_not_null(node_card)

	var canvas_data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = canvas_data["items"][0]
	assert_eq(item["type"], "node")
	assert_eq(item["graph_id"], graph.id)
	assert_eq(item["node_id"], "objects")
	assert_false(item.has("asset_ids"))

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)

	assert_eq(reloaded_canvas.get_item_count(), 1)
	assert_eq(reloaded_canvas.export_canvas_data()["items"][0]["node_id"], "objects")


func test_ai_generate_inputs_share_single_canvas_anchor() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red")]
	var graph := GraphScript.new()
	graph.id = "graph_anchor_test"
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 1, "seed": 3},
		Vector2(10, 20)
	)
	graph.add_node(
		BatchNodeScript.new(),
		"batch_1",
		{"label": "Candidates", "asset_ids": ids},
		Vector2(300, 69)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var generate_card: Node = canvas._add_graph_node_card(
		graph.id, "generate", Vector2(10, 20), "node_item_generate", false
	)
	var batch_card: Node = canvas._add_batch_card(
		ids, Vector2(300, 69), "Candidates", "node_item_batch", false, graph.id, "batch_1"
	)

	var items_anchor: Vector2 = generate_card.get_graph_port_anchor("items", true)
	var spec_anchor: Vector2 = generate_card.get_graph_port_anchor("spec", true)
	var output_anchor: Vector2 = generate_card.get_graph_port_anchor("images", false)
	var right_center: Vector2 = (
		generate_card.get_canvas_bounds().position
		+ Vector2(
			generate_card.get_canvas_bounds().size.x, generate_card.get_canvas_bounds().size.y * 0.5
		)
	)

	assert_eq(items_anchor, spec_anchor)
	assert_ne(output_anchor, right_center)
	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "items", true), items_anchor)
	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "spec", true), items_anchor)
	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "images", false), output_anchor)
	assert_eq(
		GraphEdgeRenderer._edge_anchor_world(batch_card, "in", true),
		batch_card.get_graph_port_anchor("in", true)
	)


func _register_asset(color: Color, name: String) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return AssetLibrary.register_image(image, name, {"origin": "imported"})
