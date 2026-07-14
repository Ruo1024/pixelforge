extends "res://addons/gut/test.gd"

const AppInfo := preload("res://core/util/app_info.gd")
const Graph := preload("res://core/graph/pf_graph.gd")
const NodeRegistry := preload("res://core/graph/node_registry.gd")
const PluginService := preload("res://services/plugin_service.gd")
const ProviderServiceScript := preload("res://services/provider_service.gd")
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")

const CONTRACT_EXPECTATIONS := {
	"GRAPH-SCHEMA.md": ["graph_version = 2", "position、display_title、size 与 collapsed 只在 canvas"],
	"PROVIDER-API.md": ["api_version = 2", "OpenAI Image", "RetroDiffusion"],
	"PROJECT-FORMAT.md": ["format_version = 2", "unsupported_project_version", "batch_card"],
	"WORKFLOW-TEMPLATE.md":
	["pixelforge.workflow-template", "version=2", "unsupported_template_version"],
	"STYLE-PRESETS.md": ["Beta 0.7 不再定义或注册跨模块 StylePreset"],
	"PROMPT-PRESETS.md": ["prompt_preset_version=1"],
	"CLEANUP-PRESETS.md": ["cleanup_preset_version=1"],
	"PLUGIN-API.md": ["api_version=2", "register_prompt_preset", "register_cleanup_preset"],
}


func test_eight_contracts_exist_and_align() -> void:
	assert_eq(CONTRACT_EXPECTATIONS.size(), 8)
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var contract_root := project_root.path_join("pixelforge-plan/02-contracts")
	for file_name in CONTRACT_EXPECTATIONS:
		var path := contract_root.path_join(file_name)
		assert_true(FileAccess.file_exists(path), path)
		var text := FileAccess.get_file_as_string(path)
		for expected in CONTRACT_EXPECTATIONS[file_name]:
			assert_true(text.contains(expected), "%s missing %s" % [file_name, expected])

	assert_eq(AppInfo.PROJECT_FORMAT_VERSION, 2)
	assert_eq(Graph.GRAPH_VERSION, 2)
	assert_eq(ProviderServiceScript.API_VERSION, 2)
	assert_eq(PluginService.API_VERSION, 2)
	assert_eq(WorkflowTemplateService.VERSION, 2)
	var registry := NodeRegistry.new()
	assert_false(registry.has_type("style_preset"))
	assert_false(registry.has_type("size_spec"))
	assert_true(registry.has_type("prompt_preset"))
	assert_true(registry.has_type("pixel_cleanup"))
