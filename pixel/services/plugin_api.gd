class_name PFPluginAPI
extends RefCounted

## Per-plugin registration facade with a reversible ledger for every PLUGIN-API v1 surface.

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")

var _plugin_service: Node = null
var _provider_service: Node = null
var _plugin_id := ""
var _ledger: Array = []


func _init(
	plugin_service: Node = null, provider_service: Node = null, plugin_id: String = "builtin"
) -> void:
	_plugin_service = plugin_service
	_provider_service = provider_service if provider_service != null else plugin_service
	_plugin_id = plugin_id


func register_node_type(type_name: String, node_script: Script) -> bool:
	if not NodeRegistryScript.register_plugin_type(type_name, node_script):
		return false
	_ledger.append(["node_type", type_name])
	return true


func register_provider(provider: PFProvider) -> bool:
	if _provider_service == null or not _provider_service.register_provider(provider):
		return false
	_ledger.append(["provider", provider.get_id()])
	return true


func register_pipeline_step(step_id: String, step_script: Script) -> bool:
	return _register_service_capability("pipeline_step", step_id, step_script)


func register_palette(palette_id: String, palette: Variant) -> bool:
	return _register_service_capability("palette", palette_id, palette)


func register_style_preset(preset_id: String, preset: Dictionary) -> bool:
	return _register_service_capability("style_preset", preset_id, preset)


func register_menu_item(path: String, callback: Callable) -> bool:
	return _register_service_capability("menu_item", path, callback)


func register_exporter(exporter_id: String, exporter: Variant) -> bool:
	return _register_service_capability("exporter", exporter_id, exporter)


func revoke_all() -> void:
	for index in range(_ledger.size() - 1, -1, -1):
		var entry: Array = _ledger[index]
		match String(entry[0]):
			"node_type":
				NodeRegistryScript.unregister_plugin_type(String(entry[1]))
			"provider":
				if _provider_service != null:
					_provider_service.unregister_provider(String(entry[1]))
			_:
				if _plugin_service != null:
					_plugin_service.unregister_capability(
						String(entry[0]), String(entry[1]), _plugin_id
					)
	_ledger.clear()


func get_ledger() -> Array:
	return _ledger.duplicate(true)


func _register_service_capability(kind: String, capability_id: String, value: Variant) -> bool:
	if _plugin_service == null or capability_id.is_empty():
		return false
	if not _plugin_service.register_capability(kind, capability_id, value, _plugin_id):
		return false
	_ledger.append([kind, capability_id])
	return true
