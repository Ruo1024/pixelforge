extends "res://addons/gut/test.gd"

const Strings := preload("res://ui/shell/strings.gd")

const PluginAPI := preload("res://services/plugin_api.gd")
const PluginService := preload("res://services/plugin_service.gd")
const NodeRegistry := preload("res://core/graph/node_registry.gd")

const ROOT := "user://tests/b7_2_plugin_gate"


class RawSchemaNode:
	extends PFNode

	func get_type() -> String:
		return "test.raw_schema"

	func get_param_schema() -> Array[Dictionary]:
		return [{"key": "value", "label": "Raw label"}]


class LocalizedSchemaNode:
	extends PFNode

	func get_type() -> String:
		return "test.localized_schema"

	func get_param_schema() -> Array[Dictionary]:
		return [{"key": "value", "label_key": "GEN_PARAM_QUALITY"}]


class RawSchemaProvider:
	extends PFProvider

	func get_config_schema() -> Array[Dictionary]:
		return [{"key": "secret", "label": "Raw label"}]


class LocalizedSchemaProvider:
	extends PFProvider

	func get_config_schema() -> Array[Dictionary]:
		return [
			{
				"key": "secret",
				"label_key": "OPENAI_FIELD_API_KEY",
				"help_key": "OPENAI_FIELD_API_KEY_HELP",
			}
		]

	func get_model_descriptors() -> Array[Dictionary]:
		return [
			{
				"dynamic_params":
				[
					{
						"key": "quality",
						"label_key": "GEN_PARAM_QUALITY",
						"help_key": "GEN_PARAM_QUALITY_HELP",
					}
				]
			}
		]


func before_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	NodeRegistry.unregister_plugin_type("sample.echo")


func after_each() -> void:
	NodeRegistry.unregister_plugin_type("sample.echo")
	NodeRegistry.unregister_plugin_type("test.raw_schema")
	NodeRegistry.unregister_plugin_type("test.localized_schema")
	_remove_tree(ProjectSettings.globalize_path(ROOT))


func test_registration_surface_replaces_style_and_validates_split_presets() -> void:
	var service := PluginService.new()
	service.scan_on_ready = false
	add_child_autofree(service)
	await wait_process_frames(1)
	var api := PluginAPI.new(service, service, "preset_plugin")
	assert_false(api.has_method("register_style_preset"))
	assert_true(api.has_method("register_prompt_preset"))
	assert_true(api.has_method("register_cleanup_preset"))
	if (
		not api.has_method("register_prompt_preset")
		or not api.has_method("register_cleanup_preset")
	):
		return
	var prompt := {
		"prompt_preset_version": 1,
		"id": "plugin-prompt",
		"name": "Plugin prompt",
		"prefix": "plugin prefix",
	}
	assert_true(api.register_prompt_preset("plugin-prompt", prompt))
	assert_false(api.register_prompt_preset("mismatched", prompt))
	assert_true(service.list_capabilities("prompt_preset").has("plugin-prompt"))
	assert_eq(service.get_prompt_preset("plugin-prompt"), prompt)
	var cleanup := {
		"cleanup_preset_version": 1,
		"id": "plugin-cleanup",
		"name": "Plugin cleanup",
		"settings":
		{
			"detect_grid":
			{"enabled": true, "mode": "auto", "scale": 4.0, "offset": [0.0, 0.0], "base_size": 32},
			"resample": {"enabled": true, "mode": "mode", "scale": 4.0, "offset": [0.0, 0.0]},
			"quantize":
			{
				"enabled": true,
				"mode": "fixed_palette",
				"palette_id": "db32",
				"auto_k_strategy": "median_cut",
				"k": 16,
				"dither": "none",
				"dither_strength": 0.0,
				"dither_contrast": 0.0,
				"dither_chroma": 0.0,
				"dither_density": 1.0,
			}
		},
	}
	assert_true(api.register_cleanup_preset("plugin-cleanup", cleanup))
	assert_eq(service.get_cleanup_preset("plugin-cleanup"), cleanup)
	api.revoke_all()
	assert_false(service.list_capabilities("prompt_preset").has("plugin-prompt"))
	assert_eq(service.get_prompt_preset("plugin-prompt"), {})
	assert_eq(service.get_cleanup_preset("plugin-cleanup"), {})


func test_v1_manifest_is_rejected_before_entry_and_v2_builtins_are_exact() -> void:
	var service := PluginService.new()
	service.scan_on_ready = false
	service.plugin_root = ROOT
	add_child_autofree(service)
	await wait_process_frames(1)
	var plugin_dir := ROOT.path_join("legacy_plugin")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(plugin_dir))
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("res://tests/fixtures/plugins/sample_main.gd"),
		ProjectSettings.globalize_path(plugin_dir.path_join("main.gd"))
	)
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("res://tests/fixtures/plugins/sample_node.gd"),
		ProjectSettings.globalize_path(plugin_dir.path_join("sample_node.gd"))
	)
	_write_json(
		plugin_dir.path_join("plugin.json"),
		{
			"id": "legacy_plugin",
			"name": "V1",
			"version": "1.0.0",
			"api_version": 1,
			"min_app_version": "0.1.0",
			"entry": "main.gd",
			"permissions": [],
		}
	)
	var rejected: Dictionary = service.load_directory_plugin(plugin_dir)
	assert_false(bool(rejected.get("ok", false)))
	assert_eq(rejected.get("code", ""), "unsupported_plugin_api_version", JSON.stringify(rejected))
	assert_true(Dictionary(rejected.get("args", {})).has("actual"))
	assert_true(String(rejected.get("reason", "")).is_empty())
	assert_false(rejected.has("reason"), "version errors store code+args, not rendered text")
	assert_false(NodeRegistry.new().has_type("sample.echo"), "v1 entry must not execute")
	assert_false(service.list_capabilities("menu_item").has("Extensions/Sample Echo"))

	for manifest_path in [
		"res://plugins/provider_openai/plugin.json",
		"res://plugins/provider_retrodiffusion/plugin.json",
		"res://plugins/bridge_comfyui/plugin.json",
	]:
		assert_eq(_manifest_version(manifest_path), 2, manifest_path)
	assert_eq(_manifest_version("res://templates/plugin_template/plugin.json"), 2)
	for record in service.get_plugin_records():
		assert_ne(String(record.get("id", "")), "bridge_comfyui")


func test_unrelated_v1_registration_capabilities_remain_available() -> void:
	var api := PluginAPI.new()
	for method in [
		"register_node_type",
		"register_provider",
		"register_pipeline_step",
		"register_palette",
		"register_menu_item",
		"register_exporter",
	]:
		assert_true(api.has_method(method), "%s must remain in Plugin API v2" % method)


func test_plugin_node_and_provider_schemas_share_the_resolver_gate() -> void:
	var api := PluginAPI.new()
	assert_false(api.register_node_type("test.raw_schema", RawSchemaNode))
	var service := PluginService.new()
	service.scan_on_ready = false
	add_child_autofree(service)
	await wait_process_frames(1)
	api = PluginAPI.new(service, service, "schema_plugin")
	assert_true(api.register_node_type("test.localized_schema", LocalizedSchemaNode))
	assert_false(api._validate_provider_schemas(RawSchemaProvider.new()))
	assert_true(api._validate_provider_schemas(LocalizedSchemaProvider.new()))


func test_manifest_validator_does_not_coerce_version_types() -> void:
	var service := PluginService.new()
	var manifest := {
		"id": "strict_plugin",
		"name": "Strict",
		"version": "1.0.0",
		"api_version": 2,
		"min_app_version": "0.1.0",
		"entry": "main.gd",
	}
	assert_true(bool(service.validate_manifest(manifest).get("ok", false)))
	for invalid_version in ["2", 2.0]:
		var invalid := manifest.duplicate(true)
		invalid["api_version"] = invalid_version
		assert_false(bool(service.validate_manifest(invalid).get("ok", false)))
	service.free()


func _manifest_version(path: String) -> int:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return int(parsed.get("api_version", 0)) if parsed is Dictionary else 0


func _write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(path)


func test_unverified_plugin_warning_survives_v2() -> void:
	assert_true(Strings.PLUGIN_SECURITY_WARNING.contains("Install only plugins you trust"))
	assert_true(Strings.PLUGIN_SECURITY_WARNING.contains("not a sandbox"))


func test_signature_is_not_api_v2_gate() -> void:
	var source := FileAccess.get_file_as_string("res://services/plugin_service.gd")
	assert_false(source.contains("verify_signature"))
	assert_false(source.contains("signature_valid"))
	assert_false(source.contains("trusted_plugin"))
	assert_true(source.contains("unsupported_plugin_api_version"))
