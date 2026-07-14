# gdlint: disable=max-line-length
extends "res://addons/gut/test.gd"

const AppInfo := preload("res://core/util/app_info.gd")
const Graph := preload("res://core/graph/pf_graph.gd")
const NodeRegistry := preload("res://core/graph/node_registry.gd")
const Clipboard := preload("res://core/graph/canvas_graph_clipboard.gd")
const PluginAPI := preload("res://services/plugin_api.gd")
const PluginService := preload("res://services/plugin_service.gd")
const ProviderService := preload("res://services/provider_service.gd")
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")
const FileIO := preload("res://infra/file_io.gd")
const Catalog := preload("res://infra/localization_catalog.gd")
const ContractErrorText := preload("res://services/contract_error_text.gd")


class CountingIds:
	extends RefCounted

	var calls := 0

	func next() -> String:
		calls += 1
		return "generated-%d" % calls


func test_project_graph_template_and_clipboard_are_hard_cut_to_v2() -> void:
	assert_eq(AppInfo.PROJECT_FORMAT_VERSION, 2)
	assert_eq(Graph.GRAPH_VERSION, 2)
	assert_eq(WorkflowTemplateService.VERSION, 2)
	assert_eq(Clipboard.PAYLOAD_VERSION, 2)


func test_graph_main_path_registry_contains_only_v2_nodes() -> void:
	assert_eq(
		NodeRegistry.BUILTIN_TYPES,
		[
			"ai_generate",
			"batch",
			"image_input",
			"object_list",
			"pixel_cleanup",
			"prompt_preset",
			"reference_set",
			"text_prompt",
		]
	)


func test_provider_and_plugin_registration_gates_are_v2() -> void:
	assert_eq(ProviderService.API_VERSION, 2)
	assert_eq(PluginService.API_VERSION, 2)


func test_unsupported_errors_are_bilingual_safe() -> void:
	var english := Catalog.load_catalog("en")
	var chinese := Catalog.load_catalog("zh_CN")
	assert_eq(ContractErrorText.KEY_BY_CODE.size(), 6)
	for code in ContractErrorText.KEY_BY_CODE:
		var key: String = ContractErrorText.KEY_BY_CODE[code]
		assert_true(english.has(key), key)
		assert_true(chinese.has(key), key)
		assert_false(String(english[key]).contains(code), code)
		assert_false(String(chinese[key]).contains(code), code)
		assert_true(String(english[key]).contains("Create a new project"), key)
		assert_true(String(chinese[key]).contains("请新建项目"), key)


func test_plugin_registration_surface_retires_style_and_adds_split_presets() -> void:
	var api := PluginAPI.new()
	assert_false(api.has_method("register_style_preset"))
	assert_true(api.has_method("register_prompt_preset"))
	assert_true(api.has_method("register_cleanup_preset"))


func test_project_v1_is_rejected_without_replacing_current_project() -> void:
	var service := get_tree().root.get_node("ProjectService")
	service.new_project("Keep me")
	var original_id: String = service.current_project.get_id()
	var path := "user://tests/b7_project_v1_rejected.pxproj"
	assert_eq(
		(
			FileIO
			. zip_pack(
				{
					"manifest.json":
					{
						"format_version": 1,
						"id": "v1-project",
						"name": "V1",
						"entries": {"graphs": [], "asset_count": 0},
					},
					"canvas/canvas.json": {"camera": {"center": [0, 0], "zoom": 1.0}, "items": []},
				},
				path
			)
		),
		OK
	)
	assert_eq(service.open_project(path), ERR_FILE_UNRECOGNIZED)
	assert_eq(service.last_load_error.get("code", ""), "unsupported_project_version")
	assert_eq(service.current_project.get_id(), original_id)


func test_graph_v1_is_rejected_without_registering_old_aliases() -> void:
	var parsed := Graph.parse_v2(
		{"graph_version": 1, "id": "old", "name": "Old", "nodes": [], "edges": []}
	)
	assert_false(parsed.get("ok", true))
	assert_eq(parsed["error"]["code"], "unsupported_graph_version")
	assert_false(NodeRegistry.new().has_type("size_spec"))
	assert_false(NodeRegistry.new().has_type("style_preset"))
	for invalid_version in ["2", 2.0, 2.5]:
		var invalid := {
			"graph_version": invalid_version,
			"id": "invalid-version",
			"name": "Invalid",
			"nodes": [],
			"edges": [],
		}
		assert_eq(Graph.parse_v2(invalid)["error"]["code"], "unsupported_graph_version")


func test_template_v1_is_rejected_without_guessing_fields() -> void:
	var template: Dictionary = WorkflowTemplateService.builtin_templates()[0].duplicate(true)
	template["version"] = 1
	assert_eq(
		WorkflowTemplateService.validate_template(template).get("code", ""),
		"unsupported_template_version"
	)
	for invalid_version in ["2", 2.0, 2.5]:
		template["version"] = invalid_version
		assert_eq(
			WorkflowTemplateService.validate_template(template).get("code", ""),
			"unsupported_template_version"
		)


func test_clipboard_v1_is_rejected_before_allocating_ids() -> void:
	var ids := CountingIds.new()
	var result := (
		Clipboard
		. instantiate(
			{
				"version": 1,
				"origin_project_id": "project-a",
				"graph_id": "graph",
				"items": [{}],
				"nodes": [{}],
			},
			Vector2.ZERO,
			Callable(ids, "next"),
			"project-a"
		)
	)
	assert_false(result.get("ok", true))
	assert_eq(result["error"]["code"], "unsupported_clipboard_version")
	assert_eq(ids.calls, 0)
	for invalid_version in ["2", 2.0, 2.5]:
		var invalid_payload := {
			"version": invalid_version,
			"origin_project_id": "project-a",
			"graph_id": "graph",
			"items": [{}],
			"nodes": [{}],
		}
		assert_eq(
			(
				Clipboard
				. instantiate(invalid_payload, Vector2.ZERO, Callable(ids, "next"), "project-a")["error"]["code"]
			),
			"unsupported_clipboard_version"
		)
	assert_eq(ids.calls, 0)


func test_project_string_and_fractional_v2_versions_are_rejected_atomically() -> void:
	var service := ProjectService
	service.new_project("Keep exact version")
	var original_id: String = service.current_project.get_id()
	for index in range(2):
		var invalid_version: Variant = "2" if index == 0 else 2.5
		var path := "user://tests/b7_project_invalid_version_%d.pxproj" % index
		assert_eq(FileIO.zip_pack(_project_entries(invalid_version, []), path), OK)
		assert_eq(service.open_project(path), ERR_FILE_UNRECOGNIZED)
		assert_eq(service.last_load_error.get("code", ""), "unsupported_project_version")
		assert_eq(service.current_project.get_id(), original_id)


func test_project_v2_rejects_legacy_canvas_shapes_before_replacing_current_project() -> void:
	var service := ProjectService
	service.new_project("Keep legacy rejection")
	var original_id: String = service.current_project.get_id()
	var legacy_items := [
		{"id": "legacy", "type": "batch_card", "asset_ids": [], "position": [0, 0]},
		{
			"id": "node",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "output",
			"position": [0, 0],
			"z_index": 0,
			"review_filter": "kept",
		},
	]
	for index in range(legacy_items.size()):
		var path := "user://tests/b7_project_legacy_canvas_%d.pxproj" % index
		assert_eq(FileIO.zip_pack(_project_entries(2, [legacy_items[index]]), path), OK)
		assert_eq(service.open_project(path), ERR_FILE_CORRUPT)
		assert_true(String(service.last_load_error.get("code", "")).begins_with("legacy_canvas_"))
		assert_eq(service.current_project.get_id(), original_id)


func _project_entries(version: Variant, items: Array) -> Dictionary:
	return {
		"manifest.json":
		{
			"format_version": version,
			"app_version": "0.7.0",
			"id": "00000000-0000-4000-8000-000000000001",
			"name": "Boundary",
			"created_at": "2026-07-14T00:00:00Z",
			"modified_at": "2026-07-14T00:00:00Z",
			"custom_palettes": [],
			"entries":
			{
				"canvases": ["canvas"],
				"graphs": [],
				"boards": [],
				"animations": [],
				"asset_count": 0,
			},
		},
		"canvas/canvas.json": {"camera": {"center": [0, 0], "zoom": 1.0}, "items": items},
	}
