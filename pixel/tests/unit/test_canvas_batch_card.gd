extends "res://addons/gut/test.gd"

const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")


func before_each() -> void:
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


func _register_asset(color: Color, name: String) -> String:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return AssetLibrary.register_image(image, name, {"origin": "imported"})
