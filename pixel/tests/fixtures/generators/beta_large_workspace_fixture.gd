class_name PFBetaLargeWorkspaceFixture
extends RefCounted

const GRAPH_ID := "beta_large_graph"
const BRANCH_COUNT := 40
const NODES_PER_BRANCH := 5
const BRANCHES_PER_FRAME := 5


static func build() -> Dictionary:
	var nodes := []
	var edges := []
	var items := []
	for branch_index in range(BRANCH_COUNT):
		var column := branch_index % 5
		var row := branch_index / 5
		var base := Vector2(column * 1450, row * 760)
		var suffix := "%02d" % branch_index
		var ids := {
			"objects": "objects_%s" % suffix,
			"prompt": "prompt_%s" % suffix,
			"preset": "preset_%s" % suffix,
			"generate": "generate_%s" % suffix,
			"batch": "batch_%s" % suffix,
		}
		var branch_nodes := [
			_node(
				ids["objects"],
				"object_list",
				base,
				{
					"rows":
					[
						{"id": "tower", "text": "tower %s" % suffix, "count": 1, "enabled": true},
						{"id": "crate", "text": "crate %s" % suffix, "count": 1, "enabled": true},
					]
				}
			),
			_node(ids["prompt"], "text_prompt", base + Vector2(0, 300), {"text": "game asset"}),
			_node(
				ids["preset"],
				"prompt_preset",
				base + Vector2(300, 0),
				{
					"preset":
					{
						"prompt_preset_version": 1,
						"id": "prompt-fixture-%s" % suffix,
						"name": "Fixture prompt %s" % suffix,
						"prefix": "clean 16-bit pixel art",
					}
				}
			),
			_node(
				ids["generate"],
				"ai_generate",
				base + Vector2(620, 0),
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 1,
					"seed": 1000 + branch_index,
					"extra": {},
				}
			),
			_node(
				ids["batch"], "batch", base + Vector2(960, 0), _output_params("Branch %s" % suffix)
			),
		]
		for node in branch_nodes:
			var graph_node: Dictionary = node.duplicate(true)
			graph_node.erase("position")
			nodes.append(graph_node)
		(
			edges
			. append_array(
				[
					{"from": [ids["objects"], "subjects"], "to": [ids["generate"], "subjects"]},
					{"from": [ids["prompt"], "prompt"], "to": [ids["generate"], "prompt"]},
					{"from": [ids["preset"], "prefix"], "to": [ids["generate"], "prefix"]},
					{"from": [ids["generate"], "assets"], "to": [ids["batch"], "in"]},
				]
			)
		)
		var frame_id := "stage_%02d" % (branch_index / BRANCHES_PER_FRAME)
		for node in branch_nodes:
			(
				items
				. append(
					{
						"id": "%s_item" % node["id"],
						"type": "node",
						"graph_id": GRAPH_ID,
						"node_id": node["id"],
						"position": node["position"].duplicate(),
						"z_index": items.size() + 1,
						"collapsed": branch_index % 3 == 0,
						"frame_id": frame_id,
					}
				)
			)
	for frame_index in range(BRANCH_COUNT / BRANCHES_PER_FRAME):
		var row := frame_index
		(
			items
			. push_front(
				{
					"id": "stage_%02d" % frame_index,
					"type": "frame",
					"graph_id": GRAPH_ID,
					"title": "Production stage %02d" % frame_index,
					"color": "4f6f8fff" if frame_index % 2 == 0 else "76558fff",
					"position": [-48, row * 760 - 72],
					"size": [6880, 700],
					"z_index": -1,
				}
			)
		)
	return {
		"graphs":
		{
			GRAPH_ID:
			{
				"graph_version": 2,
				"id": GRAPH_ID,
				"name": "Beta 0.5 large workspace",
				"nodes": nodes,
				"edges": edges,
			}
		},
		"canvas": {"camera": {"center": [3400, 2700], "zoom": 0.1}, "items": items},
	}


static func _node(id: String, type: String, position: Vector2, params: Dictionary) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"position": [int(position.x), int(position.y)],
		"params": params,
	}


static func _output_params(label: String) -> Dictionary:
	return {
		"label": label,
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}
