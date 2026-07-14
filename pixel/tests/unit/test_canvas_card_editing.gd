extends "res://addons/gut/test.gd"

const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Beta 0.6 card editing")


func test_graph_card_defaults_are_contract_values_and_survive_lod() -> void:
	var expectations := {
		"text_prompt": Vector2(360, 300),
		"object_list": Vector2(400, 520),
		"prompt_preset": Vector2(320, 280),
		"pixel_cleanup": Vector2(420, 680),
		"image_input": Vector2(320, 380),
		"reference_set": Vector2(400, 480),
		"ai_generate": Vector2(400, 520),
	}
	for node_type in expectations:
		var card := _card(node_type, {})
		var expected: Vector2 = expectations[node_type]
		assert_eq(card.get_canvas_bounds().size, expected, node_type)
		card.set_lod_camera_zoom(0.1)
		assert_eq(card.get_canvas_bounds().size, expected, "%s at 10%%" % node_type)
		card.set_lod_camera_zoom(4.0)
		assert_eq(card.get_canvas_bounds().size, expected, "%s at 400%%" % node_type)


func test_graph_ports_follow_edit_lod_and_keep_a_forty_pixel_hit_target() -> void:
	var card := _card("text_prompt", {})
	var anchor: Vector2 = card.get_graph_port_anchor("prompt", false)
	for zoom in [0.1, 0.25, 0.5]:
		card.set_lod_camera_zoom(zoom)
		assert_true(card._graph_port_at_world(anchor).is_empty(), "hidden at %s" % zoom)
		assert_false(card.get_node("CollapseButton").visible)
		assert_false(card.get_node("TitleButton").visible)
		assert_false(card.get_node("MoreButton").visible)
	for zoom in [0.75, 1.0, 4.0]:
		card.set_lod_camera_zoom(zoom)
		var hit_radius: float = 20.0 / float(zoom)
		assert_eq(
			card._graph_port_at_world(anchor + Vector2(hit_radius * 0.99, 0))["port_name"], "prompt"
		)
		assert_true(card._graph_port_at_world(anchor + Vector2(hit_radius * 1.01, 0)).is_empty())
		assert_true(card.get_node("CollapseButton").visible)
		assert_true(card.get_node("TitleButton").visible)
		assert_true(card.get_node("MoreButton").visible)
	var title: Control = card.get_node("TitleButton")
	var collapse: Control = card.get_node("CollapseButton")
	var more: Control = card.get_node("MoreButton")
	assert_eq(title.mouse_filter, Control.MOUSE_FILTER_PASS)
	assert_gte(collapse.position.x - title.get_rect().end.x, 8.0)
	assert_gte(more.position.x - collapse.get_rect().end.x, 8.0)


func test_object_list_commit_keeps_replaced_content_in_tree_until_signal_finishes() -> void:
	var card := _card("object_list", {}, {"rows": [{"text": "crate", "count": 1, "enabled": true}]})
	var old_content: Control = card.get_node("Content")
	var old_line: LineEdit = card.get_content_control("ObjectText0")
	card.params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			var graph: Dictionary = ProjectService.get_graph_data(graph_id)
			for node_data in graph.get("nodes", []):
				if String(node_data.get("id", "")) != node_id:
					continue
				var merged: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
				merged.merge(params, true)
				node_data["params"] = merged
				break
			ProjectService.set_graph_data(graph_id, graph, true)
			card.refresh_from_graph()
	)

	old_line.text = "mossy crate"
	old_line.focus_exited.emit()

	var replacement: LineEdit = card.get_content_control("ObjectText0")
	var replacement_content: Control = card.get_node("Content")
	assert_true(is_instance_valid(old_content))
	assert_true(old_content.is_queued_for_deletion())
	assert_eq(old_content.get_parent(), card)
	assert_true(replacement_content.is_ancestor_of(replacement))
	assert_ne(replacement, old_line)
	assert_eq(replacement.text, "mossy crate")
	await wait_process_frames(1)
	assert_false(is_instance_valid(old_content))
	assert_false(is_instance_valid(old_line))


func test_all_title_buttons_pass_single_clicks_and_own_double_clicks() -> void:
	ProjectService.set_graph_data("graph_main", _graph_data("text_prompt"), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(800, 600)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var quick_add_requests := []
	var asset_edit_requests := []
	canvas.graph_quick_add_requested.connect(
		func(position: Vector2i) -> void: quick_add_requests.append(position)
	)
	canvas.asset_edit_requested.connect(
		func(asset_id: String, version_id: String) -> void:
			asset_edit_requests.append([asset_id, version_id])
	)
	var item_position := Vector2(-300, -220)

	var graph_card: Node = canvas._add_graph_node_card(
		"graph_main", "node", item_position, "graph_card", false
	)
	await _assert_title_input_contract(canvas, graph_card, quick_add_requests, asset_edit_requests)
	canvas._remove_item_direct(graph_card.item_id)

	ProjectService.set_graph_data("output_graph", _output_graph_data(), false)
	var batch_card: Node = canvas._add_graph_node_card(
		"output_graph", "output", item_position, "batch_card", false
	)
	await _assert_title_input_contract(canvas, batch_card, quick_add_requests, asset_edit_requests)
	canvas._remove_item_direct(batch_card.item_id)

	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var sprite_card: Node = canvas.add_sprite_item(image, "", item_position, "sprite_card", false)
	await _assert_title_input_contract(canvas, sprite_card, quick_add_requests, asset_edit_requests)
	canvas._remove_item_direct(sprite_card.item_id)

	var frame: Node = (
		canvas
		. _add_frame_direct(
			{
				"id": "frame",
				"type": "frame",
				"title": "Stage",
				"position": [item_position.x, item_position.y],
				"size": [640, 480],
			}
		)
	)
	await _assert_title_input_contract(canvas, frame, quick_add_requests, asset_edit_requests)


func test_display_title_and_requested_size_are_canvas_only_fields() -> void:
	var card := _card(
		"text_prompt", {"display_title": "  Forest\nProps\t ", "size": [512.4, 411.6]}
	)
	var graph_before: Dictionary = ProjectService.get_graph_data("graph_main")
	var data: Dictionary = card.to_canvas_data()

	assert_eq(data["display_title"], "Forest Props")
	assert_eq(data["size"], [512, 412])
	assert_eq(ProjectService.get_graph_data("graph_main"), graph_before)


func test_missing_and_invalid_card_fields_use_safe_contract_defaults() -> void:
	var missing := _card("text_prompt", {})
	assert_eq(missing.to_canvas_data()["size"], [360, 300])
	assert_false(missing.to_canvas_data().has("display_title"))

	var invalid := _card(
		"text_prompt", {"display_title": 42, "size": ["wide"], "unknown_beta_field": true}
	)
	var normalized: Dictionary = invalid.to_canvas_data()
	assert_eq(normalized["size"], [360, 300])
	assert_false(normalized.has("display_title"))
	assert_true(normalized["unknown_beta_field"])


func test_rename_and_resize_each_create_one_undo_without_changing_graph() -> void:
	var graph := _graph_data("text_prompt", {"text": ""})
	ProjectService.set_graph_data("graph_main", graph, false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	await wait_process_frames(1)
	var card: Node = canvas._add_graph_node_card("graph_main", "node", Vector2.ZERO, "item", false)
	var graph_before := ProjectService.get_graph_data("graph_main")

	assert_true(canvas._set_canvas_item_display_title("item", "Forest Props", true))
	assert_eq(card.display_title, "Forest Props")
	assert_true(UndoService.undo())
	assert_eq(card.display_title, "")
	assert_true(UndoService.redo())
	assert_eq(card.display_title, "Forest Props")

	card.set_requested_size(Vector2i(512, 412))
	assert_eq(card.requested_size, Vector2i(512, 412))
	card.set_requested_size(Vector2i(360, 300))
	assert_true(canvas._set_canvas_item_size("item", Vector2i(512, 412), true))
	assert_eq(card.requested_size, Vector2i(512, 412))
	assert_true(UndoService.undo())
	assert_eq(card.requested_size, Vector2i(360, 300))
	assert_true(UndoService.redo())
	assert_eq(card.requested_size, Vector2i(512, 412))
	assert_eq(ProjectService.get_graph_data("graph_main"), graph_before)


func test_prompt_preset_title_size_and_undo_use_generic_canvas_contract() -> void:
	var graph := _graph_data("prompt_preset", {})
	ProjectService.set_graph_data("graph_main", graph, false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	await wait_process_frames(1)
	var card: Node = canvas._add_graph_node_card(
		"graph_main", "node", Vector2.ZERO, "prompt-preset-item", false
	)
	assert_eq(card.requested_size, Vector2i(320, 280))
	assert_true(
		canvas._set_canvas_item_display_title("prompt-preset-item", "My style prompt", true)
	)
	assert_eq(card.display_title, "My style prompt")
	assert_true(UndoService.undo())
	assert_eq(card.display_title, "")
	assert_true(UndoService.redo())
	assert_eq(card.display_title, "My style prompt")
	assert_true(canvas._set_canvas_item_size("prompt-preset-item", Vector2i(10, 9999), true))
	assert_eq(card.requested_size, Vector2i(280, 1200))
	assert_true(UndoService.undo())
	assert_eq(card.requested_size, Vector2i(320, 280))
	assert_true(UndoService.redo())
	assert_eq(card.requested_size, Vector2i(280, 1200))
	for node in ProjectService.get_graph_data("graph_main")["nodes"]:
		assert_false(node.has("display_title"))
		assert_false(node.has("size"))


func test_title_and_size_roundtrip_through_project_without_graph_fields() -> void:
	var graph := _graph_data("text_prompt", {"text": ""})
	ProjectService.set_graph_data("graph_main", graph, false)
	(
		ProjectService
		. set_canvas_data(
			{
				"camera": {"center": [0, 0], "zoom": 1.0},
				"items":
				[
					{
						"id": "item",
						"type": "node",
						"graph_id": "graph_main",
						"node_id": "node",
						"position": [0, 0],
						"display_title": "Forest Props",
						"size": [512, 412],
					}
				],
			},
			false
		)
	)
	var path := "user://tests/beta06-card-fields.pxproj"
	assert_eq(ProjectService.save_project(path), OK)
	assert_eq(ProjectService.open_project(path), OK)
	var item: Dictionary = ProjectService.current_project.canvas["items"][0]
	assert_eq(item["display_title"], "Forest Props")
	assert_eq(item["size"], [512, 412])
	assert_false(ProjectService.get_graph_data("graph_main")["nodes"][0].has("display_title"))
	assert_false(ProjectService.get_graph_data("graph_main")["nodes"][0].has("size"))


func test_frame_title_and_size_use_one_undo_and_frozen_bounds() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	var frame: Node = (
		canvas
		. _add_frame_direct(
			{
				"id": "frame",
				"type": "frame",
				"graph_id": "graph_main",
				"title": "Stage",
				"position": [0, 0],
				"size": [640, 480],
			}
		)
	)
	assert_true(canvas._set_canvas_item_display_title("frame", "Final Stage", true))
	assert_eq(frame.title, "Final Stage")
	assert_true(UndoService.undo())
	assert_eq(frame.title, "Stage")
	assert_true(canvas._set_canvas_item_size("frame", Vector2i(120, 90000), true))
	assert_eq(frame.requested_size, Vector2i(320, 32768))
	assert_true(UndoService.undo())
	assert_eq(frame.requested_size, Vector2i(640, 480))
	frame.set_display_title("")
	assert_eq(frame._visible_title(), "Stage")
	LocalizationService.set_language("zh_CN")
	assert_eq(frame._visible_title(), "阶段")
	LocalizationService.set_language("en")
	assert_false(frame.to_canvas_data().has("locked"))
	var bounds: Rect2 = frame.get_canvas_bounds()
	assert_eq(frame.get_node("TitleButton").mouse_filter, Control.MOUSE_FILTER_PASS)
	for zoom in [0.1, 0.25, 0.5, 1.0, 4.0]:
		frame.set_lod_camera_zoom(zoom)
		assert_eq(frame.get_canvas_bounds(), bounds)


func _card(node_type: String, fields: Dictionary, params: Dictionary = {}) -> Node:
	var graph := _graph_data(node_type, params)
	ProjectService.set_graph_data("graph_main", graph, false)
	var data := {
		"id": "item",
		"type": "node",
		"graph_id": "graph_main",
		"node_id": "node",
		"position": [0, 0],
	}
	data.merge(fields, true)
	var card: Node = CanvasNodeCardScript.new()
	add_child_autofree(card)
	card.setup_from_data(data)
	return card


func _graph_data(node_type: String, params: Dictionary = {}) -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph_main",
		"name": "Cards",
		"nodes": [{"id": "node", "type": node_type, "params": params.duplicate(true)}],
		"edges": [],
	}


func _output_graph_data() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "output_graph",
		"name": "Output Card",
		"nodes":
		[
			{
				"id": "output",
				"type": "batch",
				"params":
				{
					"label": "Output",
					"source_node_id": "",
					"source_run_id": "",
					"role": "standalone",
					"input_snapshots": {},
					"request_records": [],
					"result_slots": [],
				},
			}
		],
		"edges": [],
	}


func _assert_title_input_contract(
	canvas: Control, item: Node, quick_add_requests: Array, asset_edit_requests: Array
) -> void:
	await wait_process_frames(1)
	var title: Button = item.get_node("TitleButton")
	assert_eq(title.mouse_filter, Control.MOUSE_FILTER_PASS)
	var local_position: Vector2 = canvas.world_to_screen(
		item.position + title.position + title.size * 0.5
	)
	canvas._clear_selection()
	_send_viewport_mouse_button(canvas, local_position, true)
	await wait_process_frames(1)
	assert_eq(canvas.get_selected_ids(), [item.item_id])
	assert_true(canvas._selection.is_dragging_items)
	_send_viewport_mouse_button(canvas, local_position, false)
	await wait_process_frames(1)
	assert_false(canvas._selection.is_dragging_items)

	canvas._clear_selection()
	quick_add_requests.clear()
	asset_edit_requests.clear()
	_send_viewport_mouse_button(canvas, local_position, true, true)
	await wait_process_frames(1)
	assert_true(item.get_node("TitleEdit").visible)
	assert_true(quick_add_requests.is_empty())
	assert_true(asset_edit_requests.is_empty())
	_send_viewport_mouse_button(canvas, local_position, false)


func _send_viewport_mouse_button(
	canvas: Control, local_position: Vector2, pressed: bool, double_click: bool = false
) -> void:
	var viewport_position := canvas.get_global_rect().position + local_position
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	event.position = viewport_position
	event.global_position = viewport_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
