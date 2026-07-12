# gdlint: disable=max-public-methods
extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
const Strings := preload("res://ui/shell/strings.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const StylePresetNodeScript := preload("res://core/graph/nodes/style_preset_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
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


func test_batch_card_header_collapse_is_persisted_and_undoable() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
	var expanded_height: float = card.get_canvas_bounds().size.y
	var collapse_button: Button = card.get_node("CollapseButton")
	collapse_button.pressed.emit()

	assert_true(card.collapsed)
	assert_lt(card.get_canvas_bounds().size.y, expanded_height)
	assert_true(canvas.export_canvas_data()["items"][0]["collapsed"])
	assert_true(UndoService.undo())
	assert_false(card.collapsed)
	assert_eq(card.get_canvas_bounds().size.y, expanded_height)
	assert_true(UndoService.redo())
	assert_true(card.collapsed)


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


func test_canvas_batch_card_filters_visible_review_subset() -> void:
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
	canvas._set_batch_review_state("batch_1", [ids[0]], CanvasBatchCardScript.REVIEW_KEEP, false)
	canvas._set_batch_review_state("batch_1", [ids[1]], CanvasBatchCardScript.REVIEW_REJECT, false)

	assert_true(
		canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.REVIEW_KEEP, false)
	)
	assert_eq(card.get_visible_asset_ids(), [ids[0]])
	assert_eq(canvas._get_batch_asset_ids("batch_1", true), [ids[0]])

	assert_true(
		canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.FILTER_PENDING, false)
	)
	assert_eq(card.get_visible_asset_ids(), [ids[2]])
	assert_true(card.toggle_asset_at_world(card.position + Vector2(20, 60)))
	assert_eq(card.get_selected_asset_ids(), [ids[2]])

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["review_filter"], CanvasBatchCardScript.FILTER_PENDING)


func test_canvas_batch_card_focuses_visible_review_thumbnails() -> void:
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

	var focus: Dictionary = canvas._focus_batch_relative("batch_1", 1, false)
	assert_eq(focus["asset_id"], ids[0])
	assert_eq(focus["index"], 1)
	assert_eq(focus["total"], 3)
	assert_eq(card._get_focus_asset_id(), ids[0])
	assert_eq(card.get_selected_asset_ids(), [ids[0]])

	focus = canvas._focus_batch_relative("batch_1", 1, false)
	assert_eq(focus["asset_id"], ids[1])
	assert_eq(card.get_selected_asset_ids(), [ids[1]])

	focus = canvas._focus_batch_relative("batch_1", -1, false)
	assert_eq(focus["asset_id"], ids[0])
	assert_eq(card.get_selected_asset_ids(), [ids[0]])

	canvas._set_batch_review_state("batch_1", [ids[0]], CanvasBatchCardScript.REVIEW_REJECT, false)
	assert_true(
		canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.FILTER_PENDING, false)
	)
	assert_eq(card._get_focus_asset_id(), "")

	focus = canvas._focus_batch_relative("batch_1", 1, false)
	assert_eq(focus["asset_id"], ids[1])
	assert_eq(focus["index"], 1)
	assert_eq(focus["total"], 2)

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["focus_asset_id"], ids[1])


func test_canvas_batch_card_switches_review_layout_for_focus_view() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids: Array[String] = []
	for index in range(20):
		ids.append(_register_asset(Color(float(index % 5) / 4.0, 0.25, 0.75), "asset_%d" % index))
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
	var contact_height: float = card.get_canvas_bounds().size.y

	assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_CONTACT)
	assert_true(
		canvas._set_batch_review_layout("batch_1", CanvasBatchCardScript.LAYOUT_FOCUS, false)
	)
	assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)
	assert_true(card.get_canvas_bounds().size.y < contact_height)
	assert_eq(card._focused_visible_asset_id(), ids[0])
	assert_eq(card.asset_index_at_world(card.position + card._focus_rect().get_center()), 0)
	assert_eq(card.asset_index_at_world(card.position + card._filmstrip_rect(3).get_center()), 3)

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["review_layout"], CanvasBatchCardScript.LAYOUT_FOCUS)


func test_canvas_batch_card_switches_semantic_lod_profiles() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	assert_eq(LODProfile.profile_for_camera_zoom(0.25), LODProfile.PROFILE_REVIEW)
	assert_eq(LODProfile.profile_for_camera_zoom(1.0), LODProfile.PROFILE_REVIEW)
	assert_eq(LODProfile.profile_for_camera_zoom(4.0), LODProfile.PROFILE_INSPECT)
	assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)

	card.set_lod_camera_zoom(0.25)
	assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)
	assert_eq(card.asset_index_at_world(card.position + Vector2(24, 64)), 0)

	card.set_lod_camera_zoom(4.0)
	assert_eq(card._get_lod_profile(), LODProfile.PROFILE_INSPECT)
	assert_false(card._asset_hint_for(ids[0]).is_empty())


func test_canvas_batch_card_keeps_previous_version_for_compare() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var before_ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var after_ids := [
		_register_asset(Color.GREEN, "green"),
		_register_asset(Color.YELLOW, "yellow"),
	]
	var card: Node = canvas._add_batch_card(before_ids, Vector2(16, 24), "Batch", "batch_1", false)

	canvas._replace_batch_asset_ids("batch_1", after_ids, false, before_ids)
	assert_eq(card.asset_ids, after_ids)
	assert_eq(card._get_compare_asset_ids(), before_ids)
	assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_CURRENT)
	assert_eq(card.get_visible_asset_ids(), after_ids)

	assert_true(
		canvas._set_batch_compare_mode("batch_1", CanvasBatchCardScript.COMPARE_PREVIOUS, false)
	)
	assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
	assert_eq(card._texture_asset_id_for(after_ids[0]), before_ids[0])
	assert_eq(card._texture_asset_id_for(after_ids[1]), before_ids[1])

	assert_true(
		canvas._set_batch_compare_mode("batch_1", CanvasBatchCardScript.COMPARE_SPLIT, false)
	)
	assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)
	assert_eq(card._texture_asset_id_for(after_ids[0]), after_ids[0])
	assert_eq(card._compare_asset_id_for(after_ids[0]), before_ids[0])

	var data: Dictionary = canvas.export_canvas_data()
	var item: Dictionary = data["items"][0]
	assert_eq(item["compare_asset_ids"], before_ids)
	assert_eq(item["compare_mode"], CanvasBatchCardScript.COMPARE_SPLIT)


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


func test_moving_graph_cards_updates_graph_positions_in_same_undo_action() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red")]
	var graph := GraphScript.new()
	graph.id = "graph_move_cards"
	graph.add_node(ObjectListNodeScript.new(), "objects", {"items": "barrel"}, Vector2(10, 20))
	graph.add_node(
		BatchNodeScript.new(),
		"batch_1",
		{"label": "Candidates", "asset_ids": ids},
		Vector2(300, 20)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	canvas._add_graph_node_card(graph.id, "objects", Vector2(10, 20), "objects_item", false)
	canvas._add_batch_card(
		ids, Vector2(300, 20), "Candidates", "batch_item", false, graph.id, "batch_1"
	)
	canvas.select_ids(["objects_item", "batch_item"])
	canvas.move_selected_by(Vector2(15, 25), true)

	var moved_graph: Dictionary = ProjectService.get_graph_data(graph.id)
	assert_eq(_node_position(moved_graph, "objects"), [25, 45])
	assert_eq(_node_position(moved_graph, "batch_1"), [315, 45])
	assert_true(UndoService.undo())
	var restored_graph: Dictionary = ProjectService.get_graph_data(graph.id)
	assert_eq(_node_position(restored_graph, "objects"), [10, 20])
	assert_eq(_node_position(restored_graph, "batch_1"), [300, 20])
	assert_true(UndoService.redo())
	assert_eq(_node_position(ProjectService.get_graph_data(graph.id), "objects"), [25, 45])


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


func test_graph_batch_card_persists_review_filter_in_graph_params() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var graph := GraphScript.new()
	graph.id = "graph_batch_filter_test"
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	canvas._set_batch_review_state(
		"node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
	)
	assert_true(
		canvas._set_batch_review_filter("node_item_1", CanvasBatchCardScript.REVIEW_FLAG, false)
	)
	assert_eq(card.get_visible_asset_ids(), [ids[1]])

	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_eq(batch_node["params"]["review_filter"], CanvasBatchCardScript.REVIEW_FLAG)

	var canvas_data: Dictionary = canvas.export_canvas_data()
	assert_false(Dictionary(canvas_data["items"][0]).has("review_filter"))

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)
	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]

	assert_eq(reloaded_card.get_review_filter(), CanvasBatchCardScript.REVIEW_FLAG)
	assert_eq(reloaded_card.get_visible_asset_ids(), [ids[1]])


func test_graph_batch_card_persists_focus_asset_id_in_graph_params() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var graph := GraphScript.new()
	graph.id = "graph_batch_focus_test"
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	var focus: Dictionary = canvas._focus_batch_relative("node_item_1", 1, false)
	assert_eq(focus["asset_id"], ids[0])
	assert_eq(card._get_focus_asset_id(), ids[0])

	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_eq(batch_node["params"]["focus_asset_id"], ids[0])

	var canvas_data: Dictionary = canvas.export_canvas_data()
	assert_false(Dictionary(canvas_data["items"][0]).has("focus_asset_id"))

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)
	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]

	assert_eq(reloaded_card._get_focus_asset_id(), ids[0])


func test_graph_batch_card_persists_review_layout_in_canvas_data() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var graph := GraphScript.new()
	graph.id = "graph_batch_layout_test"
	graph.add_node(
		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	assert_true(
		canvas._set_batch_review_layout("node_item_1", CanvasBatchCardScript.LAYOUT_FOCUS, false)
	)
	assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)

	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_false(batch_node["params"].has("review_layout"))

	var canvas_data: Dictionary = canvas.export_canvas_data()
	assert_eq(canvas_data["items"][0]["review_layout"], CanvasBatchCardScript.LAYOUT_FOCUS)

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)
	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]

	assert_eq(reloaded_card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)


func test_graph_batch_card_persists_compare_state_in_graph_params() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var before_ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var after_ids := [
		_register_asset(Color.GREEN, "green"),
		_register_asset(Color.YELLOW, "yellow"),
	]
	var graph := GraphScript.new()
	graph.id = "graph_batch_compare_test"
	graph.add_node(
		BatchNodeScript.new(),
		"batch_1",
		{"label": "Candidates", "asset_ids": before_ids},
		Vector2(16, 24)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var card: Node = canvas._add_batch_card(
		before_ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
	)
	canvas._replace_batch_asset_ids("node_item_1", after_ids, false, before_ids)
	assert_true(
		canvas._set_batch_compare_mode("node_item_1", CanvasBatchCardScript.COMPARE_SPLIT, false)
	)
	assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)

	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
	var batch_node: Dictionary = graph_data["nodes"][0]
	assert_eq(batch_node["params"]["asset_ids"], after_ids)
	assert_eq(batch_node["params"]["compare_asset_ids"], before_ids)
	assert_eq(batch_node["params"]["compare_mode"], CanvasBatchCardScript.COMPARE_SPLIT)

	var canvas_data: Dictionary = canvas.export_canvas_data()
	assert_false(Dictionary(canvas_data["items"][0]).has("compare_asset_ids"))
	assert_false(Dictionary(canvas_data["items"][0]).has("compare_mode"))

	var reloaded_canvas: Control = CanvasScript.new()
	reloaded_canvas.size = Vector2(512, 512)
	add_child_autofree(reloaded_canvas)
	await wait_process_frames(2)
	reloaded_canvas.load_canvas_data(canvas_data)
	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]

	assert_eq(reloaded_card.asset_ids, after_ids)
	assert_eq(reloaded_card._get_compare_asset_ids(), before_ids)
	assert_eq(reloaded_card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)


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


func test_object_node_card_exposes_content_and_emits_atomic_param_commit() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var graph := GraphScript.new()
	graph.id = "graph_content_card"
	graph.add_node(
		ObjectListNodeScript.new(), "objects", {"items": "barrel\ncrate"}, Vector2(24, 32)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var commits := []
	canvas.graph_node_params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			commits.append([graph_id, node_id, params])
	)

	var card: Node = canvas._add_graph_node_card(
		graph.id, "objects", Vector2(24, 32), "node_item_objects", false
	)
	var edit: TextEdit = card.get_content_control("ObjectEdit")
	var apply_button: Button = card.get_content_control("ApplyButton")

	assert_not_null(edit)
	assert_not_null(apply_button)
	assert_gt(card.get_canvas_bounds().size.y, 116.0)
	assert_eq(
		card.get_content_control("ItemCount").text,
		Strings.text("CONTENT_OBJECT_SELECTED_FORMAT") % [2, 2]
	)
	assert_eq(card.get_content_control("ObjectText0").text, "barrel")
	edit.text = "well"
	apply_button.pressed.emit()
	assert_eq(commits.size(), 1)
	assert_eq(commits[0][0], graph.id)
	assert_eq(commits[0][1], "objects")
	assert_eq(commits[0][2]["items"], "barrel\ncrate\nwell")
	assert_eq(commits[0][2]["rows"].size(), 3)
	assert_eq(commits[0][2]["rows"][2]["text"], "well")


func test_prompt_and_style_cards_show_real_content_and_prompt_emits_commit() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(800, 600)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var graph := GraphScript.new()
	graph.id = "graph_prompt_style_cards"
	graph.add_node(TextPromptNodeScript.new(), "prompt", {"text": "tiny windmill"}, Vector2(0, 0))
	(
		graph
		. add_node(
			StylePresetNodeScript.new(),
			"style",
			{
				"preset_ref": "embedded",
				"preset":
				{
					"name": "Farm DB32",
					"base_size": 32,
					"palette": {"ref": "db32"},
				},
			},
			Vector2(300, 0)
		)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var commits := []
	canvas.graph_node_params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			commits.append([graph_id, node_id, params])
	)
	var prompt_card: Node = canvas._add_graph_node_card(
		graph.id, "prompt", Vector2.ZERO, "prompt_item", false
	)
	var style_card: Node = canvas._add_graph_node_card(
		graph.id, "style", Vector2(300, 0), "style_item", false
	)

	var prompt_edit: TextEdit = prompt_card.get_content_control("PromptEdit")
	assert_eq(prompt_edit.text, "tiny windmill")
	prompt_edit.text = "tiny watermill"
	(prompt_card.get_content_control("ApplyButton") as Button).pressed.emit()
	assert_eq(commits, [[graph.id, "prompt", {"text": "tiny watermill"}]])
	assert_eq(style_card.get_content_control("StyleName").text, "Farm DB32")
	assert_eq(style_card.get_content_control("StyleDetail").text, "32 px base · Palette: db32")


func test_content_card_uses_structural_summary_only_at_ten_percent_overview() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var graph := GraphScript.new()
	graph.id = "graph_semantic_zoom"
	graph.add_node(TextPromptNodeScript.new(), "prompt", {"text": "tiny windmill"}, Vector2.ZERO)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "prompt", Vector2.ZERO, "prompt_item", false
	)
	assert_not_null(card.get_content_control("PromptEdit"))
	assert_eq(card.get_canvas_bounds().size, Vector2(240, 238))

	canvas.set_camera_zoom(0.1)
	assert_null(card.get_content_control("PromptEdit"))
	assert_eq(card.get_canvas_bounds().size, Vector2(220, 116))
	canvas.set_camera_zoom(1.0)
	assert_not_null(card.get_content_control("PromptEdit"))


func test_generate_content_card_routes_run_and_collapsed_state_roundtrips() -> void:
	ProjectService.current_project.manifest["style_preset"] = {
		"base_size": 32, "palette": {"ref": "db32"}
	}
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var graph := GraphScript.new()
	graph.id = "graph_generate_card"
	graph.add_node(
		AiGenerateNodeScript.new(),
		"generate",
		{"provider_id": "mock", "batch_size": 2, "seed": 7},
		Vector2(24, 32)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var actions := []
	canvas.graph_node_action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "generate", Vector2(24, 32), "node_item_generate", false
	)
	var run_button: Button = card.get_content_control("RunButton")
	var cancel_button: Button = card.get_content_control("CancelButton")

	assert_not_null(card.get_content_control("ProviderOption"))
	assert_eq(card.get_content_control("ProviderOption").get_item_text(0), "PixelForge Mock")
	assert_true(card.get_content_control("ModelCapabilities").text.contains("up to 16 images"))
	assert_eq(card.get_content_control("CostEstimate").text, "Estimated cost: $0.00")
	assert_eq(card.get_content_control("StyleSummary").text, "Style: 32 px · db32")
	assert_not_null(run_button)
	assert_not_null(cancel_button)
	assert_false(cancel_button.visible)
	run_button.pressed.emit()
	assert_eq(actions, [[graph.id, "generate", "run"]])

	card.set_execution_status("CONTENT_STATUS_RUNNING", "42% · rendering")
	assert_true(run_button.disabled)
	assert_true(cancel_button.visible)
	assert_eq(card._status_badge, Strings.text("CONTENT_STATUS_RUNNING"))
	assert_eq(card.get_content_control("ExecutionDetail").text, "42% · rendering")
	assert_eq(card.get_canvas_bounds().size, Vector2(280, 390))
	cancel_button.pressed.emit()
	assert_eq(actions, [[graph.id, "generate", "run"], [graph.id, "generate", "cancel"]])
	card.set_execution_status("CONTENT_STATUS_CANCELED", "Previous results preserved")
	assert_false(run_button.disabled)
	assert_false(cancel_button.visible)
	assert_eq(card._status_badge, Strings.text("CONTENT_STATUS_CANCELED"))
	assert_eq(card.get_content_control("ExecutionDetail").text, "Previous results preserved")
	assert_false(card.to_canvas_data().has("execution_status"))

	var collapse_button: Button = card.get_node("CollapseButton")
	collapse_button.pressed.emit()
	assert_true(card.collapsed)
	assert_eq(card.get_canvas_bounds().size, Vector2(220, 116))
	assert_null(card.get_content_control("RunButton"))
	assert_true(UndoService.undo())
	assert_false(card.collapsed)
	assert_not_null(card.get_content_control("RunButton"))
	assert_true(UndoService.redo())
	assert_true(card.collapsed)
	assert_true(card.to_canvas_data()["collapsed"])

	var collapsed_card: Node = (
		canvas
		. _add_node_direct(
			{
				"id": "node_item_collapsed",
				"type": "node",
				"graph_id": graph.id,
				"node_id": "generate",
				"position": [320, 32],
				"collapsed": true,
			}
		)
	)
	assert_eq(collapsed_card.get_canvas_bounds().size, Vector2(220, 116))
	assert_null(collapsed_card.get_content_control("RunButton"))
	var collapsed_data: Dictionary = collapsed_card.to_canvas_data()
	assert_true(collapsed_data["collapsed"])


func test_graph_node_card_marks_ghost_node_status() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	(
		ProjectService
		. set_graph_data(
			"graph_ghost",
			{
				"graph_version": 1,
				"id": "graph_ghost",
				"name": "Ghost",
				"nodes":
				[
					{
						"id": "plugin_1",
						"type": "missing.plugin_node",
						"params": {"seed": 7},
						"position": [0, 0],
					},
				],
				"edges": [],
			},
			false
		)
	)

	var node_card: Node = canvas._add_graph_node_card(
		"graph_ghost", "plugin_1", Vector2(24, 32), "node_item_ghost", false
	)

	assert_true(node_card._is_ghost)
	assert_eq(node_card._status_badge, Strings.GRAPH_NODE_BADGE_MISSING)
	assert_eq(node_card._summary, Strings.GRAPH_NODE_GHOST_SUMMARY)


func test_graph_cards_mark_loaded_invalid_edge_status() -> void:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)

	var ids := [_register_asset(Color.RED, "red")]
	var graph := GraphScript.new()
	graph.id = "graph_invalid_edge_badge"
	graph.add_node(ObjectListNodeScript.new(), "objects", {"items": "barrel"}, Vector2(24, 32))
	graph.add_node(
		BatchNodeScript.new(),
		"batch_1",
		{"label": "Candidates", "asset_ids": ids},
		Vector2(320, 32)
	)
	graph.edges.append({"from": ["objects", "items"], "to": ["batch_1", "in"]})
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var node_card: Node = canvas._add_graph_node_card(
		graph.id, "objects", Vector2(24, 32), "node_item_objects", false
	)
	var batch_card: Node = canvas._add_batch_card(
		ids, Vector2(320, 32), "Candidates", "node_item_batch", false, graph.id, "batch_1"
	)

	assert_true(node_card._has_edge_error)
	assert_eq(node_card._status_badge, Strings.GRAPH_NODE_BADGE_EDGE_ERROR)
	assert_true(batch_card._has_graph_edge_error)


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


func test_failed_batch_placeholder_keeps_expected_slots_and_routes_retry_remove() -> void:
	var graph := GraphScript.new()
	graph.id = "graph_batch_placeholder"
	(
		graph
		. add_node(
			BatchNodeScript.new(),
			"batch",
			{
				"label": "Cloud result",
				"asset_ids": [],
				"run_state":
				{
					"status": "failed",
					"expected_count": 5,
					"detail": "Recorded provider failure",
				},
			},
			Vector2.ZERO
		)
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(720, 520)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var actions := []
	canvas.batch_run_action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)
	var card: Node = canvas._add_batch_card(
		[], Vector2.ZERO, "Cloud result", "placeholder", false, graph.id, "batch"
	)
	assert_eq(card.run_state["expected_count"], 5)
	assert_gt(card.get_canvas_bounds().size.y, float(card.MIN_CARD_HEIGHT))
	assert_true(card._retry_button.visible)
	assert_true(card._remove_placeholder_button.visible)
	card._retry_button.pressed.emit()
	card._remove_placeholder_button.pressed.emit()
	assert_eq(actions, [[graph.id, "batch", "retry"], [graph.id, "batch", "remove"]])


func _register_asset(color: Color, name: String) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return AssetLibrary.register_image(image, name, {"origin": "imported"})


func _node_position(graph_data: Dictionary, node_id: String) -> Array:
	for node_value in graph_data.get("nodes", []):
		var node_data: Dictionary = node_value
		if String(node_data.get("id", "")) == node_id:
			return node_data.get("position", [])
	return []
