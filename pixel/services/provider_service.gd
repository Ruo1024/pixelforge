class_name PFProviderService
extends Node

## Provider registry, encrypted credential lifecycle, validation state, and default selection.
## contract: 02-contracts/PROVIDER-API.md §3；providers receive decrypted values only in memory.

signal provider_registered(provider_id: String)
signal provider_config_changed(provider_id: String)
signal provider_validation_changed(provider_id: String, state: String, message: String)

const PluginAPIScript := preload("res://services/plugin_api.gd")
const CredentialStoreScript := preload("res://services/credential_store.gd")
const BUILTIN_OPENAI_PLUGIN := "res://plugins/provider_openai/main.gd"
const API_VERSION := 1
const DEFAULT_PROVIDER := "mock"

var load_builtin_plugins := true
var _providers := {}
var _plugins := []
var _validation_states := {}
var _credential_store: RefCounted = null


func _ready() -> void:
	if _credential_store == null:
		_credential_store = CredentialStoreScript.new()
	if load_builtin_plugins:
		load_builtin_plugin(BUILTIN_OPENAI_PLUGIN)


func _exit_tree() -> void:
	for plugin in _plugins:
		plugin._exit_app()
	for provider in _providers.values():
		if provider.has_method("clear_session_config"):
			provider.clear_session_config()
	_plugins.clear()
	_providers.clear()


func set_credential_store(store: RefCounted) -> void:
	_credential_store = store


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
	if provider == null or provider.get_api_version() != API_VERSION:
		return false
	var provider_id := provider.get_id().strip_edges()
	if provider_id.is_empty() or _providers.has(provider_id):
		return false
	if provider.has_method("attach_request_host"):
		provider.attach_request_host(self)
	_providers[provider_id] = provider
	_validation_states[provider_id] = {"state": "unconfigured", "message": ""}
	_configure_from_storage(provider_id)
	provider_registered.emit(provider_id)
	return true


func get_provider(provider_id: String) -> PFProvider:
	return _providers.get(provider_id)


func get_provider_ids() -> Array:
	var ids := _providers.keys()
	ids.sort()
	return ids


func get_selectable_provider_ids() -> Array:
	var ids := [DEFAULT_PROVIDER]
	for provider_id in get_provider_ids():
		if get_validation_state(String(provider_id)) == "verified":
			ids.append(String(provider_id))
	return ids


func get_default_provider_id() -> String:
	var provider_id := String(
		SettingsService.get_setting("provider", "default_id", DEFAULT_PROVIDER)
	)
	return provider_id if get_selectable_provider_ids().has(provider_id) else DEFAULT_PROVIDER


func set_default_provider_id(provider_id: String) -> bool:
	if not get_selectable_provider_ids().has(provider_id):
		return false
	SettingsService.set_setting("provider", "default_id", provider_id)
	return true


func get_provider_config(provider_id: String) -> Dictionary:
	var provider := get_provider(provider_id)
	if provider == null:
		return {}
	var result := {}
	for field in provider.get_config_schema():
		var key := String(field.get("key", ""))
		if key.is_empty():
			continue
		if String(field.get("kind", "")) == "password":
			result[key] = ""
			result["%s_saved" % key] = _credential_store.has_secret(provider_id, key)
		else:
			result[key] = SettingsService.get_setting(
				_provider_settings_section(provider_id), key, field.get("default")
			)
	return result


func save_provider_config(provider_id: String, config: Dictionary) -> Dictionary:
	var provider := get_provider(provider_id)
	if provider == null:
		return _error("invalid_request", "Provider is not registered")
	for field in provider.get_config_schema():
		var key := String(field.get("key", ""))
		if key.is_empty() or not config.has(key):
			continue
		if String(field.get("kind", "")) == "password":
			var secret := String(config[key]).strip_edges()
			if not secret.is_empty():
				var save_error: Error = _credential_store.set_secret(provider_id, key, secret)
				if save_error != OK:
					return _error("provider_internal", "Credential could not be saved")
		else:
			SettingsService.set_setting(_provider_settings_section(provider_id), key, config[key])
	var configure_error: Variant = _configure_from_storage(provider_id)
	if configure_error != null:
		return configure_error
	SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
	_set_validation_state(provider_id, "configured", "Saved; validate before use")
	provider_config_changed.emit(provider_id)
	return {"ok": true}


func delete_provider_credentials(provider_id: String) -> Error:
	var error: Error = _credential_store.delete_provider(provider_id)
	var provider := get_provider(provider_id)
	if provider != null and provider.has_method("clear_session_config"):
		provider.clear_session_config()
	SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
	_set_validation_state(provider_id, "unconfigured", "Credentials removed")
	provider_config_changed.emit(provider_id)
	return error


func validate_provider(provider_id: String) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return null
	var task: Variant = provider.validate_credentials()
	if task == null:
		return null
	_set_validation_state(provider_id, "validating", "Validating credentials…")
	task.finished.connect(
		func(_result: Variant) -> void:
			SettingsService.set_setting(_provider_settings_section(provider_id), "validated", true)
			_set_validation_state(provider_id, "verified", "Credentials verified")
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
			_set_validation_state(
				provider_id, "failed", String(error.get("message", "Validation failed"))
			)
	)
	task.canceled.connect(
		func() -> void: _set_validation_state(provider_id, "configured", "Validation canceled")
	)
	return task


func get_validation_state(provider_id: String) -> String:
	return String(_validation_states.get(provider_id, {}).get("state", "unconfigured"))


func get_validation_message(provider_id: String) -> String:
	return String(_validation_states.get(provider_id, {}).get("message", ""))


func configure_session(provider_id: String, config: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return _error("invalid_request", "Provider is not registered")
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


func _configure_from_storage(provider_id: String) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return _error("invalid_request", "Provider is not registered")
	var config := {}
	var has_required_secret := true
	for field in provider.get_config_schema():
		var key := String(field.get("key", ""))
		if key.is_empty():
			continue
		if String(field.get("kind", "")) == "password":
			var secret: String = _credential_store.get_secret(provider_id, key)
			if secret.is_empty():
				has_required_secret = false
			else:
				config[key] = secret
		else:
			config[key] = SettingsService.get_setting(
				_provider_settings_section(provider_id), key, field.get("default")
			)
	if not has_required_secret:
		return null
	var error: Variant = provider.configure(config)
	if error == null:
		if bool(
			SettingsService.get_setting(_provider_settings_section(provider_id), "validated", false)
		):
			_set_validation_state(provider_id, "verified", "Credentials verified previously")
		else:
			_set_validation_state(provider_id, "configured", "Saved; validate before use")
	return error


func _set_validation_state(provider_id: String, state: String, message: String) -> void:
	_validation_states[provider_id] = {"state": state, "message": message}
	provider_validation_changed.emit(provider_id, state, message)


func _provider_settings_section(provider_id: String) -> String:
	return "provider_%s" % provider_id


func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "recoverable": true}
