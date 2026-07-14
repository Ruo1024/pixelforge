extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")


func before_each() -> void:
	ProjectService.new_project("Output Card v2")


func test_graph_output_card_persists_only_canvas_identity_and_display_fields() -> void:
	var fixture := await _make_card(3)
	var canvas: Control = fixture["canvas"]
	var card: Node = fixture["card"]
	assert_eq(card.get_visible_asset_ids(), ["asset-0", "asset-1", "asset-2"])
	assert_not_null(card.get_node("OutputCardController"))
	card.set_display_title("Chosen Output")
	card.set_requested_size(Vector2i(720, 420))
	var item: Dictionary = canvas.export_canvas_data()["items"][0]
	assert_eq(item["type"], "node")
	assert_eq(item["graph_id"], "graph-output")
	assert_eq(item["node_id"], "output")
	assert_eq(item["display_title"], "Chosen Output")
	assert_eq(item["size"], [720, 420])
	assert_false(item.has("asset_ids"))
	assert_false(item.has("selected_asset_ids"))


func test_title_size_collapse_ports_and_lod_remain_available() -> void:
	var fixture := await _make_card(1)
	var canvas: Control = fixture["canvas"]
	var card: Node = fixture["card"]
	var expanded_height: float = card.get_canvas_bounds().size.y
	assert_true(card.resize_handle_contains_world(card.get_canvas_bounds().end - Vector2.ONE))
	assert_false(card._graph_port_at_world(card.get_graph_port_anchor("assets", false)).is_empty())
	card.set_lod_camera_zoom(0.1)
	assert_false(card.get_node("OutputCardController").visible)
	card.set_lod_camera_zoom(1.0)
	(card.get_node("CollapseButton") as Button).pressed.emit()
	assert_true(card.collapsed)
	assert_lt(card.get_canvas_bounds().size.y, expanded_height)
	assert_true(UndoService.undo())
	assert_false(card.collapsed)
	assert_eq(canvas.export_canvas_data()["items"][0]["collapsed"], false)


func _make_card(count: int) -> Dictionary:
	var graph := GraphScript.new()
	graph.id = "graph-output"
	graph.add_node(BatchNodeScript.new(), "output", _params(count), Vector2.ZERO)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(1000, 700)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "output", Vector2(24, 24), "output-card", false
	)
	return {"canvas": canvas, "card": card}


func _params(count: int) -> Dictionary:
	var slots := []
	for index in range(count):
		slots.append(
			{
				"slot_id": "slot-%d" % index,
				"run_id": "",
				"request_id": "",
				"source_row_id": "",
				"source_asset_id": "",
				"input_snapshot_id": "",
				"planned_size": [4, 4],
				"status": "succeeded",
				"asset_id": "asset-%d" % index,
				"detached": false,
				"unexpected": false,
				"error": null,
			}
		)
	return {
		"label": "Output",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": slots,
	}
