class_name PFPluginAPI
extends RefCounted

## Per-plugin registration facade with a reversible ledger for every PLUGIN-API v2 surface.

const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const PROVIDER_API_VERSION := 2

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
	if node_script == null or not node_script.can_instantiate():
		return false
	var node: Variant = node_script.new()
	if (
		node == null
		or not node.has_method("get_param_schema")
		or not bool(
			SchemaTextResolverScript.validate_schema(node.get_param_schema()).get("ok", false)
		)
	):
		return false
	if not NodeRegistryScript.register_plugin_type(type_name, node_script):
		return false
	_ledger.append(["node_type", type_name])
	return true


func register_provider(provider: PFProvider) -> bool:
	if _provider_service == null or provider == null:
		return false
	# Provider version is the only call allowed before the hard compatibility gate.
	if provider.get_api_version() != PROVIDER_API_VERSION:
		return false
	if not _validate_provider_schemas(provider):
		return false
	var result: Dictionary = _provider_service.register_provider(provider)
	if not bool(result.get("ok", false)):
		return false
	_ledger.append(["provider", String(result["provider_id"])])
	return true


func register_pipeline_step(step_id: String, step_script: Script) -> bool:
	return _register_service_capability("pipeline_step", step_id, step_script)


func register_palette(palette_id: String, palette: Variant) -> bool:
	return _register_service_capability("palette", palette_id, palette)


func register_prompt_preset(preset_id: String, preset: Dictionary) -> bool:
	return _register_service_capability("prompt_preset", preset_id, preset)


func register_cleanup_preset(preset_id: String, preset: Dictionary) -> bool:
	return _register_service_capability("cleanup_preset", preset_id, preset)


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


func _validate_provider_schemas(provider: PFProvider) -> bool:
	if not bool(
		SchemaTextResolverScript.validate_schema(provider.get_config_schema()).get("ok", false)
	):
		return false
	for descriptor in provider.get_model_descriptors():
		if not (descriptor is Dictionary):
			return false
		var dynamic_params: Variant = descriptor.get("dynamic_params", [])
		if not (dynamic_params is Array):
			return false
		if not bool(SchemaTextResolverScript.validate_schema(dynamic_params).get("ok", false)):
			return false
	return true
