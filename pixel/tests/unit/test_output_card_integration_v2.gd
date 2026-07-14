extends "res://addons/gut/test.gd"

const PRODUCTION_SURFACES := [
	"res://ui/canvas/canvas_batch_card.gd",
	"res://ui/canvas/infinite_canvas.gd",
	"res://ui/canvas/canvas_batch_ops.gd",
	"res://ui/canvas/canvas_graph_item_bridge.gd",
	"res://ui/shell/m2_1_ui_controller.gd",
]

const RETIRED_SYMBOLS := [
	"review_states",
	"review_filter",
	"review_layout",
	"focus_asset_id",
	"compare_asset_ids",
	"compare_mode",
	"_split_batch_selection",
	"_split_batch_marked",
]


func test_output_host_is_graph_bound_and_uses_the_v2_controller() -> void:
	var card_source := FileAccess.get_file_as_string(PRODUCTION_SURFACES[0])
	assert_true(card_source.contains("output_card_controller.gd"))
	assert_true(card_source.contains("PFOutputCardController"))
	assert_false(card_source.contains('"type": "batch_card"'))
	assert_false(card_source.contains('else "batch_card"'))


func test_detach_is_one_canvas_undo_with_stable_origin_identity() -> void:
	var canvas_source := FileAccess.get_file_as_string(PRODUCTION_SURFACES[1])
	assert_true(canvas_source.contains("detach_output_slot"))
	assert_true(canvas_source.contains("detach_all_output_assets"))
	assert_true(canvas_source.contains("UndoService.perform_action"))
	assert_true(canvas_source.contains("origin_graph_id"))
	assert_true(canvas_source.contains("origin_batch_node_id"))
	assert_true(canvas_source.contains("origin_slot_id"))


func test_retired_review_and_standalone_batch_symbols_are_absent() -> void:
	for path in PRODUCTION_SURFACES:
		var source := FileAccess.get_file_as_string(path)
		for symbol in RETIRED_SYMBOLS:
			assert_false(source.contains(symbol), "%s still contains %s" % [path, symbol])
	var canvas_source := FileAccess.get_file_as_string(PRODUCTION_SURFACES[1])
	assert_false(canvas_source.contains('item_type == "batch_card"'))
	assert_false(canvas_source.contains('String(data.get("type", "")) == "batch_card"'))


func test_output_canvas_data_roundtrip_keeps_only_graph_identity() -> void:
	var card_source := FileAccess.get_file_as_string(PRODUCTION_SURFACES[0])
	assert_true(card_source.contains('"graph_id"'))
	assert_true(card_source.contains('"node_id"'))
	assert_false(card_source.contains('result["asset_ids"]'))
	assert_false(card_source.contains('result["selected_asset_ids"]'))
