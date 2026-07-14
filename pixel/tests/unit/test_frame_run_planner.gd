extends "res://addons/gut/test.gd"

const Planner := preload("res://services/frame_run_planner.gd")


func test_frame_plan_includes_external_dependencies_and_excludes_unrelated_branches() -> void:
	var plan := Planner.plan(_graph(), _canvas(), "frame-stage")

	assert_true(plan["ok"])
	assert_eq(plan["target_generate_ids"], ["generate-a", "generate-b"])
	assert_eq(plan["result_count"], 9)
	assert_eq(plan["request_count"], 2)
	assert_eq(plan["known_cost"], 0.0)
	assert_has(plan["included_node_ids"], "outside-prompt")
	assert_does_not_have(plan["included_node_ids"], "unrelated-bad")


func test_frame_without_valid_generate_target_is_rejected_without_scope() -> void:
	var canvas := _canvas()
	for item in canvas["items"]:
		if item.get("node_id", "") in ["generate-a", "generate-b"]:
			item["frame_id"] = "other-frame"
	var plan := Planner.plan(_graph(), canvas, "frame-stage")

	assert_false(plan["ok"])
	assert_eq(plan["code"], "no_runnable_targets")
	assert_eq(plan["target_generate_ids"], [])


func test_frame_target_missing_required_prompt_is_reported_but_other_target_runs() -> void:
	var graph := _graph()
	graph["edges"] = graph["edges"].filter(
		func(edge: Dictionary) -> bool:
			return not (
				edge["to"][0] == "generate-b" and edge["from"][0] in ["outside-prompt", "legacy"]
			)
	)
	var plan := Planner.plan(graph, _canvas(), "frame-stage")

	assert_true(plan["ok"])
	assert_eq(plan["target_generate_ids"], ["generate-a"])
	assert_eq(plan["invalid_targets"], [{"node_id": "generate-b", "reason": "missing_prompt"}])


func _graph() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Planner",
		"nodes":
		[
			{
				"id": "rows",
				"type": "object_list",
				"params":
				{
					"rows":
					[
						{"id": "a", "text": "tower", "count": 2, "enabled": true},
						{"id": "b", "text": "barrel", "count": 3, "enabled": true},
						{"id": "off", "text": "well", "count": 10, "enabled": false}
					]
				}
			},
			{
				"id": "legacy",
				"type": "object_list",
				"params":
				{
					"rows":
					[
						{"id": "tree", "text": "tree", "count": 2, "enabled": true},
						{"id": "rock", "text": "rock", "count": 2, "enabled": true},
					]
				}
			},
			{"id": "outside-prompt", "type": "text_prompt", "params": {"text": "shared"}},
			{
				"id": "generate-a",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 7,
					"seed": 1,
					"extra": {}
				}
			},
			{
				"id": "generate-b",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 2,
					"seed": 2,
					"extra": {}
				}
			},
			{"id": "unrelated-bad", "type": "image_input", "params": {"asset_id": "missing"}},
		],
		"edges":
		[
			{"from": ["rows", "subjects"], "to": ["generate-a", "subjects"]},
			{"from": ["legacy", "subjects"], "to": ["generate-b", "subjects"]},
			{"from": ["outside-prompt", "prompt"], "to": ["generate-a", "prompt"]},
			{"from": ["outside-prompt", "prompt"], "to": ["generate-b", "prompt"]},
		],
	}


func _canvas() -> Dictionary:
	return {
		"camera": {"center": [0, 0], "zoom": 1.0},
		"items":
		[
			{
				"id": "frame-stage",
				"type": "frame",
				"graph_id": "graph-main",
				"position": [0, 0],
				"size": [1200, 700]
			},
			{
				"id": "item-rows",
				"type": "node",
				"graph_id": "graph-main",
				"node_id": "rows",
				"position": [0, 0],
				"frame_id": "frame-stage"
			},
			{
				"id": "item-legacy",
				"type": "node",
				"graph_id": "graph-main",
				"node_id": "legacy",
				"position": [0, 200],
				"frame_id": "frame-stage"
			},
			{
				"id": "item-a",
				"type": "node",
				"graph_id": "graph-main",
				"node_id": "generate-a",
				"position": [600, 0],
				"frame_id": "frame-stage"
			},
			{
				"id": "item-b",
				"type": "node",
				"graph_id": "graph-main",
				"node_id": "generate-b",
				"position": [600, 240],
				"frame_id": "frame-stage"
			},
		],
	}
