extends "res://addons/gut/test.gd"

const BoardScript := preload("res://core/board/pf_board.gd")
const Blob := preload("res://core/board/terrain_blob.gd")
const GroupScript := preload("res://core/board/terrain_group.gd")
const BrushScript := preload("res://core/board/terrain_brush.gd")


func test_all_256_masks_normalize_to_exactly_47_valid_roles() -> void:
	var normalized := {}
	for mask in range(256):
		var value := Blob.normalize_47(mask)
		normalized[value] = true
		assert_between(Blob.role_47(mask), 0, 46)
	assert_eq(normalized.size(), 47)
	for mask in range(256):
		assert_between(Blob.role_16(mask), 0, 15)


func test_u_shape_and_erase_recompute_neighbor_roles() -> void:
	var board := BoardScript.new("Lake", 6, 6, 16)
	var layer_id := board.add_layer("Water", PFBoard.LAYER_TILE)
	var group := GroupScript.new()
	group.mode = 16
	for role in range(16):
		group.roles[str(role)] = ["role_%d" % role]
	var brush := BrushScript.new()
	var shape := [
		Vector2i(1, 1),
		Vector2i(1, 2),
		Vector2i(1, 3),
		Vector2i(2, 3),
		Vector2i(3, 3),
		Vector2i(3, 2),
		Vector2i(3, 1),
	]
	for cell in shape:
		assert_true(brush.paint(board, layer_id, cell, group)["ok"])
	_assert_roles_match_neighbors(board.get_layer(layer_id)["cells"])
	assert_true(brush.paint(board, layer_id, Vector2i(1, 2), group, true)["ok"])
	assert_false(board.get_layer(layer_id)["cells"].has("1,2"))
	_assert_roles_match_neighbors(board.get_layer(layer_id)["cells"])


func test_missing_role_falls_back_and_variant_hash_is_stable() -> void:
	var group := GroupScript.new()
	group.roles["0"] = ["a", "b", "c"]
	var first := group.choose_asset(15, Vector2i(4, 9))
	var second := group.choose_asset(15, Vector2i(4, 9))
	assert_true(first["fallback"])
	assert_eq(first, second)


func _assert_roles_match_neighbors(cells: Dictionary) -> void:
	for key in cells.keys():
		var cell := PFBoard.parse_cell_key(String(key))
		var expected := Blob.role_16(Blob.neighbor_mask(cells, cell))
		assert_eq(int(cells[key]["terrain_role"]), expected)
		assert_eq(String(cells[key]["asset_id"]), "role_%d" % expected)
