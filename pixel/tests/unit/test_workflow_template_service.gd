extends "res://addons/gut/test.gd"

const Service := preload("res://services/workflow_template_service.gd")
const FileIO := preload("res://infra/file_io.gd")

var _saved_ids: Array[String] = []


func after_each() -> void:
	for template_id in _saved_ids:
		Service.delete_template(template_id)
	_saved_ids.clear()


func test_capture_filters_external_edges_and_clears_assets_and_results() -> void:
	var graph := _graph_fixture()
	var canvas := _canvas_fixture()
	var result := Service.build_from_frame("Reusable stage", graph, canvas, "frame-a")

	assert_true(result.get("ok", false), JSON.stringify(result))
	assert_eq(result["external_edge_count"], 1)
	var template: Dictionary = result["template"]
	assert_eq(template["edges"].size(), 3)
	assert_eq(template["requirements"]["reference_slots"], 1)
	assert_eq(_node(template, "reference")["params"]["asset_id"], "")
	assert_eq(_node(template, "batch")["params"], {"label": "Results"})
	assert_eq(_node(template, "prompt")["display_title"], "Ideas")
	assert_eq(_node(template, "prompt")["size"], [420, 320])
	assert_false(JSON.stringify(template).contains("asset-reference"))


func test_capture_rejects_unknown_nodes_params_sensitive_fields_and_paths() -> void:
	var graph := _graph_fixture()
	var canvas := _canvas_fixture()
	_node(graph, "prompt")["params"]["unexpected"] = true
	assert_eq(
		Service.build_from_frame("Bad", graph, canvas, "frame-a")["code"], "unknown_template_param"
	)

	graph = _graph_fixture()
	_node(graph, "prompt")["type"] = "plugin.custom"
	assert_eq(
		Service.build_from_frame("Bad", graph, canvas, "frame-a")["code"],
		"unsupported_template_node"
	)

	graph = _graph_fixture()
	_node(graph, "prompt")["params"]["api_token"] = "hidden"
	assert_eq(
		Service.build_from_frame("Bad", graph, canvas, "frame-a")["code"], "unsafe_template_value"
	)

	graph = _graph_fixture()
	_node(graph, "prompt")["params"]["text"] = "/Users/example/private.png"
	assert_eq(
		Service.build_from_frame("Bad", graph, canvas, "frame-a")["code"], "unsafe_template_value"
	)


func test_template_storage_is_atomic_and_corrupt_files_do_not_block_listing() -> void:
	var template: Dictionary = Service.builtin_templates()[0].duplicate(true)
	template["id"] = "test-template-storage"
	template["name"] = "Saved workflow"
	_saved_ids.append(template["id"])
	assert_true(Service.save_template(template)["ok"])
	assert_eq(Service.load_template(template["id"])["template"]["name"], "Saved workflow")
	assert_true(Service.rename_template(template["id"], "Renamed workflow")["ok"])

	var corrupt_id := "test-template-corrupt"
	_saved_ids.append(corrupt_id)
	assert_eq(
		FileIO.atomic_write(
			"user://workflow_templates/%s.json" % corrupt_id, PackedByteArray([1, 2, 3])
		),
		OK
	)
	var listed := Service.list_templates("workflow")
	assert_true(
		listed["templates"].any(
			func(item: Dictionary) -> bool: return item["name"] == "Renamed workflow"
		)
	)
	assert_true(
		listed["warnings"].any(
			func(item: Dictionary) -> bool: return item["file"] == "%s.json" % corrupt_id
		)
	)


func test_builtins_validate_and_instantiate_remaps_all_ids_and_positions() -> void:
	var builtins := Service.builtin_templates()
	assert_eq(builtins.size(), 4)
	for template in builtins:
		assert_true(Service.validate_template(template)["ok"])
	var graph := {"graph_version": 1, "id": "graph-main", "name": "Main", "nodes": [], "edges": []}
	var canvas := {"camera": {"center": [0, 0], "zoom": 1.0}, "items": []}
	var first := Service.instantiate(builtins[0], graph, canvas, Vector2(500, 300))
	var second := Service.instantiate(builtins[0], graph, canvas, Vector2(500, 300))

	assert_true(first["ok"])
	assert_ne(first["frame_id"], second["frame_id"])
	assert_ne(first["node_id_map"], second["node_id_map"])
	assert_eq(first["graph"]["nodes"][0]["position"], [540, 380])
	var first_node_id := String(first["graph"]["nodes"][0]["id"])
	var canvas_node := _canvas_node(first["canvas"], first_node_id)
	assert_eq(canvas_node["position"], [540, 380])
	assert_eq(canvas_node["frame_id"], first["frame_id"])
	assert_eq(canvas_node["size"], builtins[0]["nodes"][0]["size"])
	assert_eq(first["graph"]["edges"][0]["from"][0], first_node_id)
	assert_eq(builtins[0]["nodes"][0]["id"], "prompt")


func test_invalid_edge_port_and_future_version_fail_closed() -> void:
	var template: Dictionary = Service.builtin_templates()[0].duplicate(true)
	template["edges"][0]["from"][1] = "unknown"
	assert_eq(Service.validate_template(template)["code"], "invalid_template_edge")
	template = Service.builtin_templates()[0].duplicate(true)
	template["version"] = 3
	assert_eq(Service.validate_template(template)["code"], "unsupported_template_version")


func _graph_fixture() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Main",
		"nodes":
		[
			{
				"id": "outside",
				"type": "text_prompt",
				"position": [0, 0],
				"params": {"text": "outside"}
			},
			{
				"id": "prompt",
				"type": "text_prompt",
				"position": [120, 120],
				"params": {"text": "tower"}
			},
			{
				"id": "reference",
				"type": "image_input",
				"position": [120, 300],
				"params": {"asset_id": "asset-reference"}
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"position": [480, 120],
				"params":
					{
						"provider_id": "openai_image",
						"model_id": "gpt-image-2",
						"target_width": 64,
						"target_height": 64,
						"batch_size": 1,
						"seed": -1,
						"extra": {"quality": "low"},
					}
			},
			{
				"id": "batch",
				"type": "batch",
				"position": [820, 120],
				"params":
				{
					"label": "Results",
					"source_node_id": "generate",
					"source_run_id": "run-template",
					"role": "current",
					"input_snapshots": {},
					"request_records": [],
					"result_slots": [
						{
							"status": "succeeded",
							"detached": false,
							"asset_id": "generated-output",
						}
					],
				}
			},
		],
		"edges":
		[
			{"from": ["prompt", "prompt"], "to": ["generate", "prompt"]},
			{"from": ["reference", "assets"], "to": ["generate", "references"]},
			{"from": ["generate", "assets"], "to": ["batch", "in"]},
			{"from": ["outside", "prompt"], "to": ["generate", "prompt"]},
		],
	}


func _canvas_fixture() -> Dictionary:
	var items := [
		{
			"id": "frame-a",
			"type": "frame",
			"graph_id": "graph-main",
			"title": "Stage",
			"color": "4f6f8fff",
			"position": [80, 80],
			"size": [1200, 560]
		},
		{
			"id": "item-outside",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "outside",
			"position": [0, 0],
			"frame_id": null
		},
	]
	for node_id in ["prompt", "reference", "generate", "batch"]:
		var node := _node(_graph_fixture(), node_id)
		items.append(
			{
				"id": "item-%s" % node_id,
				"type": "node",
				"graph_id": "graph-main",
				"node_id": node_id,
				"position": node["position"],
				"frame_id": "frame-a"
			}
		)
		if node_id == "prompt":
			items[items.size() - 1]["display_title"] = "Ideas"
			items[items.size() - 1]["size"] = [420, 320]
	return {"camera": {"center": [0, 0], "zoom": 1.0}, "items": items}


func _node(container: Dictionary, node_id: String) -> Dictionary:
	var nodes: Array = container.get("nodes", [])
	for node in nodes:
		if String(node.get("id", "")) == node_id:
			return node
	return {}


func _canvas_node(canvas: Dictionary, node_id: String) -> Dictionary:
	for item in canvas.get("items", []):
		if String(item.get("node_id", "")) == node_id:
			return item
	return {}
