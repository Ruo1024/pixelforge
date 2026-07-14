extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const CleanupNodeScript := preload("res://core/graph/nodes/pixel_cleanup_node.gd")


func before_each() -> void:
	ProjectService.new_project("Cleanup v2 shell")
	AssetLibrary.clear()


func test_shell_only_saves_settings_and_never_executes() -> void:
	var settings: Dictionary = CleanupNodeScript.DEFAULT_SETTINGS.duplicate(true)
	settings["quantize"]["palette_id"] = "db16"
	var params := {"preset_id": "cleanup-user-shell", "settings": settings}
	var graph := GraphScript.new()
	graph.id = "graph-cleanup-shell"
	assert_false(
		graph.add_node(CleanupNodeScript.new(), "cleanup", params, Vector2.ZERO).is_empty()
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)

	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(900, 700)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var actions: Array = []
	canvas.graph_node_action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "cleanup", Vector2.ZERO, "item-cleanup", false
	)
	await wait_process_frames(2)

	assert_eq(card.get_content_control("CleanupPresetId").text, "cleanup-user-shell")
	assert_true(card.get_content_control("CleanupSettingsSnapshot").text.contains("db16"))
	assert_null(card.get_content_control("PrimaryActionButton"))
	assert_eq(actions, [])
	assert_true(AssetLibrary.get_all_meta().is_empty())
	assert_eq(ProjectService.get_graph_data(graph.id)["nodes"][0]["params"], params)
