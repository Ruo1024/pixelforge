extends "res://addons/gut/test.gd"

const Planner := preload("res://services/frame_run_planner.gd")


func test_frame_plan_includes_external_dependencies_and_excludes_unrelated_branches() -> void:
	var plan := Planner.plan(_graph(), _canvas(), "frame-stage")

	assert_true(plan["ok"])
	assert_eq(plan["target_generate_ids"], ["generate-a", "generate-b"])
	assert_eq(plan["result_count"], 9)
	assert_eq(plan["request_count"], 2)
	assert_eq(plan["known_cost"], 0.0)
	assert_has(plan["included_node_ids"], "shared-size")
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


func test_frame_target_missing_required_size_is_reported_but_other_target_runs() -> void:
	var graph := _graph()
	graph["edges"] = graph["edges"].filter(
		func(edge: Dictionary) -> bool:
			return not (edge["from"][0] == "shared-size" and edge["to"][0] == "generate-b")
	)
	var plan := Planner.plan(graph, _canvas(), "frame-stage")

	assert_true(plan["ok"])
	assert_eq(plan["target_generate_ids"], ["generate-a"])
	assert_eq(plan["invalid_targets"], [{"node_id": "generate-b", "reason": "missing_spec"}])


func _graph() -> Dictionary:
	return {
		"graph_version": 1,
		"id": "graph-main",
		"name": "Planner",
		"nodes":
		[
			{
				"id": "rows",
				"type": "object_list",
				"position": [0, 0],
				"params":
				{
					"items": "tower\nbarrel",
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
				"position": [0, 200],
				"params": {"items": "tree\nrock"}
			},
			{
				"id": "outside-prompt",
				"type": "text_prompt",
				"position": [-300, 0],
				"params": {"text": "shared"}
			},
			{
				"id": "shared-size",
				"type": "size_spec",
				"position": [300, 0],
				"params": {"width": 32, "height": 32, "per_subject": 1}
			},
			{
				"id": "generate-a",
				"type": "ai_generate",
				"position": [600, 0],
				"params":
				{"provider_id": "mock", "model_id": "pixel_mock_v1", "batch_size": 7, "seed": 1}
			},
			{
				"id": "generate-b",
				"type": "ai_generate",
				"position": [600, 240],
				"params":
				{"provider_id": "mock", "model_id": "pixel_mock_v1", "batch_size": 2, "seed": 2}
			},
			{
				"id": "unrelated-bad",
				"type": "image_input",
				"position": [1000, 800],
				"params": {"asset_id": "missing"}
			},
		],
		"edges":
		[
			{"from": ["rows", "items"], "to": ["generate-a", "items"]},
			{"from": ["legacy", "items"], "to": ["generate-b", "items"]},
			{"from": ["outside-prompt", "text"], "to": ["generate-a", "text"]},
			{"from": ["shared-size", "spec"], "to": ["generate-a", "spec"]},
			{"from": ["shared-size", "spec"], "to": ["generate-b", "spec"]},
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
