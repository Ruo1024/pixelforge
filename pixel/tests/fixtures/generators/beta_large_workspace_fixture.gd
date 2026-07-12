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
			"style": "style_%s" % suffix,
			"size": "size_%s" % suffix,
			"generate": "generate_%s" % suffix,
			"batch": "batch_%s" % suffix,
		}
		var branch_nodes := [
			_node(
				ids["objects"],
				"object_list",
				base,
				{"items": "tower %s\ncrate %s" % [suffix, suffix]}
			),
			_node(
				ids["style"],
				"style_preset",
				base + Vector2(0, 300),
				{"preset_ref": "embedded", "preset": {}}
			),
			_node(
				ids["size"],
				"size_spec",
				base + Vector2(300, 0),
				{"width": 32, "height": 32, "per_subject": 1}
			),
			_node(
				ids["generate"],
				"ai_generate",
				base + Vector2(620, 0),
				{
					"provider_id": "mock",
					"model_id": "pixel_mock_v1",
					"batch_size": 1,
					"seed": 1000 + branch_index
				}
			),
			_node(
				ids["batch"],
				"batch",
				base + Vector2(960, 0),
				{"label": "Branch %s" % suffix, "asset_ids": []}
			),
		]
		nodes.append_array(branch_nodes)
		(
			edges
			. append_array(
				[
					{"from": [ids["objects"], "items"], "to": [ids["generate"], "items"]},
					{"from": [ids["style"], "style"], "to": [ids["generate"], "style"]},
					{"from": [ids["size"], "spec"], "to": [ids["generate"], "spec"]},
					{"from": [ids["generate"], "images"], "to": [ids["batch"], "in"]},
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
				"graph_version": 1,
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
