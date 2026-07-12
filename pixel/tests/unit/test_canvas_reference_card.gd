extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")


func before_each() -> void:
	LocalizationService.set_language("en")
	ProjectService.new_project("Reference Card")


func test_reference_node_card_shows_preview_and_routes_asset_actions() -> void:
	var image := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var asset_id: String = AssetLibrary.register_image(
		image, "reference_name", {"origin": "imported"}
	)
	var graph := GraphScript.new()
	graph.id = "graph_reference_card"
	graph.add_node(ImageInputNodeScript.new(), "reference", {"asset_id": asset_id}, Vector2(24, 32))
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var commits := []
	var actions := []
	canvas.graph_node_params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			commits.append([graph_id, node_id, params])
	)
	canvas.graph_node_action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "reference", Vector2(24, 32), "node_item_reference", false
	)
	var preview: TextureRect = card.get_content_control("ReferencePreview")
	var detail: Label = card.get_content_control("ReferenceDetail")
	var field: Control = card.get_content_control("ReferenceField")
	assert_not_null(preview.texture)
	assert_string_contains(detail.text, "reference_name")
	field.set_value_and_emit("")
	assert_eq(commits, [[graph.id, "reference", {"asset_id": ""}]])
	(card.get_content_control("ImportButton") as Button).pressed.emit()
	assert_eq(actions, [[graph.id, "reference", "import_reference"]])


func test_reference_node_card_keeps_missing_id_and_shows_placeholder() -> void:
	var graph := GraphScript.new()
	graph.id = "graph_missing_reference"
	graph.add_node(
		ImageInputNodeScript.new(), "reference", {"asset_id": "missing-reference-id"}, Vector2.ZERO
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "reference", Vector2.ZERO, "missing_reference_card", false
	)
	assert_string_contains(card.get_content_control("ReferenceDetail").text, "missing-")
	assert_eq(card.get_content_control("ReferenceField").get_value(), "missing-reference-id")
