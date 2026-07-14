extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const CanvasItemFrameScript := preload("res://ui/canvas/canvas_item_frame.gd")
const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")
const Strings := preload("res://ui/shell/strings.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Hit Policy")


func test_canvas_hit_policy_prioritizes_output_tile() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = _add_output_card(canvas, ids, Vector2(16, 24), "batch_1")

	var hit := _hit(canvas, _slot_center(card, 0))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_left_click_on_batch_thumbnail_does_not_start_card_drag() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = _add_output_card(canvas, ids, Vector2(16, 24), "batch_1")

	canvas._begin_left_interaction(canvas.world_to_screen(_slot_center(card, 0)), false)

	assert_eq(canvas.get_selected_ids(), ["batch_1"])
	assert_eq(card.get_selected_asset_ids(), [ids[0]])
	assert_false(canvas._selection.is_dragging_items)


func test_canvas_hit_policy_keeps_output_tile_available_at_25_percent() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = _add_output_card(canvas, ids, Vector2(16, 24), "batch_1")
	card.set_lod_camera_zoom(0.25)

	var hit := _hit(canvas, _slot_center(card, 0))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_hit_policy_prioritizes_batch_graph_port_over_thumbnail() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	_set_graph("graph_hit", [_batch_node("batch_1", ids)])
	var card: Node = canvas._add_graph_node_card(
		"graph_hit", "batch_1", Vector2(16, 24), "batch_item", false
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

	var hit := _hit(canvas, node.get_graph_port_anchor("subjects", false))

	assert_eq(hit["kind"], HitPolicy.KIND_GRAPH_PORT)
	assert_eq(hit["item_id"], "objects_item")
	assert_eq(hit["port_name"], "subjects")
	assert_false(hit["is_input"])
	assert_eq(hit["port_index"], 0)


func test_canvas_left_click_on_graph_port_selects_without_dragging_card() -> void:
	var canvas: Control = _canvas()
	_set_graph("graph_hit", [_graph_node("objects", "object_list")])
	var node: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)

	canvas._begin_left_interaction(
		canvas.world_to_screen(node.get_graph_port_anchor("subjects", false)), false
	)

	assert_eq(canvas.get_selected_ids(), ["objects_item"])
	assert_false(canvas._selection.is_dragging_items)


func test_canvas_drag_to_compatible_graph_port_hot_zone_adds_edge() -> void:
	var canvas: Control = _canvas()
	var status_events := []
	canvas.graph_status.connect(func(event: Dictionary) -> void: status_events.append(event))
	_set_graph(
		"graph_hit", [_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")]
	)
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var generate: Node = canvas._add_node_direct(
		_node_item("generate_item", "graph_hit", "generate", Vector2(700, 100))
	)
	var target_anchor: Vector2 = generate.get_graph_port_anchor("subjects", true)
	var hot_zone_world := target_anchor + Vector2(24, 28)

	canvas._begin_left_interaction(
		canvas.world_to_screen(objects.get_graph_port_anchor("subjects", false)), false
	)
	canvas._handle_mouse_motion(_mouse_motion_event(canvas.world_to_screen(hot_zone_world)))

	assert_eq(canvas._graph_edge_drag_world, target_anchor)
	assert_eq(status_events[0]["type"], "connect_preview")
	assert_eq(status_events[0]["state"], "valid")

	canvas._finish_left_interaction(canvas.world_to_screen(hot_zone_world))

	var graph_data := ProjectService.get_graph_data("graph_hit")
	assert_eq(
		graph_data.get("edges", []),
		[{"from": ["objects", "subjects"], "to": ["generate", "subjects"]}]
	)
	assert_eq(String(status_events[-1]["type"]), "connect_succeeded")
	assert_eq(
		status_events[-1]["edge"], {"from": ["objects", "subjects"], "to": ["generate", "subjects"]}
	)


func test_hidden_graph_edges_are_not_drawn_or_selectable_and_graph_truth_is_unchanged() -> void:
	var canvas: Control = _canvas()
	var edge := {"from": ["objects", "subjects"], "to": ["generate", "subjects"]}
	_set_graph(
		"graph_hit",
		[_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")],
		[edge]
	)
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var generate: Node = canvas._add_node_direct(
		_node_item("generate_item", "graph_hit", "generate", Vector2(600, 100))
	)
	var midpoint: Vector2 = (
		(
			objects.get_graph_port_anchor("subjects", false)
			+ generate.get_graph_port_anchor("subjects", true)
		)
		* 0.5
	)

	canvas._begin_left_interaction(canvas.world_to_screen(midpoint), false)
	assert_false(canvas._selected_graph_edge.is_empty())
	assert_false(canvas._toggle_graph_edges())
	canvas._begin_left_interaction(canvas.world_to_screen(midpoint), false)

	assert_true(canvas._selected_graph_edge.is_empty())
	assert_eq(ProjectService.get_graph_data("graph_hit")["edges"], [edge])
	assert_true(canvas._toggle_graph_edges())


func test_canvas_drag_between_incompatible_graph_ports_does_not_add_edge() -> void:
	var canvas: Control = _canvas()
	var status_messages := []
	var status_events := []
	canvas.graph_status.connect(func(event: Dictionary) -> void: status_events.append(event))
	canvas.graph_connect_failed.connect(
		func(reason: String) -> void:
			status_messages.append(Strings.text("STATUS_GRAPH_CONNECT_FAILED") % reason)
	)
	var ids := [_register_asset(Color.RED, "red")]
	_set_graph("graph_hit", [_graph_node("objects", "object_list"), _batch_node("batch_1", ids)])
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var batch: Node = canvas._add_graph_node_card(
		"graph_hit", "batch_1", Vector2(700, 100), "batch_item", false
	)

	canvas._begin_left_interaction(
		canvas.world_to_screen(objects.get_graph_port_anchor("subjects", false)), false
	)
	canvas._handle_mouse_motion(
		_mouse_motion_event(canvas.world_to_screen(batch.get_graph_port_anchor("in", true)))
	)
	assert_eq(status_events[0]["type"], "connect_preview")
	assert_eq(status_events[0]["state"], "invalid")
	assert_eq(status_events[0]["reason"], "Cannot connect subject_list to asset_list")
	canvas._finish_left_interaction(canvas.world_to_screen(batch.get_graph_port_anchor("in", true)))

	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])
	assert_eq(
		status_messages,
		[Strings.text("STATUS_GRAPH_CONNECT_FAILED") % "Cannot connect subject_list to asset_list"]
	)


func test_canvas_delete_key_removes_selected_graph_edge() -> void:
	var canvas: Control = _canvas()
	var status_events := []
	canvas.graph_status.connect(func(event: Dictionary) -> void: status_events.append(event))
	var edge := {"from": ["objects", "subjects"], "to": ["generate", "subjects"]}
	_set_graph(
		"graph_hit",
		[_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")],
		[edge]
	)
	var objects: Node = canvas._add_node_direct(
		_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
	)
	var generate: Node = canvas._add_node_direct(
		_node_item("generate_item", "graph_hit", "generate", Vector2(700, 100))
	)
	var edge_midpoint: Vector2 = objects.get_graph_port_anchor("subjects", false).lerp(
		generate.get_graph_port_anchor("subjects", true), 0.5
	)

	canvas._begin_left_interaction(canvas.world_to_screen(edge_midpoint), false)
	assert_eq(String(status_events[0]["type"]), "edge_selected")
	assert_eq(status_events[0]["edge"], edge)
	canvas._unhandled_key_input(_delete_key_event())

	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])
	assert_eq(String(status_events[1]["type"]), "edge_deleted")
	assert_eq(status_events[1]["edge"], edge)
	UndoService.undo()
	assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [edge])


func test_canvas_deleting_graph_node_removes_incident_edges_and_undo_restores() -> void:
	var canvas: Control = _canvas()
	var status_events := []
	canvas.graph_status.connect(func(event: Dictionary) -> void: status_events.append(event))
	var edge := {"from": ["objects", "subjects"], "to": ["generate", "subjects"]}
	_set_graph(
		"graph_hit",
		[_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")],
		[edge]
	)
	canvas._add_node_direct(_node_item("objects_item", "graph_hit", "objects", Vector2(100, 100)))
	canvas._add_node_direct(_node_item("generate_item", "graph_hit", "generate", Vector2(380, 100)))

	canvas._select_only(["objects_item"])
	canvas.delete_selected(true)

	var graph_data := ProjectService.get_graph_data("graph_hit")
	assert_eq(_graph_node_ids(graph_data), ["generate"])
	assert_eq(graph_data.get("edges", []), [])
	assert_false(canvas._items_by_id.has("objects_item"))
	assert_eq(String(status_events[0]["type"]), "nodes_deleted")
	assert_eq(int(status_events[0]["nodes"]), 1)
	assert_eq(int(status_events[0]["edges"]), 1)

	UndoService.undo()

	graph_data = ProjectService.get_graph_data("graph_hit")
	assert_eq(_graph_node_ids(graph_data), ["objects", "generate"])
	assert_eq(graph_data.get("edges", []), [edge])
	assert_true(canvas._items_by_id.has("objects_item"))


func test_stage_frame_groups_moves_and_deletes_as_explicit_membership_with_undo() -> void:
	var canvas: Control = _canvas()
	_set_graph(
		"graph_stage",
		[_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")]
	)
	canvas._add_node_direct(_node_item("objects_item", "graph_stage", "objects", Vector2(100, 100)))
	canvas._add_node_direct(
		_node_item("generate_item", "graph_stage", "generate", Vector2(420, 120))
	)
	canvas.select_ids(["objects_item", "generate_item"])

	assert_true(canvas._group_selected_nodes())
	assert_eq(canvas.get_item_count(), 3)
	var frame_id := String(canvas.get_selected_ids()[0])
	var grouped_items: Array = canvas.export_canvas_data()["items"]
	assert_eq(_item_by_id(grouped_items, "objects_item")["frame_id"], frame_id)
	assert_eq(_item_by_id(grouped_items, "generate_item")["frame_id"], frame_id)
	assert_false(_item_by_id(grouped_items, frame_id).has("member_ids"))
	var frame_position := Vector2(
		_item_by_id(grouped_items, frame_id)["position"][0],
		_item_by_id(grouped_items, frame_id)["position"][1]
	)
	assert_eq(_hit(canvas, frame_position + Vector2(8, 8))["item_id"], frame_id)

	canvas.move_selected_by(Vector2(40, 24), true)
	var moved_items: Array = canvas.export_canvas_data()["items"]
	assert_eq(_item_by_id(moved_items, "objects_item")["position"], [140, 124])
	assert_eq(_item_by_id(moved_items, "generate_item")["position"], [460, 144])
	for node in ProjectService.get_graph_data("graph_stage")["nodes"]:
		assert_false(node.has("position"))
	assert_true(UndoService.undo())
	assert_eq(
		_item_by_id(canvas.export_canvas_data()["items"], "objects_item")["position"], [100, 100]
	)

	canvas.select_ids([frame_id])
	canvas.delete_selected(true)
	assert_eq(canvas.get_item_count(), 2)
	assert_null(_item_by_id(canvas.export_canvas_data()["items"], "objects_item")["frame_id"])
	assert_eq(ProjectService.get_graph_data("graph_stage")["nodes"].size(), 2)
	assert_true(UndoService.undo())
	assert_eq(canvas.get_item_count(), 3)
	assert_eq(
		_item_by_id(canvas.export_canvas_data()["items"], "objects_item")["frame_id"], frame_id
	)


func test_stage_frame_rejects_cross_graph_grouping() -> void:
	var canvas: Control = _canvas()
	_set_graph("graph_a", [_graph_node("a", "object_list")])
	_set_graph("graph_b", [_graph_node("b", "object_list")])
	canvas._add_node_direct(_node_item("a_item", "graph_a", "a", Vector2.ZERO))
	canvas._add_node_direct(_node_item("b_item", "graph_b", "b", Vector2(300, 0)))
	canvas.select_ids(["a_item", "b_item"])

	assert_false(canvas._group_selected_nodes())
	assert_eq(canvas.get_item_count(), 2)


func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	_add_output_card(canvas, ids, Vector2.ZERO, "batch_1")
	canvas.add_sprite_item(_image(Color.GREEN), "", Vector2.ZERO, "sprite_top", false)

	var hit := _hit(canvas, Vector2(2, 2))

	assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
	assert_eq(hit["item_id"], "sprite_top")


func test_canvas_hit_policy_reports_empty_space() -> void:
	var canvas: Control = _canvas()

	var hit := _hit(canvas, Vector2(2000, 2000))

	assert_eq(hit["kind"], HitPolicy.KIND_EMPTY)
	assert_eq(hit["item_id"], "")


func test_canvas_right_click_routes_batch_before_empty_graph_quick_add() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = _add_output_card(canvas, ids, Vector2(16, 24), "batch_1")
	var batch_requests := []
	var graph_requests := []
	canvas.batch_context_requested.connect(
		func(card_id: String, screen_position: Vector2i) -> void:
			batch_requests.append([card_id, screen_position])
	)
	canvas.graph_quick_add_requested.connect(
		func(screen_position: Vector2i) -> void: graph_requests.append(screen_position)
	)

	canvas._handle_mouse_button(
		_right_click_event(canvas.world_to_screen(card.position + Vector2(4, 4)))
	)

	assert_eq(batch_requests.size(), 1)
	assert_eq(batch_requests[0][0], "batch_1")
	assert_eq(graph_requests, [])

	canvas._handle_mouse_button(_right_click_event(canvas.world_to_screen(Vector2(2000, 2000))))

	assert_eq(batch_requests.size(), 1)
	assert_eq(graph_requests.size(), 1)


func _canvas() -> Control:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	return canvas


func _add_output_card(
	canvas: Control, asset_ids: Array, position: Vector2, item_id: String
) -> Node:
	var graph_id := "graph_%s" % item_id
	var node_id := "output_%s" % item_id
	_set_graph(graph_id, [_batch_node(node_id, asset_ids)])
	return canvas._add_graph_node_card(graph_id, node_id, position, item_id, false)


func _slot_center(card: Node, index: int) -> Vector2:
	var grid: Control = card.get_node("OutputCardController/SlotGrid")
	return card.position + grid.position + grid.slot_rect(index).get_center()


func _hit(canvas: Control, world_position: Vector2) -> Dictionary:
	return HitPolicy.hit_at_world(
		canvas.item_layer,
		world_position,
		CanvasBatchCardScript,
		CanvasItemSpriteScript,
		CanvasNodeCardScript,
		CanvasItemFrameScript
	)


func _register_asset(color: Color, name: String) -> String:
	return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})


func _set_graph(graph_id: String, nodes: Array, edges: Array = []) -> void:
	ProjectService.set_graph_data(
		graph_id,
		{"graph_version": 2, "id": graph_id, "name": "Hit Policy", "nodes": nodes, "edges": edges}
	)


func _graph_node(node_id: String, node_type: String) -> Dictionary:
	var params := (
		{"rows": []}
		if node_type == "object_list"
		else {
			"provider_id": "mock",
			"model_id": "pixel_mock_v1",
			"target_width": 32,
			"target_height": 32,
			"batch_size": 1,
			"seed": -1,
			"extra": {},
		}
	)
	return {"id": node_id, "type": node_type, "params": params}


func _batch_node(node_id: String, asset_ids: Array) -> Dictionary:
	return {
		"id": node_id,
		"type": "batch",
		"params": _output_params(asset_ids),
	}


func _output_params(asset_ids: Array) -> Dictionary:
	var slots := []
	for index in range(asset_ids.size()):
		(
			slots
			. append(
				{
					"slot_id": "slot-%d" % index,
					"run_id": "",
					"request_id": "",
					"source_row_id": "",
					"source_asset_id": "",
					"input_snapshot_id": "",
					"planned_size": [4, 4],
					"status": "succeeded",
					"asset_id": String(asset_ids[index]),
					"detached": false,
					"unexpected": false,
					"error": null,
				}
			)
		)
	return {
		"label": "Batch",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": slots,
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


func _graph_node_ids(graph_data: Dictionary) -> Array:
	var result := []
	for raw_node in graph_data.get("nodes", []):
		if raw_node is Dictionary:
			var node_data: Dictionary = raw_node
			result.append(String(node_data.get("id", "")))
	return result


func _item_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if item is Dictionary and String(item.get("id", "")) == item_id:
			return item
	return {}


func _image(color: Color) -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _delete_key_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_DELETE
	event.pressed = true
	return event


func _mouse_motion_event(position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	return event


func _right_click_event(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = position
	event.pressed = true
	return event
