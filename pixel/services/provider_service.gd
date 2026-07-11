class_name PFProviderService
extends Node

## Provider 注册表与会话配置。
## M4-V1 只加载一个内置插件；凭据只保存在 provider 实例内存中，不写 settings/project。

signal provider_registered(provider_id: String)

const PluginAPIScript := preload("res://services/plugin_api.gd")
const BUILTIN_OPENAI_PLUGIN := "res://plugins/provider_openai/main.gd"

var _providers := {}
var _plugins := []


func _ready() -> void:
	load_builtin_plugin(BUILTIN_OPENAI_PLUGIN)


func _exit_tree() -> void:
	for plugin in _plugins:
		plugin._exit_app()
	for provider in _providers.values():
		if provider.has_method("clear_session_config"):
			provider.clear_session_config()
	_plugins.clear()
	_providers.clear()


func load_builtin_plugin(script_path: String) -> bool:
	var script: Script = load(script_path)
	if script == null:
		return false
	var plugin: Variant = script.new()
	if plugin == null or not plugin.has_method("_enter_app"):
		return false
	plugin._enter_app(PluginAPIScript.new(self))
	_plugins.append(plugin)
	return true


func register_provider(provider: PFProvider) -> bool:
	if provider == null or provider.get_api_version() != 1:
		return false
	var provider_id := provider.get_id().strip_edges()
	if provider_id.is_empty() or _providers.has(provider_id):
		return false
	if provider.has_method("attach_request_host"):
		provider.attach_request_host(self)
	_providers[provider_id] = provider
	provider_registered.emit(provider_id)
	return true


func get_provider(provider_id: String) -> PFProvider:
	return _providers.get(provider_id)


func get_provider_ids() -> Array:
	var ids := _providers.keys()
	ids.sort()
	return ids


func configure_session(provider_id: String, config: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return {"code": "invalid_request", "message": "Provider is not registered"}
	return provider.configure(config)


func clear_session(provider_id: String) -> void:
	var provider := get_provider(provider_id)
	if provider != null and provider.has_method("clear_session_config"):
		provider.clear_session_config()


func has_session_credentials(provider_id: String) -> bool:
	var provider := get_provider(provider_id)
	return (
		provider != null
		and provider.has_method("has_session_credentials")
		and provider.has_session_credentials()
	)


func generate(provider_id: String, request: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	return provider.generate(request) if provider != null else null
