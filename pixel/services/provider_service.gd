# gdlint: disable=max-public-methods
class_name PFProviderService
extends Node

## Provider registry, encrypted credential lifecycle, validation state, and default selection.
## contract: 02-contracts/PROVIDER-API.md §3；providers receive decrypted values only in memory.

signal provider_registered(provider_id: String)
signal provider_config_changed(provider_id: String)
signal provider_validation_changed(provider_id: String, state: String, message: String)

const PluginAPIScript := preload("res://services/plugin_api.gd")
const CredentialStoreScript := preload("res://services/credential_store.gd")
const BUILTIN_PROVIDER_PLUGINS := [
	"res://plugins/provider_openai/main.gd",
	"res://plugins/provider_retrodiffusion/main.gd",
	"res://plugins/bridge_comfyui/main.gd",
]
const API_VERSION := 1
const DEFAULT_PROVIDER := "mock"
const MOCK_MODEL_DESCRIPTOR := {
	"provider_id": "mock",
	"model_id": "pixel_mock_v1",
	"display_name": "PixelForge Mock",
	"is_default": true,
	"capabilities":
	{
		"txt2img": true,
		"img2img": true,
		"max_reference_images": 16,
		"output_size_constraints": {"min_side": 1, "max_side": 512},
		"max_batch": 16,
		"seed": true,
		"transparent_bg": false,
		"cost_estimate": true,
	},
}

var load_builtin_plugins := true
var _providers := {}
var _plugins := []
var _validation_states := {}
var _credential_store: RefCounted = null


func _ready() -> void:
	if _credential_store == null:
		_credential_store = CredentialStoreScript.new()
	if load_builtin_plugins:
		for plugin_path in BUILTIN_PROVIDER_PLUGINS:
			load_builtin_plugin(plugin_path)


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
	plugin._enter_app(PluginAPIScript.new(null, self, script_path.get_base_dir().get_file()))
	_plugins.append(plugin)
	return true


func register_provider(provider: PFProvider) -> bool:
	if provider == null or provider.get_api_version() != API_VERSION:
		return false
	var provider_id := provider.get_id().strip_edges()
	if provider_id.is_empty() or _providers.has(provider_id):
		return false
	var descriptors := provider.get_model_descriptors()
	if not descriptors.is_empty() and not _model_descriptors_are_valid(provider_id, descriptors):
		return false
	if provider.has_method("attach_request_host"):
		provider.attach_request_host(self)
	_providers[provider_id] = provider
	_validation_states[provider_id] = {"state": "unconfigured", "message": ""}
	_configure_from_storage(provider_id)
	provider_registered.emit(provider_id)
	return true


func unregister_provider(provider_id: String) -> bool:
	if not _providers.has(provider_id):
		return false
	var provider: Variant = _providers[provider_id]
	if provider.has_method("clear_session_config"):
		provider.clear_session_config()
	_providers.erase(provider_id)
	_validation_states.erase(provider_id)
	return true


func get_provider(provider_id: String) -> PFProvider:
	return _providers.get(provider_id)


func get_provider_ids() -> Array:
	var ids := _providers.keys()
	ids.sort()
	return ids


func get_model_descriptors(provider_id: String = "") -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	var provider_ids := [provider_id] if not provider_id.is_empty() else get_provider_ids()
	for registered_id in provider_ids:
		var provider := get_provider(String(registered_id))
		if provider == null:
			continue
		for descriptor in provider.get_model_descriptors():
			descriptors.append(descriptor.duplicate(true))
	return descriptors


func get_selectable_model_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = [MOCK_MODEL_DESCRIPTOR.duplicate(true)]
	for provider_id in get_provider_ids():
		if get_validation_state(String(provider_id)) != "verified":
			continue
		descriptors.append_array(get_model_descriptors(String(provider_id)))
	return descriptors


func get_model_descriptor(provider_id: String, model_id: String = "") -> Dictionary:
	if provider_id == DEFAULT_PROVIDER:
		var requested := model_id.strip_edges()
		return (
			MOCK_MODEL_DESCRIPTOR.duplicate(true)
			if requested.is_empty() or requested == MOCK_MODEL_DESCRIPTOR["model_id"]
			else {}
		)
	var provider := get_provider(provider_id)
	return provider.get_model_descriptor(model_id) if provider != null else {}


func resolve_model_id(provider_id: String, model_id: String = "") -> String:
	if provider_id == DEFAULT_PROVIDER:
		var requested := model_id.strip_edges()
		return (
			String(MOCK_MODEL_DESCRIPTOR["model_id"])
			if requested.is_empty() or requested == MOCK_MODEL_DESCRIPTOR["model_id"]
			else ""
		)
	var provider := get_provider(provider_id)
	return provider.resolve_model_id(model_id) if provider != null else ""


func validate_generation_request(provider_id: String, request: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return _error("invalid_request", "Provider is not registered")
	return provider.validate_generation_request(request)


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
	if provider == null:
		return null
	return provider.generate(request)


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


func _model_descriptors_are_valid(provider_id: String, descriptors: Array[Dictionary]) -> bool:
	var model_ids := {}
	var default_count := 0
	var required_capabilities := [
		"txt2img",
		"max_reference_images",
		"max_batch",
		"seed",
		"transparent_bg",
		"cost_estimate",
	]
	for descriptor in descriptors:
		if String(descriptor.get("provider_id", "")) != provider_id:
			return false
		var model_id := String(descriptor.get("model_id", "")).strip_edges()
		if model_id.is_empty() or model_ids.has(model_id):
			return false
		model_ids[model_id] = true
		if String(descriptor.get("display_name", "")).strip_edges().is_empty():
			return false
		default_count += 1 if bool(descriptor.get("is_default", false)) else 0
		var capabilities: Dictionary = descriptor.get("capabilities", {})
		for key in required_capabilities:
			if not capabilities.has(key):
				return false
		if not capabilities.has("output_sizes") and not capabilities.has("output_size_constraints"):
			return false
	return default_count == 1


func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "recoverable": true}
