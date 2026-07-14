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
		var preset_id := "preset_%s" % suffix
		var generate_id := "generate_%s" % suffix
		var batch_id := "batch_%s" % suffix
		var branch_nodes := [
			_node(
				prompt_id,
				"object_list",
				{
					"rows":
					_rows(["barrel", "fence"] if branch_index == 0 else ["well", "lantern"], 2)
				}
			),
			_node(reference_id, "image_input", {"asset_id": ""}),
			_node(
				preset_id, "prompt_preset", {"preset": _prompt_preset("prompt-fixture-%s" % suffix)}
			),
			_node(generate_id, "ai_generate", _generate_params(100 + branch_index)),
			_node(batch_id, "batch", _output_params("Branch %s results" % suffix.to_upper())),
		]
		nodes.append_array(branch_nodes)
		var positions := {
			prompt_id: [base_x, 0],
			reference_id: [base_x, 280],
			preset_id: [base_x + 280, 280],
			generate_id: [base_x + 560, 0],
			batch_id: [base_x + 860, 0],
		}
		(
			edges
			. append_array(
				[
					{"from": [prompt_id, "subjects"], "to": [generate_id, "subjects"]},
					{"from": [preset_id, "prefix"], "to": [generate_id, "prefix"]},
					{"from": [reference_id, "assets"], "to": [generate_id, "references"]},
					{"from": [generate_id, "assets"], "to": [batch_id, "in"]},
				]
			)
		)
		for node in branch_nodes:
			var node_id := String(node["id"])
			(
				items
				. append(
					{
						"id": "%s_item" % node_id,
						"type": "node",
						"graph_id": GRAPH_ID,
						"node_id": node_id,
						"position": positions[node_id].duplicate(),
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
				"graph_version": 2,
				"id": GRAPH_ID,
				"name": "Two branch workspace",
				"nodes": nodes,
				"edges": edges,
			}
		},
		"canvas": {"camera": {"center": [720, 180], "zoom": 0.5}, "items": items},
	}


static func _node(id: String, type: String, params: Dictionary) -> Dictionary:
	return {"id": id, "type": type, "params": params}


static func _rows(texts: Array, count: int) -> Array:
	var rows := []
	for index in range(texts.size()):
		(
			rows
			. append(
				{
					"id": "row-%d" % index,
					"text": String(texts[index]),
					"count": count,
					"enabled": true,
				}
			)
		)
	return rows


static func _prompt_preset(id: String) -> Dictionary:
	return {
		"prompt_preset_version": 1,
		"id": id,
		"name": "Fixture prompt",
		"prefix": "clean 16-bit pixel art",
	}


static func _generate_params(seed: int) -> Dictionary:
	return {
		"provider_id": "mock",
		"model_id": "pixel_mock_v1",
		"target_width": 32,
		"target_height": 32,
		"batch_size": 1,
		"seed": seed,
		"extra": {},
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
