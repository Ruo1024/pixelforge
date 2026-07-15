extends "res://addons/gut/test.gd"

const GridScript := preload("res://ui/canvas/media_tile_grid.gd")


func before_each() -> void:
	ProjectService.new_project("Media grid test")


func test_real_textures_are_loaded_only_for_visible_items_and_buffer() -> void:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color("#44aaff"))
	var asset_id: String = AssetLibrary.register_image(image, "generated-safe-tile")
	var items: Array[Dictionary] = []
	for index in range(50):
		(
			items
			. append(
				{
					"id": "item-%d" % index,
					"asset_id": asset_id,
					"status": "reference",
					"order_label": str(index + 1),
				}
			)
		)
	var grid := await _grid(items, Vector2(720, 456), true)
	assert_gt(grid.active_tile_count(), 0)
	assert_lt(grid.created_tile_count(), items.size())
	assert_lte(grid.created_tile_count(), 18)
	assert_eq(grid.loaded_texture_count(), 1)
	var preview: TextureRect = grid.get_child(0).get_node("Preview")
	assert_not_null(preview.texture)
	grid.set_scroll_offset(grid.max_scroll_offset())
	assert_eq(grid.visible_item_ids()[-1], "item-49")
	assert_lte(grid.active_tile_count(), 18)


func test_reorder_uses_stable_item_ids_and_wheel_stays_owned_at_boundaries() -> void:
	var items := [
		{"id": "asset-a", "asset_id": "", "status": "reference", "order_label": "1"},
		{"id": "asset-b", "asset_id": "", "status": "reference", "order_label": "2"},
		{"id": "asset-c", "asset_id": "", "status": "reference", "order_label": "3"},
	]
	var grid := await _grid(items, Vector2(720, 300), true)
	var requests := []
	grid.reorder_requested.connect(
		func(item_id: String, before_id: String) -> void: requests.append([item_id, before_id])
	)
	assert_true(grid.request_reorder("asset-c", "asset-a"))
	assert_eq(requests, [["asset-c", "asset-a"]])
	assert_false(grid.request_reorder("missing", "asset-a"))
	grid.set_scroll_offset(0)
	assert_true(grid.handle_wheel(1, false))
	grid.set_scroll_offset(grid.max_scroll_offset())
	assert_true(grid.handle_wheel(-1, false))
	assert_false(grid.handle_wheel(-1, true))


func _grid(items: Array, grid_size: Vector2, reorder: bool) -> Control:
	var grid: Control = GridScript.new()
	grid.size = grid_size
	add_child_autofree(grid)
	grid.configure_items(items, false, reorder, true)
	await wait_process_frames(2)
	return grid
