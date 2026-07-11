extends "res://addons/gut/test.gd"

const PluginServiceScript := preload("res://services/plugin_service.gd")
const NodeRegistry := preload("res://core/graph/node_registry.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")

const ROOT := "user://tests/m7_plugins"
const DIRECTORY_ID := "sample_directory"


func before_each() -> void:
	NodeRegistry.unregister_plugin_type("sample.echo")
	_remove_tree(ProjectSettings.globalize_path(ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))


func after_each() -> void:
	NodeRegistry.unregister_plugin_type("sample.echo")


func test_directory_plugin_unload_ghost_and_reload_restore() -> void:
	var plugin_dir := ROOT.path_join(DIRECTORY_ID)
	_make_plugin_directory(plugin_dir, DIRECTORY_ID)
	var service := PluginServiceScript.new()
	service.scan_on_ready = false
	service.plugin_root = ROOT
	add_child_autofree(service)
	await wait_process_frames(1)
	var loaded := service.load_directory_plugin(plugin_dir)
	assert_true(bool(loaded["ok"]))
	assert_true(NodeRegistry.new().has_type("sample.echo"))
	assert_true(service.list_capabilities("menu_item").has("Extensions/Sample Echo"))

	var graph := GraphScript.new()
	graph.add_node(NodeRegistry.new().create("sample.echo"), "sample")
	var saved := graph.to_json()
	assert_true(service.unload_plugin(DIRECTORY_ID))
	assert_true(GraphScript.from_json(saved).get_node("sample").is_ghost())
	assert_true(bool(service.load_directory_plugin(plugin_dir)["ok"]))
	assert_false(GraphScript.from_json(saved).get_node("sample").is_ghost())


func test_pck_plugin_loads_from_namespaced_root() -> void:
	var pck_path := ROOT.path_join("sample_pck.pck")
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(pck_path), OK)
	var fixture_root := "res://tests/fixtures/plugins"
	assert_eq(
		packer.add_file(
			"res://plugins/sample_pck/main.gd", fixture_root.path_join("sample_main.gd")
		),
		OK
	)
	assert_eq(
		packer.add_file(
			"res://plugins/sample_pck/sample_node.gd", fixture_root.path_join("sample_node.gd")
		),
		OK
	)
	var manifest_path := ROOT.path_join("sample_pck.json")
	_write_json(manifest_path, _manifest("sample_pck"))
	assert_eq(packer.add_file("res://plugins/sample_pck/plugin.json", manifest_path), OK)
	assert_eq(packer.flush(), OK)
	var service := PluginServiceScript.new()
	service.scan_on_ready = false
	service.plugin_root = ROOT
	add_child_autofree(service)
	await wait_process_frames(1)
	assert_true(bool(service.load_pck_plugin(pck_path)["ok"]))
	assert_true(NodeRegistry.new().has_type("sample.echo"))


func test_bad_manifest_version_and_entry_are_isolated_with_reasons() -> void:
	var service := PluginServiceScript.new()
	service.scan_on_ready = false
	service.plugin_root = ROOT
	add_child_autofree(service)
	await wait_process_frames(1)
	var missing_dir := ROOT.path_join("missing_manifest")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(missing_dir))
	assert_string_contains(String(service.load_directory_plugin(missing_dir)["reason"]), "missing")
	var future_dir := ROOT.path_join("future_plugin")
	_make_plugin_directory(future_dir, "future_plugin", "99.0.0")
	assert_string_contains(String(service.load_directory_plugin(future_dir)["reason"]), "newer")
	var bad_entry_dir := ROOT.path_join("bad_entry")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bad_entry_dir))
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("res://tests/fixtures/plugins/not_a_plugin.gd"),
		ProjectSettings.globalize_path(bad_entry_dir.path_join("main.gd"))
	)
	_write_json(bad_entry_dir.path_join("plugin.json"), _manifest("bad_entry"))
	assert_string_contains(
		String(service.load_directory_plugin(bad_entry_dir)["reason"]), "lifecycle"
	)
	var syntax_dir := ROOT.path_join("syntax_error")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(syntax_dir))
	var syntax_file := FileAccess.open(syntax_dir.path_join("main.gd"), FileAccess.WRITE)
	syntax_file.store_string("extends PFPlugin\nfunc _enter_app(api: Variant) -> void\n")
	syntax_file.close()
	_write_json(syntax_dir.path_join("plugin.json"), _manifest("syntax_error"))
	assert_string_contains(
		String(service.load_directory_plugin(syntax_dir)["reason"]), "could not be loaded"
	)


func _make_plugin_directory(path: String, plugin_id: String, min_version: String = "0.1.0") -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path("res://tests/fixtures/plugins/sample_main.gd"),
		ProjectSettings.globalize_path(path.path_join("main.gd"))
	)
	_write_json(path.path_join("plugin.json"), _manifest(plugin_id, min_version))


func _manifest(plugin_id: String, min_version: String = "0.1.0") -> Dictionary:
	return {
		"id": plugin_id,
		"name": plugin_id.capitalize(),
		"version": "1.0.0",
		"api_version": 1,
		"min_app_version": min_version,
		"entry": "main.gd",
		"permissions": [],
	}


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
