extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Hit Policy")


func test_canvas_hit_policy_prioritizes_batch_thumbnail_inside_review_card() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	var hit := _hit(canvas, card.position + Vector2(20, 60))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_left_click_on_batch_thumbnail_does_not_start_card_drag() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	canvas._begin_left_interaction(canvas.world_to_screen(card.position + Vector2(20, 60)), false)

	assert_eq(canvas.get_selected_ids(), ["batch_1"])
	assert_eq(card.get_selected_asset_ids(), [ids[0]])
	assert_false(canvas._selection.is_dragging_items)


func test_canvas_hit_policy_keeps_batch_thumbnail_available_at_25_percent() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
	card.set_lod_camera_zoom(0.25)

	var hit := _hit(canvas, card.position + Vector2(20, 60))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_hit_policy_prioritizes_batch_graph_port_over_thumbnail() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	_set_graph("graph_hit", [_batch_node("batch_1", ids)])
	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Batch", "batch_item", false, "graph_hit", "batch_1"
	)

	var hit := _hit(canvas, card.get_graph_port_anchor("in", true))

	assert_eq(hit["kind"], HitPolicy.KIND_GRAPH_PORT)
	assert_eq(hit["item_id"], "batch_item")
	assert_eq(hit["port_name"], "in")
	assert_true(hit["is_input"])
	assert_eq(hit["asset_index"], -1)


func test_canvas_hit_policy_reports_node_output_port_on_card_edge() -> void:
	var canvas: Control = _canvas()
	_set_graph("graph_hit", [_graph_node("objects", "object_list")])
	var node: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)

	var hit := _hit(canvas, node.get_graph_port_anchor("items", false))

	assert_eq(hit["kind"], HitPolicy.KIND_GRAPH_PORT)
	assert_eq(hit["item_id"], "objects_item")
	assert_eq(hit["port_name"], "items")
	assert_false(hit["is_input"])
	assert_eq(hit["port_index"], 0)


func test_canvas_left_click_on_graph_port_selects_without_dragging_card() -> void:
	var canvas: Control = _canvas()
	_set_graph("graph_hit", [_graph_node("objects", "object_list")])
	var node: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)

	canvas._begin_left_interaction(
		canvas.world_to_screen(node.get_graph_port_anchor("items", false)), false
	)

	assert_eq(canvas.get_selected_ids(), ["objects_item"])
	assert_false(canvas._selection.is_dragging_items)


func test_canvas_drag_to_compatible_graph_port_hot_zone_adds_edge() -> void:
	var canvas: Control = _canvas()
	_set_graph(
		"graph_hit", [_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")]
	)
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var generate: Node = canvas._add_node_direct(
		_node_item("generate_item", "graph_hit", "generate", Vector2(380, 100))
	)

	canvas._begin_left_interaction(
		canvas.world_to_screen(objects.get_graph_port_anchor("items", false)), false
	)
	canvas._finish_left_interaction(
		canvas.world_to_screen(generate.get_graph_port_anchor("items", true) + Vector2(126, 28))
	)

	var graph_data := ProjectService.get_graph_data("graph_hit")
	assert_eq(
		graph_data.get("edges", []), [{"from": ["objects", "items"], "to": ["generate", "items"]}]
	)


func test_canvas_drag_between_incompatible_graph_ports_does_not_add_edge() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	_set_graph("graph_hit", [_graph_node("objects", "object_list"), _batch_node("batch_1", ids)])
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var batch: Node = canvas._add_batch_card(
		ids, Vector2(380, 100), "Batch", "batch_item", false, "graph_hit", "batch_1"
	)

	canvas._begin_left_interaction(
		canvas.world_to_screen(objects.get_graph_port_anchor("items", false)), false
	)
	canvas._finish_left_interaction(canvas.world_to_screen(batch.get_graph_port_anchor("in", true)))

	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])


func test_canvas_delete_key_removes_selected_graph_edge() -> void:
	var canvas: Control = _canvas()
	var edge := {"from": ["objects", "items"], "to": ["generate", "items"]}
	_set_graph(
		"graph_hit",
		[_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")],
		[edge]
	)
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var generate: Node = canvas._add_node_direct(
		_node_item("generate_item", "graph_hit", "generate", Vector2(380, 100))
	)
	var edge_midpoint: Vector2 = objects.get_graph_port_anchor("items", false).lerp(
		generate.get_graph_port_anchor("items", true), 0.5
	)

	canvas._begin_left_interaction(canvas.world_to_screen(edge_midpoint), false)
	canvas._unhandled_key_input(_delete_key_event())

	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])
	UndoService.undo()
	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [edge])


func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	canvas._add_batch_card(ids, Vector2.ZERO, "Batch", "batch_1", false)
	canvas.add_sprite_item(_image(Color.GREEN), "", Vector2.ZERO, "sprite_top", false)

	var hit := _hit(canvas, Vector2(2, 2))

	assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
	assert_eq(hit["item_id"], "sprite_top")


func test_canvas_hit_policy_reports_empty_space() -> void:
	var canvas: Control = _canvas()

	var hit := _hit(canvas, Vector2(2000, 2000))

	assert_eq(hit["kind"], HitPolicy.KIND_EMPTY)
	assert_eq(hit["item_id"], "")


func _canvas() -> Control:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	return canvas


func _hit(canvas: Control, world_position: Vector2) -> Dictionary:
	return HitPolicy.hit_at_world(
		canvas.item_layer,
		world_position,
		CanvasBatchCardScript,
		CanvasItemSpriteScript,
		CanvasNodeCardScript
	)


func _register_asset(color: Color, name: String) -> String:
	return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})


func _set_graph(graph_id: String, nodes: Array, edges: Array = []) -> void:
	ProjectService.set_graph_data(
		graph_id,
		{"graph_version": 1, "id": graph_id, "name": "Hit Policy", "nodes": nodes, "edges": edges}
	)


func _graph_node(node_id: String, node_type: String) -> Dictionary:
	return {"id": node_id, "type": node_type, "params": {}, "position": [0, 0]}


func _batch_node(node_id: String, asset_ids: Array) -> Dictionary:
	return {
		"id": node_id,
		"type": "batch",
		"params": {"asset_ids": asset_ids.duplicate(), "label": "Batch"},
		"position": [0, 0],
	}


func _node_item(
	item_id: String, graph_id: String, node_id: String, position: Vector2
) -> Dictionary:
	return {
		"id": item_id,
		"type": "node",
		"graph_id": graph_id,
		"node_id": node_id,
		"position": [int(position.x), int(position.y)],
		"z_index": 0,
		"locked": false,
	}


func _image(color: Color) -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _delete_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_DELETE
	event.pressed = true
	return event
