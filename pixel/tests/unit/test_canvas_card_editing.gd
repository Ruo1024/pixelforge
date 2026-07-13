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
		"style_preset": Vector2(320, 280),
		"size_spec": Vector2(320, 260),
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
	var anchor: Vector2 = card.get_graph_port_anchor("text", false)
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
			card._graph_port_at_world(anchor + Vector2(hit_radius * 0.99, 0))["port_name"], "text"
		)
		assert_true(card._graph_port_at_world(anchor + Vector2(hit_radius * 1.01, 0)).is_empty())
		assert_true(card.get_node("CollapseButton").visible)
		assert_true(card.get_node("TitleButton").visible)
		assert_true(card.get_node("MoreButton").visible)
	var title: Control = card.get_node("TitleButton")
	var collapse: Control = card.get_node("CollapseButton")
	var more: Control = card.get_node("MoreButton")
	assert_gte(collapse.position.x - title.get_rect().end.x, 8.0)
	assert_gte(more.position.x - collapse.get_rect().end.x, 8.0)


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
	var graph := _graph_data("text_prompt")
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


func test_title_and_size_roundtrip_through_project_without_graph_fields() -> void:
	var graph := _graph_data("text_prompt")
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
	for zoom in [0.1, 0.25, 0.5, 1.0, 4.0]:
		frame.set_lod_camera_zoom(zoom)
		assert_eq(frame.get_canvas_bounds(), bounds)


func _card(node_type: String, fields: Dictionary) -> Node:
	var graph := _graph_data(node_type)
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


func _graph_data(node_type: String) -> Dictionary:
	return {
		"graph_version": 1,
		"id": "graph_main",
		"name": "Cards",
		"nodes": [{"id": "node", "type": node_type, "position": [0, 0], "params": {}}],
		"edges": [],
	}
