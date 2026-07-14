extends "res://addons/gut/test.gd"

const BatchNode := preload("res://core/graph/nodes/batch_node.gd")


func test_visible_projection_is_succeeded_not_detached_and_stable() -> void:
	var params := {
		"result_slots": [
			{"slot_id": "q", "status": "queued", "detached": false},
			{"slot_id": "a", "status": "succeeded", "asset_id": "asset-a", "detached": false},
			{"slot_id": "f", "status": "failed", "asset_id": "asset-f", "detached": false},
			{"slot_id": "b", "status": "succeeded", "asset_id": "asset-b", "detached": true},
			{"slot_id": "c", "status": "succeeded", "asset_id": "asset-c", "detached": false, "unexpected": true},
			{"slot_id": "x", "status": "canceled", "detached": false},
		]
	}
	assert_eq(BatchNode.get_visible_asset_ids(params), ["asset-a", "asset-c"])


func test_batch_params_have_no_asset_ids_compatibility_field() -> void:
	var node := BatchNode.new()
	var validated := node.validate_params(
		{
			"label": "Output",
			"asset_ids": ["legacy"],
			"result_slots": [
				{"status": "succeeded", "asset_id": "current", "detached": false}
			],
		}
	)
	assert_false(validated.has("asset_ids"))
	assert_eq(node.execute({}, validated, null)["assets"], ["current"])
