extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")


func before_each() -> void:
	get_tree().root.get_node("ProjectService").new_project("Hit Policy")


func test_canvas_hit_policy_prioritizes_batch_thumbnail_inside_review_card() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	var hit := _hit(canvas, card.position + Vector2(20, 60))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_left_click_on_batch_thumbnail_does_not_start_card_drag() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

	canvas._begin_left_interaction(canvas.world_to_screen(card.position + Vector2(20, 60)), false)

	assert_eq(canvas.get_selected_ids(), ["batch_1"])
	assert_eq(card.get_selected_asset_ids(), [ids[0]])
	assert_false(canvas._selection.is_dragging_items)


func test_canvas_hit_policy_keeps_batch_thumbnail_available_at_25_percent() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
	card.set_lod_camera_zoom(0.25)

	var hit := _hit(canvas, card.position + Vector2(20, 60))

	assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
	assert_eq(hit["item_id"], "batch_1")
	assert_eq(hit["asset_index"], 0)


func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
	var canvas: Control = _canvas()
	var ids := [_register_asset(Color.RED, "red")]
	canvas._add_batch_card(ids, Vector2.ZERO, "Batch", "batch_1", false)
	canvas.add_sprite_item(_image(Color.GREEN), "", Vector2.ZERO, "sprite_top", false)

	var hit := _hit(canvas, Vector2(2, 2))

	assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
	assert_eq(hit["item_id"], "sprite_top")


func test_canvas_hit_policy_reports_empty_space() -> void:
	var canvas: Control = _canvas()

	var hit := _hit(canvas, Vector2(2000, 2000))

	assert_eq(hit["kind"], HitPolicy.KIND_EMPTY)
	assert_eq(hit["item_id"], "")


func _canvas() -> Control:
	var canvas: Control = CanvasScript.new()
	canvas.size = Vector2(512, 512)
	add_child_autofree(canvas)
	return canvas


func _hit(canvas: Control, world_position: Vector2) -> Dictionary:
	return HitPolicy.hit_at_world(
		canvas.item_layer,
		world_position,
		CanvasBatchCardScript,
		CanvasItemSpriteScript,
		CanvasNodeCardScript
	)


func _register_asset(color: Color, name: String) -> String:
	return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})


func _image(color: Color) -> Image:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image
