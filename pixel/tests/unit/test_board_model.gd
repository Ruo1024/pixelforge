extends "res://addons/gut/test.gd"

const BoardScript := preload("res://core/board/pf_board.gd")


func test_board_layers_cells_items_and_roundtrip_are_stable() -> void:
	var board := BoardScript.new("Farm", 60, 40, 16)
	var terrain := board.add_layer("Terrain", PFBoard.LAYER_TILE)
	var props := board.add_layer("Props", PFBoard.LAYER_FREE)
	for index in range(200):
		assert_true(board.set_cell(terrain, Vector2i(index % 60, index / 60), "tile_%d" % index))
	for index in range(30):
		assert_false(
			board.add_free_item(props, "prop_%d" % index, Vector2i(index * 3, index * 2)).is_empty()
		)
	assert_true(board.set_layer_visuals(props, false, 0.45, "multiply"))
	assert_true(board.move_layer(props, 0))
	board.extra["future_board_field"] = {"kept": true}

	var loaded := BoardScript.from_json(board.to_json())
	assert_eq(loaded.grid, board.grid)
	assert_eq(loaded.layers, board.layers)
	assert_eq(loaded.get_layer(terrain)["cells"].size(), 200)
	assert_eq(loaded.get_layer(props)["items"].size(), 30)
	assert_eq(loaded.get_referenced_asset_ids().size(), 230)
	assert_eq(loaded.to_json()["future_board_field"], {"kept": true})


func test_board_rejects_out_of_bounds_and_invalid_layer_operations() -> void:
	var board := BoardScript.new("Small", 2, 2, 16)
	var layer_id := board.add_layer("Terrain", PFBoard.LAYER_TILE)
	assert_false(board.set_cell(layer_id, Vector2i(2, 0), "outside"))
	assert_false(board.set_cell("missing", Vector2i.ZERO, "missing"))
	assert_eq(board.add_free_item(layer_id, "asset", Vector2i.ZERO), "")
	assert_false(board.set_layer_visuals("missing", true, 1.0, "normal"))
