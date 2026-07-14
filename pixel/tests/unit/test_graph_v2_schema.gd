extends "res://addons/gut/test.gd"

const Graph := preload("res://core/graph/pf_graph.gd")
const NodeRegistry := preload("res://core/graph/node_registry.gd")

const MAIN_PATH_TYPES := [
	"ai_generate",
	"batch",
	"image_input",
	"object_list",
	"pixel_cleanup",
	"prompt_preset",
	"reference_set",
	"text_prompt",
]
const PORT_TYPES := ["asset_list", "prompt_prefix", "subject_list", "text"]
const EXPECTED_NODES := {
	"text_prompt":
	{
		"category": "input",
		"inputs": [],
		"outputs": [{"name": "prompt", "type": "text"}],
	},
	"object_list":
	{
		"category": "input",
		"inputs": [],
		"outputs": [{"name": "subjects", "type": "subject_list"}],
	},
	"prompt_preset":
	{
		"category": "input",
		"inputs": [],
		"outputs": [{"name": "prefix", "type": "prompt_prefix"}],
	},
	"image_input":
	{
		"category": "input",
		"inputs": [],
		"outputs": [{"name": "assets", "type": "asset_list"}],
	},
	"reference_set":
	{
		"category": "input",
		"inputs": [],
		"outputs": [{"name": "assets", "type": "asset_list"}],
	},
	"ai_generate":
	{
		"category": "generate",
		"inputs":
		[
			{"name": "prefix", "type": "prompt_prefix", "required": false},
			{"name": "prompt", "type": "text", "required": false},
			{"name": "subjects", "type": "subject_list", "required": false},
			{"name": "references", "type": "asset_list", "required": false},
		],
		"outputs": [{"name": "assets", "type": "asset_list"}],
	},
	"pixel_cleanup":
	{
		"category": "process",
		"inputs": [{"name": "assets", "type": "asset_list", "required": true}],
		"outputs": [{"name": "assets", "type": "asset_list"}],
	},
	"batch":
	{
		"category": "container",
		"inputs": [{"name": "in", "type": "asset_list", "required": false}],
		"outputs": [{"name": "assets", "type": "asset_list"}],
	},
}


func test_main_path_whitelist_and_ports() -> void:
	var registry := NodeRegistry.new()
	assert_eq(NodeRegistry.BUILTIN_TYPES, MAIN_PATH_TYPES)
	var observed_port_types := {}
	for type_name in MAIN_PATH_TYPES:
		assert_true(registry.has_type(type_name), "%s must be a built-in v2 node" % type_name)
		var node: PFNode = registry.create(type_name)
		var expected: Dictionary = EXPECTED_NODES[type_name]
		assert_eq(node.get_type(), type_name)
		assert_eq(node.get_category(), expected["category"], "%s category" % type_name)
		assert_eq(node.get_input_ports(), expected["inputs"], "%s input ports" % type_name)
		assert_eq(node.get_output_ports(), expected["outputs"], "%s output ports" % type_name)
		for port in node.get_input_ports() + node.get_output_ports():
			observed_port_types[String(port["type"])] = true
	assert_eq(_sorted_keys(observed_port_types), PORT_TYPES)


func test_object_list_rows_only() -> void:
	var valid_rows := [
		{"id": " barrel ", "text": " wooden barrel ", "count": 2, "enabled": true},
		{"id": "crate", "text": "wooden crate", "count": 1, "enabled": false},
	]
	var parsed := Graph.parse_v2(_graph_with_node("object_list", {"rows": valid_rows}))
	assert_true(parsed.get("ok", false), JSON.stringify(parsed))
	if parsed.get("ok", false):
		var rows: Array = parsed["graph"].get_node_params("subject")["rows"]
		assert_eq(
			rows,
			[
				{"id": "barrel", "text": "wooden barrel", "count": 2, "enabled": true},
				{"id": "crate", "text": "wooden crate", "count": 1, "enabled": false},
			]
		)
		assert_eq(
			parsed["graph"].get_node("subject").execute({}, {"rows": rows}, null),
			{"subjects": [{"id": "barrel", "text": "wooden barrel", "count": 2}]}
		)

	var invalid_params := [
		{"items": ["barrel"]},
		{"rows": [], "items": []},
		{"rows": [{"id": "", "text": "barrel", "count": 1, "enabled": true}]},
		{"rows": [{"id": "a", "text": "  ", "count": 1, "enabled": true}]},
		{"rows": [{"id": "a", "text": "barrel", "count": 0, "enabled": true}]},
		{"rows": [{"id": "a", "text": "barrel", "count": 1000, "enabled": true}]},
		{"rows": [{"id": "a", "text": "barrel", "count": 1.0, "enabled": true}]},
		{"rows": [{"id": "a", "text": "barrel", "count": 1, "enabled": 1}]},
		{"rows": [{"id": "a", "text": "barrel", "count": 1, "enabled": true, "legacy": true}]},
		{
			"rows":
			[
				{"id": "same", "text": "barrel", "count": 1, "enabled": true},
				{"id": "same", "text": "crate", "count": 1, "enabled": true},
			]
		},
	]
	for params in invalid_params:
		parsed = Graph.parse_v2(_graph_with_node("object_list", params))
		assert_false(parsed.get("ok", false), "must reject invalid rows: %s" % JSON.stringify(params))


func test_size_spec_removed_from_production() -> void:
	var registry := NodeRegistry.new()
	assert_false(registry.has_type("size_spec"))
	assert_false(registry.has_type("style_preset"))
	assert_false(
		FileAccess.file_exists("res://core/graph/nodes/size_spec_node.gd"),
		"the retired production node script must be deleted"
	)
	for production_surface in [
		"res://core/graph/node_registry.gd",
		"res://services/graph_mock_runner.gd",
		"res://services/offline_example_graph.gd",
		"res://services/workflow_template_service.gd",
		"res://ui/canvas/canvas_card_contract.gd",
		"res://ui/canvas/infinite_canvas.gd",
	]:
		assert_false(
			"size_spec" in FileAccess.get_file_as_string(production_surface).to_lower(),
			"%s must not retain size_spec" % production_surface
		)
	for retired_type in ["size_spec", "style_preset"]:
		var parsed := Graph.parse_v2(_graph_with_node(retired_type, {}))
		assert_false(parsed.get("ok", false))
		assert_eq(parsed.get("error", {}).get("code", ""), "retired_graph_node")
	for legacy_param in ["width", "height", "per_subject", "preset_ref"]:
		var params := _generate_params()
		params[legacy_param] = 1
		var parsed := Graph.parse_v2(_graph_with_node("ai_generate", params))
		assert_false(parsed.get("ok", false), "must reject ai_generate.%s" % legacy_param)
		assert_eq(parsed.get("error", {}).get("code", ""), "unknown_graph_param")


func test_generate_params_roundtrip() -> void:
	var source := _graph_with_node("ai_generate", _generate_params())
	var parsed := Graph.parse_v2(source)
	assert_true(parsed.get("ok", false), JSON.stringify(parsed))
	if parsed.get("ok", false):
		assert_eq(parsed["graph"].to_json(), source)
		assert_eq(_sorted_keys(parsed["graph"].get_node_params("subject")), [
			"batch_size", "extra", "model_id", "provider_id", "seed", "target_height", "target_width"
		])

	var defaults: Dictionary = NodeRegistry.new().create("ai_generate").validate_params({})
	assert_eq(
		defaults,
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"target_width": 32,
			"target_height": 32,
			"batch_size": 4,
			"seed": -1,
			"extra": {"quality": "low"},
		}
	)


func test_batch_display_and_output_port_have_no_alias() -> void:
	var batch: PFNode = NodeRegistry.new().create("batch")
	assert_eq(batch.get_display_name(), "Output")
	assert_eq(batch.get_input_ports(), [{"name": "in", "type": "asset_list", "required": false}])
	assert_eq(batch.get_output_ports(), [{"name": "assets", "type": "asset_list"}])
	for old_param in ["asset_ids", "expected_count", "review_states", "review_filter", "review_layout", "focus_asset_id", "compare_asset_id"]:
		var params := _batch_params()
		params[old_param] = []
		var parsed := Graph.parse_v2(_graph_with_node("batch", params))
		assert_false(parsed.get("ok", false), "must reject batch.%s" % old_param)

	for old_output_port in ["images", "output"]:
		var graph_data := {
			"graph_version": 2,
			"id": "g",
			"name": "Batch port gate",
			"nodes": [
				{"id": "batch", "type": "batch", "params": _batch_params()},
				{"id": "cleanup", "type": "pixel_cleanup", "params": {}},
			],
			"edges": [{"from": ["batch", old_output_port], "to": ["cleanup", "assets"]}],
		}
		var parsed := Graph.parse_v2(graph_data)
		assert_false(parsed.get("ok", false), "must reject batch.%s alias" % old_output_port)


func test_non_main_path_classification_keeps_tools_outside_graph_registry() -> void:
	var registry := NodeRegistry.new()
	for deferred_type in [
		"matting", "slice", "outline", "palette_map", "select", "output_to_canvas", "output_to_library"
	]:
		assert_false(registry.has_type(deferred_type), "%s is not a Beta 0.7 main-path node" % deferred_type)
	for independent_tool in [
		"res://core/pixel/matting.gd",
		"res://core/pixel/segmenter.gd",
		"res://core/pixel/outliner.gd",
		"res://core/pixel/palette_registry.gd",
		"res://ui/editor/pixel_editor.gd",
		"res://ui/board/board_editor.gd",
	]:
		assert_true(FileAccess.file_exists(independent_tool), "%s remains an independent tool" % independent_tool)


func _graph_with_node(type_name: String, params: Dictionary) -> Dictionary:
	return {
		"graph_version": 2,
		"id": "g",
		"name": "Schema test",
		"nodes": [{"id": "subject", "type": type_name, "params": params}],
		"edges": [],
	}


func _generate_params() -> Dictionary:
	return {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"target_width": 32,
		"target_height": 32,
		"batch_size": 4,
		"seed": -1,
		"extra": {"quality": "low"},
	}


func _batch_params() -> Dictionary:
	return {
		"label": "",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}


func _sorted_keys(value: Dictionary) -> Array:
	var keys := value.keys()
	keys.sort()
	return keys
