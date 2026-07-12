class_name PFBetaWorkspaceFixture
extends RefCounted

## Deterministic two-branch/two-stage project data for Beta 0.3–0.5 automation.

const GRAPH_ID := "beta_fixture_graph"


static func build() -> Dictionary:
	var nodes := []
	var edges := []
	var items := []
	for branch_index in range(2):
		var suffix := "a" if branch_index == 0 else "b"
		var base_x := branch_index * 920
		var prompt_id := "prompt_%s" % suffix
		var reference_id := "reference_%s" % suffix
		var size_id := "size_%s" % suffix
		var generate_id := "generate_%s" % suffix
		var batch_id := "batch_%s" % suffix
		(
			nodes
			. append_array(
				[
					{
						"id": prompt_id,
						"type": "object_list",
						"position": [base_x, 0],
						"params":
						{"items": "barrel\nfence" if branch_index == 0 else "well\nlantern"},
					},
					{
						"id": reference_id,
						"type": "image_input",
						"position": [base_x, 280],
						"params": {"asset_id": ""},
					},
					{
						"id": size_id,
						"type": "size_spec",
						"position": [base_x + 280, 0],
						"params": {"width": 32, "height": 32, "per_subject": 2},
					},
					{
						"id": generate_id,
						"type": "ai_generate",
						"position": [base_x + 560, 0],
						"params":
						{"provider_id": "mock", "batch_size": 2, "seed": 100 + branch_index},
					},
					{
						"id": batch_id,
						"type": "batch",
						"position": [base_x + 860, 0],
						"params":
						{"asset_ids": [], "label": "Branch %s results" % suffix.to_upper()},
					},
				]
			)
		)
		(
			edges
			. append_array(
				[
					{"from": [prompt_id, "items"], "to": [generate_id, "items"]},
					{"from": [size_id, "spec"], "to": [generate_id, "spec"]},
					{"from": [reference_id, "image"], "to": [generate_id, "image"]},
					{"from": [generate_id, "images"], "to": [batch_id, "in"]},
				]
			)
		)
		for node in nodes.slice(branch_index * 5, branch_index * 5 + 5):
			var node_id := String(node["id"])
			(
				items
				. append(
					{
						"id": "%s_item" % node_id,
						"type": "node",
						"graph_id": GRAPH_ID,
						"node_id": node_id,
						"position": node["position"].duplicate(),
						"z_index": items.size() + 1,
						"collapsed": false,
						"frame_id": "stage_%s" % suffix,
					}
				)
			)

	items.push_front(_frame("stage_b", "Variation stage", "76558fff", Vector2(888, -64)))
	items.push_front(_frame("stage_a", "Reference stage", "4f6f8fff", Vector2(-32, -64)))
	return {
		"manifest_name": "Beta workspace fixture",
		"graphs":
		{
			GRAPH_ID:
			{
				"graph_version": 1,
				"id": GRAPH_ID,
				"name": "Two branch workspace",
				"nodes": nodes,
				"edges": edges,
			}
		},
		"canvas": {"camera": {"center": [720, 180], "zoom": 0.5}, "items": items},
	}


static func _frame(frame_id: String, title: String, color: String, position: Vector2) -> Dictionary:
	return {
		"id": frame_id,
		"type": "frame",
		"graph_id": GRAPH_ID,
		"title": title,
		"color": color,
		"position": [int(position.x), int(position.y)],
		"size": [880, 640],
		"z_index": -1,
	}
