extends "res://addons/gut/test.gd"

const AppInfo := preload("res://core/util/app_info.gd")
const Clipboard := preload("res://core/graph/canvas_graph_clipboard.gd")
const Graph := preload("res://core/graph/pf_graph.gd")
const OfflineExample := preload("res://services/offline_example_graph.gd")
const ProjectModel := preload("res://services/pf_project.gd")
const ProviderService := preload("res://services/provider_service.gd")
const WorkflowTemplates := preload("res://services/workflow_template_service.gd")
const WorkspaceFixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")
const LargeWorkspaceFixture := preload(
	"res://tests/fixtures/generators/beta_large_workspace_fixture.gd"
)

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
const RETIRED_TOKENS := [
	'"size_spec"',
	'"style_preset"',
	'"review_states"',
	'"review_filter"',
	'"review_layout"',
	'"focus_asset_id"',
	'"compare_',
]


func test_all_default_resources_are_v2() -> void:
	assert_eq(AppInfo.PROJECT_FORMAT_VERSION, 2)
	assert_eq(Graph.GRAPH_VERSION, 2)
	assert_eq(ProviderService.API_VERSION, 2)
	assert_eq(WorkflowTemplates.VERSION, 2)
	assert_eq(Clipboard.PAYLOAD_VERSION, 2)

	var project := ProjectModel.new()
	project.reset("V2 fixture")
	assert_eq(project.manifest["format_version"], 2)
	assert_true(_is_uuid_v4(String(project.manifest["id"])))
	assert_false(project.manifest.has("style_preset"))

	for fixture in [WorkspaceFixture.build(), LargeWorkspaceFixture.build()]:
		for graph_data in fixture["graphs"].values():
			_assert_v2_graph(graph_data, "bundled test fixture")

	var offline_graph: Dictionary = OfflineExample.build("A tiny forest shrine", "Starter example").to_json()
	_assert_v2_graph(offline_graph, "offline example")
	assert_eq(
		_node_types(offline_graph),
		["prompt_preset", "text_prompt", "reference_set", "ai_generate", "pixel_cleanup"]
	)
	assert_eq(_node_params(offline_graph, "text_prompt")["text"], "A tiny forest shrine")
	assert_eq(_node_params(offline_graph, "reference_set")["asset_ids"], [])
	assert_false(_has_node_type(offline_graph, "object_list"))
	assert_false(_has_node_type(offline_graph, "batch"))
	assert_true(_has_edge(offline_graph, "prompt_preset", "prefix", "generate", "prefix"))
	assert_true(_has_edge(offline_graph, "text_prompt", "prompt", "generate", "prompt"))
	assert_true(_has_edge(offline_graph, "reference_set", "assets", "generate", "references"))
	assert_false(_has_incoming_edge(offline_graph, "cleanup"))
	var templates := WorkflowTemplates.builtin_templates()
	assert_eq(templates.size(), 4)
	for template in templates:
		assert_eq(template["version"], 2, String(template["id"]))
		assert_true(WorkflowTemplates.validate_template(template)["ok"], String(template["id"]))
		_assert_no_retired_tokens(template, "template %s" % template["id"])
		for node in template["nodes"]:
			assert_true(String(node["type"]) in MAIN_PATH_TYPES, JSON.stringify(node))

	assert_eq(
		ProviderService.BUILTIN_PROVIDER_PLUGINS,
		[
			"res://plugins/provider_openai/main.gd",
			"res://plugins/provider_retrodiffusion/main.gd",
		]
	)
	for plugin_script_path in ProviderService.BUILTIN_PROVIDER_PLUGINS:
		var plugin_dir := String(plugin_script_path).get_base_dir()
		var manifest := _json_file(plugin_dir.path_join("plugin.json"))
		assert_eq(int(manifest.get("api_version", 0)), 2, plugin_dir)
		var plugin: Variant = load(plugin_script_path).new()
		assert_not_null(plugin, plugin_script_path)
	assert_eq(
		int(_json_file("res://templates/plugin_template/plugin.json").get("api_version", 0)), 2
	)

	for preset_dir in ["res://assets/prompt_presets", "res://assets/cleanup_presets"]:
		var files := Array(DirAccess.get_files_at(preset_dir)).filter(
			func(file_name: String) -> bool: return file_name.ends_with(".json")
		)
		assert_eq(files.size(), 6, preset_dir)
		for file_name in files:
			var preset := _json_file(preset_dir.path_join(String(file_name)))
			var version_key := (
				"prompt_preset_version"
				if "prompt_presets" in preset_dir
				else "cleanup_preset_version"
			)
			assert_eq(int(preset.get(version_key, 0)), 1, preset_dir.path_join(String(file_name)))
			assert_false(preset.has("based_on"), String(file_name))


func test_offline_example_layout_uses_effective_bounds_and_output_reservation() -> void:
	var positions: Dictionary = OfflineExample.layout_positions(
		{
			"prompt_preset": Vector2(320, 280),
			"text_prompt": Vector2(360, 300),
			"reference_set": Vector2(400, 480),
			"generate": Vector2(400, 520),
			"cleanup": Vector2(400, 520),
		}
	)
	assert_eq(positions["prompt_preset"], Vector2(0, 0))
	assert_eq(positions["text_prompt"], Vector2(0, 360))
	assert_eq(positions["reference_set"], Vector2(0, 740))
	assert_eq(positions["generate"], Vector2(480, 350))
	assert_eq(positions["cleanup"], Vector2(1640, 350))
	assert_eq(
		positions["cleanup"].x - (positions["generate"].x + 400.0),
		80.0 + OfflineExample.RUNTIME_OUTPUT_WIDTH + 80.0
	)


func _assert_v2_graph(graph_data: Dictionary, source_name: String) -> void:
	assert_eq(graph_data.get("graph_version", 0), 2, source_name)
	var parsed := Graph.parse_v2(graph_data)
	assert_true(parsed.get("ok", false), "%s: %s" % [source_name, JSON.stringify(parsed)])
	_assert_no_retired_tokens(graph_data, source_name)
	for node in graph_data.get("nodes", []):
		assert_true(String(node.get("type", "")) in MAIN_PATH_TYPES, JSON.stringify(node))
		if String(node.get("type", "")) == "batch":
			for legacy_key in [
				"asset_ids",
				"expected_count",
				"review_states",
				"review_filter",
				"review_layout",
				"focus_asset_id",
				"compare_asset_id",
			]:
				assert_false(
					node.get("params", {}).has(legacy_key),
					"%s batch.%s" % [source_name, legacy_key]
				)


func _node_types(graph_data: Dictionary) -> Array:
	var result := []
	for node_value in graph_data.get("nodes", []):
		result.append(String(node_value.get("type", "")))
	return result


func _node_params(graph_data: Dictionary, node_id: String) -> Dictionary:
	for node_value in graph_data.get("nodes", []):
		if String(node_value.get("id", "")) == node_id:
			return Dictionary(node_value.get("params", {}))
	return {}


func _has_node_type(graph_data: Dictionary, node_type: String) -> bool:
	return node_type in _node_types(graph_data)


func _has_edge(
	graph_data: Dictionary, from_node: String, from_port: String, to_node: String, to_port: String
) -> bool:
	for edge_value in graph_data.get("edges", []):
		if (
			edge_value.get("from", []) == [from_node, from_port]
			and edge_value.get("to", []) == [to_node, to_port]
		):
			return true
	return false


func _has_incoming_edge(graph_data: Dictionary, node_id: String) -> bool:
	for edge_value in graph_data.get("edges", []):
		if String(edge_value.get("to", ["", ""])[0]) == node_id:
			return true
	return false


func _assert_no_retired_tokens(value: Variant, source_name: String) -> void:
	var serialized := JSON.stringify(value)
	for token in RETIRED_TOKENS:
		assert_false(token in serialized, "%s contains retired token %s" % [source_name, token])


func _json_file(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "%s must contain a JSON object" % path)
	return Dictionary(parsed) if parsed is Dictionary else {}


func _is_uuid_v4(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	return regex.search(value) != null
