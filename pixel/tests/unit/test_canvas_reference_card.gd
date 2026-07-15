extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")


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
	assert_eq(card._display_name, "reference_name")
	assert_string_contains(detail.text, "4×3")
	assert_eq(preview.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_false(field.visible)
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


func test_reference_set_card_uses_shared_large_media_grid_and_stable_asset_actions() -> void:
	var blue := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	blue.fill(Color.CORNFLOWER_BLUE)
	var red := Image.create(3, 4, false, Image.FORMAT_RGBA8)
	red.fill(Color.INDIAN_RED)
	var blue_id: String = AssetLibrary.register_image(blue, "blue", {"origin": "imported"})
	var red_id: String = AssetLibrary.register_image(red, "red", {"origin": "generated"})
	var graph := GraphScript.new()
	graph.id = "graph_reference_set_card"
	graph.add_node(
		ReferenceSetNodeScript.new(), "references", {"asset_ids": [blue_id, red_id]}, Vector2.ZERO
	)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(640, 520)
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
		graph.id, "references", Vector2.ZERO, "reference_set_card", false
	)
	await wait_process_frames(2)
	var grid: Control = card.get_content_control("ReferenceMediaGrid")
	assert_not_null(grid)
	assert_eq(grid.item_ids(), [blue_id, red_id])
	assert_eq(grid.loaded_texture_count(), 2)
	assert_true(grid.request_reorder(red_id, blue_id))
	assert_eq(commits[-1][2], {"asset_ids": [red_id, blue_id]})
	var red_tile := _tile_for_id(grid, red_id)
	var action_bar: Control = red_tile.get_node("Actions")
	red_tile.mouse_entered.emit()
	assert_true(action_bar.visible)
	red_tile.mouse_exited.emit()
	action_bar.mouse_entered.emit()
	await wait_process_frames(1)
	assert_true(
		action_bar.visible, "moving from a tile into its actions must not flicker them away"
	)
	assert_eq(
		(red_tile.get_node("Actions/Replace") as Button).mouse_filter, Control.MOUSE_FILTER_STOP
	)
	(red_tile.get_node("Actions/Replace") as Button).pressed.emit()
	assert_eq(actions[-1], [graph.id, "references", "replace_reference:1"])
	(red_tile.get_node("Actions/Remove") as Button).pressed.emit()
	assert_eq(commits[-1][2], {"asset_ids": [blue_id]})
	card.get_content_control("ReferenceSetAddField").set_value_and_emit(red_id)
	assert_eq(commits[-1][2], {"asset_ids": [blue_id, red_id, red_id]})
	var add_field: Control = card.get_content_control("ReferenceSetAddField")
	(add_field.find_child("ImportButton", true, false) as Button).pressed.emit()
	assert_eq(actions[-1], [graph.id, "references", "import_reference_set"])


func test_dragging_canvas_image_group_into_reference_set_appends_in_selection_order() -> void:
	var first_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	first_image.fill(Color.DARK_ORANGE)
	var second_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	second_image.fill(Color.DARK_SEA_GREEN)
	var first_asset := AssetLibrary.register_image(first_image, "first", {"origin": "imported"})
	var second_asset := AssetLibrary.register_image(second_image, "second", {"origin": "imported"})
	var graph := GraphScript.new()
	graph.id = "graph_reference_drop"
	graph.add_node(ReferenceSetNodeScript.new(), "references", {"asset_ids": []}, Vector2.ZERO)
	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(1200, 800)
	add_child_autofree(canvas)
	await wait_process_frames(2)
	var card: Node = canvas._add_graph_node_card(
		graph.id, "references", Vector2.ZERO, "reference_drop_card", false
	)
	var first: Node = canvas.add_sprite_item(
		first_image, first_asset, Vector2(-320, 0), "first_sprite", false
	)
	var second: Node = canvas.add_sprite_item(
		second_image, second_asset, Vector2(-240, 0), "second_sprite", false
	)
	canvas.select_ids([first.item_id, second.item_id])
	var before := {first.item_id: first.position, second.item_id: second.position}
	canvas._selection.start_drag(first.position, before)
	var commits := []
	canvas.graph_node_params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			commits.append([graph_id, node_id, params])
	)
	var drop_world: Vector2 = card.position + Vector2(120, 120)
	canvas._drag_selected_to(drop_world)
	canvas._finish_left_interaction(canvas.world_to_screen(drop_world))
	assert_eq(commits, [[graph.id, "references", {"asset_ids": [first_asset, second_asset]}]])
	assert_eq(first.position, before[first.item_id])
	assert_eq(second.position, before[second.item_id])
	assert_eq(canvas.get_selected_ids(), [card.item_id])


func _tile_for_id(grid: Control, item_id: String) -> Button:
	for child in grid.get_children():
		if child is Button and String(child.get_meta("item_id", "")) == item_id:
			return child
	return null
