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
const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const SchemaTextResolverScript := preload("res://services/schema_text_resolver.gd")
const BUILTIN_PROVIDER_PLUGINS := [
	"res://plugins/provider_openai/main.gd",
	"res://plugins/provider_retrodiffusion/main.gd",
]
const API_VERSION := 2
const AUTOMATION_PROVIDER := "mock"
const VALIDATION_STATES := ["unconfigured", "configured", "validating", "verified", "invalid"]
const MOCK_MODEL_DESCRIPTOR := {
	"provider_id": "mock",
	"model_id": "pixel_mock_v1",
	"display_name": "PixelForge Mock",
	"is_default": true,
	"ui_scope": "main",
	"provider_meta_keys": [],
	"capabilities":
	{
		"txt2img": true,
		"img2img": true,
		"max_reference_images": 16,
		"max_batch": 16,
		"target_size_constraints":
		{
			"min_width": 1,
			"max_width": 512,
			"width_step": 1,
			"min_height": 1,
			"max_height": 512,
			"height_step": 1,
			"allowed_sizes": [],
		},
		"provider_output_sizes": [],
		"native_pixel": true,
		"native_idempotency": false,
		"safe_validation": false,
		"seed": true,
		"transparent_bg": false,
		"cost_estimate": true,
	},
	"dynamic_params": [],
}

var load_builtin_plugins := true
var _providers := {}
var _plugins := []
var _validation_states := {}
var _credential_store: RefCounted = null
var _automation_mock_enabled := false
var _verified_config_fingerprints := {}


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


func register_provider(provider: PFProvider) -> Dictionary:
	# The version call is deliberately the only operation before the hard gate.
	if provider == null or provider.get_api_version() != API_VERSION:
		return _registration_failure("unsupported_provider_api_version", "api_version")
	var descriptors := provider.get_model_descriptors()
	var provider_id := _provider_id_from_descriptors(descriptors)
	if provider_id.is_empty() or _providers.has(provider_id):
		return _registration_failure("invalid_provider_descriptor", "provider_id")
	if not _model_descriptors_are_valid(provider_id, descriptors):
		return _registration_failure("invalid_provider_descriptor", "model_descriptors")
	var schema := provider.get_config_schema()
	if not _config_schema_is_valid(schema) or not _schema_text_is_valid(schema):
		return _registration_failure("invalid_provider_schema", "config_schema")
	if provider.has_method("attach_request_host"):
		provider.attach_request_host(self)
	_providers[provider_id] = provider
	_validation_states[provider_id] = {"state": "unconfigured", "message": ""}
	_configure_from_storage(provider_id)
	provider_registered.emit(provider_id)
	return {"ok": true, "provider_id": provider_id}


func unregister_provider(provider_id: String) -> bool:
	if not _providers.has(provider_id):
		return false
	var provider: Variant = _providers[provider_id]
	if provider.has_method("clear_session_config"):
		provider.clear_session_config()
	_providers.erase(provider_id)
	_validation_states.erase(provider_id)
	_verified_config_fingerprints.erase(provider_id)
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
	var descriptors: Array[Dictionary] = []
	if _automation_mock_enabled:
		descriptors.append(MOCK_MODEL_DESCRIPTOR.duplicate(true))
	for provider_id in get_provider_ids():
		if not _provider_can_generate(String(provider_id)):
			continue
		descriptors.append_array(get_model_descriptors(String(provider_id)))
	return descriptors


func get_model_descriptor(provider_id: String, model_id: String = "") -> Dictionary:
	if _automation_mock_enabled and provider_id == AUTOMATION_PROVIDER:
		var requested := model_id.strip_edges()
		return (
			MOCK_MODEL_DESCRIPTOR.duplicate(true)
			if requested.is_empty() or requested == MOCK_MODEL_DESCRIPTOR["model_id"]
			else {}
		)
	var provider := get_provider(provider_id)
	return (
		ProviderContractV2.get_model_descriptor(provider.get_model_descriptors(), model_id)
		if provider != null
		else {}
	)


func resolve_model_id(provider_id: String, model_id: String = "") -> String:
	if _automation_mock_enabled and provider_id == AUTOMATION_PROVIDER:
		var requested := model_id.strip_edges()
		return (
			String(MOCK_MODEL_DESCRIPTOR["model_id"])
			if requested.is_empty() or requested == MOCK_MODEL_DESCRIPTOR["model_id"]
			else ""
		)
	var provider := get_provider(provider_id)
	return (
		ProviderContractV2.resolve_model_id(provider.get_model_descriptors(), model_id)
		if provider != null
		else ""
	)


func validate_generation_request(provider_id: String, request: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return {"code": "invalid_provider", "field": "provider_id", "args": {}}
	return ProviderContractV2.validate_request_for_provider(
		request, provider_id, provider.get_model_descriptors()
	)


func get_selectable_provider_ids() -> Array:
	var ids := [AUTOMATION_PROVIDER] if _automation_mock_enabled else []
	for provider_id in get_provider_ids():
		if _provider_can_generate(String(provider_id)):
			ids.append(String(provider_id))
	return ids


func get_default_provider_id() -> String:
	var selectable := get_selectable_provider_ids()
	if selectable.is_empty():
		return ""
	var provider_id := String(SettingsService.get_setting("provider", "default_id", ""))
	return provider_id if selectable.has(provider_id) else String(selectable[0])


func set_default_provider_id(provider_id: String) -> bool:
	if not get_selectable_provider_ids().has(provider_id):
		return false
	SettingsService.set_setting("provider", "default_id", provider_id)
	return true


func enable_automation_mock_for_tests() -> void:
	## Explicit automation-only substitute; production startup never calls this path.
	_automation_mock_enabled = true


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
	var effective_config := _effective_provider_config(provider_id, config)
	var configure_error: Variant = provider.configure(effective_config)
	if configure_error != null:
		return configure_error
	var tested_fingerprint := String(_verified_config_fingerprints.get(provider_id, ""))
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
	SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
	configure_error = _configure_from_storage(provider_id)
	if configure_error != null:
		return configure_error
	var fingerprint := _provider_config_fingerprint(_effective_provider_config(provider_id))
	var remains_verified := not fingerprint.is_empty() and tested_fingerprint == fingerprint
	if not remains_verified:
		_verified_config_fingerprints.erase(provider_id)
	SettingsService.set_setting(
		_provider_settings_section(provider_id), "validated", remains_verified
	)
	_set_validation_state(
		provider_id,
		"verified" if remains_verified else "configured",
		(
			LocalizationService.text("PROVIDER_PING_SUCCESS", "Connection successful")
			if remains_verified
			else _configured_message(provider)
		)
	)
	provider_config_changed.emit(provider_id)
	return {"ok": true}


func restore_provider_config(provider_id: String) -> void:
	_verified_config_fingerprints.erase(provider_id)
	_configure_from_storage(provider_id)


func delete_provider_credentials(provider_id: String) -> Error:
	var error: Error = _credential_store.delete_provider(provider_id)
	var provider := get_provider(provider_id)
	if provider != null and provider.has_method("clear_session_config"):
		provider.clear_session_config()
	SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
	_verified_config_fingerprints.erase(provider_id)
	_set_validation_state(
		provider_id,
		"unconfigured",
		LocalizationService.text("PROVIDER_STATUS_CREDENTIALS_REMOVED", "Credentials removed")
	)
	provider_config_changed.emit(provider_id)
	return error


func validate_provider(provider_id: String, draft_config: Dictionary = {}) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null or not _safe_validation(provider):
		return null
	var is_draft := not draft_config.is_empty()
	var effective_config := _effective_provider_config(provider_id, draft_config)
	var configure_error: Variant = provider.configure(effective_config)
	if configure_error != null:
		var configure_code := (
			String(configure_error.get("code", "protocol_error"))
			if configure_error is Dictionary
			else "protocol_error"
		)
		_set_validation_outcome(provider_id, configure_code)
		return null
	var task: Variant = provider.validate_credentials()
	if task == null:
		return null
	var fingerprint := _provider_config_fingerprint(effective_config)
	_set_validation_state(
		provider_id,
		"validating",
		LocalizationService.text("PROVIDER_PING_TESTING", "Testing connection…")
	)
	task.finished.connect(
		func(result: Variant) -> void:
			var outcome := "success"
			if result is Dictionary:
				outcome = String(result.get("status", "success"))
			if outcome == "success":
				_verified_config_fingerprints[provider_id] = fingerprint
				if not is_draft:
					SettingsService.set_setting(
						_provider_settings_section(provider_id), "validated", true
					)
			else:
				_verified_config_fingerprints.erase(provider_id)
			_set_validation_outcome(provider_id, outcome)
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			if not is_draft:
				SettingsService.set_setting(
					_provider_settings_section(provider_id), "validated", false
				)
			_verified_config_fingerprints.erase(provider_id)
			_set_validation_outcome(provider_id, String(error.get("code", "protocol_error")))
	)
	task.canceled.connect(
		func() -> void:
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text(
					"PROVIDER_STATUS_VALIDATION_CANCELED", "Validation canceled"
				)
			)
	)
	return task


func get_validation_state(provider_id: String) -> String:
	return String(_validation_states.get(provider_id, {}).get("state", "unconfigured"))


func get_validation_message(provider_id: String) -> String:
	return String(_validation_states.get(provider_id, {}).get("message", ""))


func generate(provider_id: String, request: Dictionary) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return null
	if not _provider_can_generate(provider_id):
		return null
	var validation_issue: Variant = validate_generation_request(provider_id, request)
	if validation_issue != null:
		return validation_issue
	var task: Variant = provider.generate(request)
	if task != null and not _safe_validation(provider):
		task.completed.connect(
			func(_result: Variant) -> void:
				SettingsService.set_setting(
					_provider_settings_section(provider_id), "validated", true
				)
				_set_validation_state(
					provider_id,
					"verified",
					LocalizationService.text("PROVIDER_STATUS_VERIFIED", "Credentials verified")
				)
		)
		task.failed.connect(
			func(error: Dictionary) -> void:
				if String(error.get("code", "")) == "auth_failed":
					SettingsService.set_setting(
						_provider_settings_section(provider_id), "validated", false
					)
					_set_validation_state(
						provider_id,
						"invalid",
						LocalizationService.text(
							"PROVIDER_STATUS_INVALID", "Credentials are invalid"
						)
					)
		)
	return task


func _configure_from_storage(provider_id: String) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null:
		return _error("invalid_request", "Provider is not registered")
	var config := _effective_provider_config(provider_id)
	var has_required_secret := true
	for field in provider.get_config_schema():
		var key := String(field.get("key", ""))
		if key.is_empty():
			continue
		if String(field.get("kind", "")) == "password":
			if bool(field.get("required", false)) and String(config.get(key, "")).is_empty():
				has_required_secret = false
	if not has_required_secret:
		if provider.has_method("clear_session_config"):
			provider.clear_session_config()
		_set_validation_state(provider_id, "unconfigured", "")
		return null
	var error: Variant = provider.configure(config)
	if error == null:
		if bool(
			SettingsService.get_setting(_provider_settings_section(provider_id), "validated", false)
		):
			_verified_config_fingerprints[provider_id] = _provider_config_fingerprint(config)
			_set_validation_state(
				provider_id,
				"verified",
				LocalizationService.text("PROVIDER_STATUS_VERIFIED", "Credentials verified")
			)
		else:
			_set_validation_state(provider_id, "configured", _configured_message(provider))
	return error


func _effective_provider_config(provider_id: String, draft_config: Dictionary = {}) -> Dictionary:
	var provider := get_provider(provider_id)
	if provider == null:
		return {}
	var config := {}
	for field in provider.get_config_schema():
		var key := String(field.get("key", ""))
		if key.is_empty():
			continue
		var kind := String(field.get("kind", ""))
		if kind == "password":
			var draft_secret := String(draft_config.get(key, "")).strip_edges()
			config[key] = (
				draft_secret
				if not draft_secret.is_empty()
				else _credential_store.get_secret(provider_id, key)
			)
		else:
			config[key] = (
				draft_config[key]
				if draft_config.has(key)
				else SettingsService.get_setting(
					_provider_settings_section(provider_id), key, field.get("default")
				)
			)
	return config


func _provider_config_fingerprint(config: Dictionary) -> String:
	if config.is_empty():
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(JSON.stringify(config).to_utf8_buffer())
	return context.finish().hex_encode()


func _set_validation_outcome(provider_id: String, outcome: String) -> void:
	match outcome:
		"success":
			_set_validation_state(
				provider_id,
				"verified",
				LocalizationService.text("PROVIDER_PING_SUCCESS", "Connection successful")
			)
		"auth_failed":
			_set_validation_state(
				provider_id,
				"invalid",
				LocalizationService.text("PROVIDER_PING_AUTH_FAILED", "Authentication failed")
			)
		"model_unconfirmed":
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text(
					"PROVIDER_PING_MODEL_UNCONFIRMED",
					"Service reached, but the model could not be confirmed"
				)
			)
		"rate_limited":
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text("PROVIDER_PING_RATE_LIMITED", "Service is rate limited")
			)
		"timeout":
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text("PROVIDER_PING_TIMEOUT", "Connection timed out")
			)
		"network":
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text("PROVIDER_PING_NETWORK_ERROR", "Network or TLS error")
			)
		_:
			_set_validation_state(
				provider_id,
				"configured",
				LocalizationService.text("PROVIDER_PING_PROTOCOL_ERROR", "Protocol error")
			)


func _set_validation_state(provider_id: String, state: String, message: String) -> void:
	if state not in VALIDATION_STATES:
		return
	_validation_states[provider_id] = {"state": state, "message": message}
	provider_validation_changed.emit(provider_id, state, message)


func _safe_validation(provider: PFProvider) -> bool:
	var descriptor := ProviderContractV2.get_model_descriptor(provider.get_model_descriptors())
	return bool(descriptor.get("capabilities", {}).get("safe_validation", true))


func _provider_can_generate(provider_id: String) -> bool:
	var provider := get_provider(provider_id)
	if provider == null:
		return false
	var state := get_validation_state(provider_id)
	return state == "verified" or (state == "configured" and not _safe_validation(provider))


func _configured_message(provider: PFProvider) -> String:
	if _safe_validation(provider):
		return LocalizationService.text(
			"PROVIDER_STATUS_SAVED_VALIDATE", "Saved; validate before use"
		)
	return LocalizationService.text(
		"PROVIDER_STATUS_SAVED_FIRST_GENERATION",
		"Saved; credentials will be verified on the first real generation"
	)


func _provider_id_from_descriptors(descriptors: Array[Dictionary]) -> String:
	if descriptors.is_empty():
		return ""
	return String(descriptors[0].get("provider_id", "")).strip_edges()


func _registration_failure(code: String, field: String) -> Dictionary:
	return {
		"ok": false,
		"error": {"code": code, "field": field, "args": {"supported": API_VERSION}},
	}


func _config_schema_is_valid(schema: Array[Dictionary]) -> bool:
	var ids := {}
	var valid := true
	for field in schema:
		var kind := String(field.get("kind", ""))
		var keys := ["default", "help_key", "key", "kind", "label_key", "required"]
		if kind == "enum":
			keys.append("values")
		if not _has_exact_keys(field, keys):
			valid = false
			break
		var key := String(field.get("key", ""))
		if not _matches("^[a-z][a-z0-9_]{0,63}$", key) or ids.has(key):
			valid = false
			break
		ids[key] = true
		if not kind in ["string", "password", "bool", "enum"]:
			valid = false
			break
		if not (field["required"] is bool):
			valid = false
			break
		if not (field["label_key"] is String) or String(field["label_key"]).is_empty():
			valid = false
			break
		if not (field["help_key"] is String) or String(field["help_key"]).is_empty():
			valid = false
			break
		match kind:
			"string":
				if not (field["default"] is String):
					valid = false
			"password":
				if not (field["default"] is String) or not String(field["default"]).is_empty():
					valid = false
			"bool":
				if not (field["default"] is bool):
					valid = false
			"enum":
				if not (field["default"] is String) or not (field["values"] is Array):
					valid = false
				elif field["values"].is_empty() or not field["values"].has(field["default"]):
					valid = false
				else:
					var values := {}
					for value in field["values"]:
						if not (value is String) or values.has(value):
							valid = false
							break
						values[value] = true
		if not valid:
			break
	return valid


func _schema_text_is_valid(schema: Array[Dictionary]) -> bool:
	var result: Dictionary = SchemaTextResolverScript.validate_schema(schema)
	return bool(result.get("ok", false))


func _provider_settings_section(provider_id: String) -> String:
	return "provider_%s" % provider_id


func _model_descriptors_are_valid(provider_id: String, descriptors: Array[Dictionary]) -> bool:
	var model_ids := {}
	var default_count := 0
	var shared_meta_keys: Variant = null
	var valid := not descriptors.is_empty()
	var descriptor_keys := [
		"capabilities",
		"display_name",
		"dynamic_params",
		"is_default",
		"model_id",
		"provider_id",
		"provider_meta_keys",
		"ui_scope",
	]
	var capability_keys := [
		"cost_estimate",
		"img2img",
		"max_batch",
		"max_reference_images",
		"native_idempotency",
		"native_pixel",
		"provider_output_sizes",
		"safe_validation",
		"seed",
		"target_size_constraints",
		"transparent_bg",
		"txt2img",
	]
	for descriptor in descriptors:
		if not _has_exact_keys(descriptor, descriptor_keys):
			valid = false
			break
		if String(descriptor.get("provider_id", "")) != provider_id:
			valid = false
			break
		var model_id := String(descriptor.get("model_id", "")).strip_edges()
		if model_id.is_empty() or model_ids.has(model_id):
			valid = false
			break
		model_ids[model_id] = true
		if String(descriptor.get("display_name", "")).strip_edges().is_empty():
			valid = false
			break
		if not (descriptor.get("is_default") is bool) or descriptor.get("ui_scope") != "main":
			valid = false
			break
		default_count += 1 if bool(descriptor.get("is_default", false)) else 0
		var capabilities: Dictionary = descriptor.get("capabilities", {})
		if not _has_exact_keys(capabilities, capability_keys):
			valid = false
			break
		if not _capabilities_are_valid(capabilities):
			valid = false
			break
		var meta_keys: Variant = descriptor.get("provider_meta_keys")
		if not _provider_meta_keys_are_valid(meta_keys):
			valid = false
			break
		if shared_meta_keys == null:
			shared_meta_keys = meta_keys.duplicate()
		elif shared_meta_keys != meta_keys:
			valid = false
			break
		if not _dynamic_params_are_valid(descriptor.get("dynamic_params")):
			valid = false
			break
	return valid and default_count == 1


func _capabilities_are_valid(capabilities: Dictionary) -> bool:
	var valid := true
	for flag in [
		"txt2img",
		"img2img",
		"native_pixel",
		"native_idempotency",
		"safe_validation",
		"seed",
		"transparent_bg",
		"cost_estimate",
	]:
		if not (capabilities[flag] is bool):
			valid = false
			break
	for count_key in ["max_reference_images", "max_batch"]:
		if not (capabilities[count_key] is int) or int(capabilities[count_key]) < 0:
			valid = false
			break
	if int(capabilities["max_batch"]) < 1:
		valid = false
	var constraints: Variant = capabilities["target_size_constraints"]
	if not (constraints is Dictionary) or not _target_constraints_are_valid(constraints):
		valid = false
	var provider_sizes: Variant = capabilities["provider_output_sizes"]
	if not (provider_sizes is Array):
		valid = false
	else:
		for size_value in provider_sizes:
			if not _is_positive_int_pair(size_value):
				valid = false
				break
		valid = valid and provider_sizes.is_empty() == bool(capabilities["native_pixel"])
	return valid


func _target_constraints_are_valid(constraints: Dictionary) -> bool:
	var keys := [
		"allowed_sizes",
		"height_step",
		"max_height",
		"max_width",
		"min_height",
		"min_width",
		"width_step",
	]
	if not _has_exact_keys(constraints, keys):
		return false
	for key in keys:
		if key == "allowed_sizes":
			continue
		if not (constraints[key] is int) or int(constraints[key]) < 1:
			return false
	if (
		int(constraints["min_width"]) > int(constraints["max_width"])
		or int(constraints["min_height"]) > int(constraints["max_height"])
	):
		return false
	if not (constraints["allowed_sizes"] is Array):
		return false
	for size_value in constraints["allowed_sizes"]:
		if not _is_positive_int_pair(size_value):
			return false
	return true


func _provider_meta_keys_are_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	var previous := ""
	for key_value in value:
		if not (key_value is String):
			return false
		var key := String(key_value)
		if (
			not _matches("^[a-z][a-z0-9_]{0,63}$", key)
			or (not previous.is_empty() and key <= previous)
		):
			return false
		previous = key
	return true


func _dynamic_params_are_valid(value: Variant) -> bool:
	if not (value is Array):
		return false
	var ids := {}
	var valid := true
	var required_keys := [
		"advanced",
		"default",
		"help_key",
		"key",
		"kind",
		"label_key",
		"max",
		"min",
		"required",
		"step",
		"template_safe",
		"values",
	]
	for raw_spec in value:
		if not (raw_spec is Dictionary):
			valid = false
			break
		var spec: Dictionary = raw_spec
		var allowed_keys := required_keys.duplicate()
		allowed_keys.append("visible_when")
		if not _has_exact_keys(spec, allowed_keys, required_keys):
			valid = false
			break
		var key := String(spec.get("key", ""))
		if not _matches("^[a-z][a-z0-9_]{0,63}$", key) or ids.has(key):
			valid = false
			break
		ids[key] = true
		if not String(spec.get("kind", "")) in ["bool", "int", "float", "enum", "string"]:
			valid = false
			break
		if (
			not (spec["required"] is bool)
			or not (spec["advanced"] is bool)
			or not (spec["template_safe"] is bool)
		):
			valid = false
			break
		if not (spec["values"] is Array):
			valid = false
			break
		if not (spec["label_key"] is String) or String(spec["label_key"]).is_empty():
			valid = false
			break
		if not (spec["help_key"] is String) or String(spec["help_key"]).is_empty():
			valid = false
			break
		if not _dynamic_param_value_shape_is_valid(spec):
			valid = false
			break
		if spec.has("visible_when") and spec["visible_when"] != {"mode": "img2img"}:
			valid = false
			break
	return valid


func _dynamic_param_value_shape_is_valid(spec: Dictionary) -> bool:
	var values: Array = spec["values"]
	match String(spec["kind"]):
		"bool":
			return (
				spec["default"] is bool
				and values.is_empty()
				and spec["min"] == null
				and spec["max"] == null
				and spec["step"] == null
			)
		"int":
			return (
				spec["default"] is int
				and values.is_empty()
				and spec["min"] is int
				and spec["max"] is int
				and spec["step"] is int
				and int(spec["min"]) <= int(spec["default"])
				and int(spec["default"]) <= int(spec["max"])
				and int(spec["step"]) > 0
			)
		"float":
			return (
				(spec["default"] is float or spec["default"] is int)
				and values.is_empty()
				and (spec["min"] is float or spec["min"] is int)
				and (spec["max"] is float or spec["max"] is int)
				and (spec["step"] is float or spec["step"] is int)
				and float(spec["min"]) <= float(spec["default"])
				and float(spec["default"]) <= float(spec["max"])
				and float(spec["step"]) > 0.0
			)
		"enum":
			return (
				spec["default"] is String
				and not values.is_empty()
				and values.has(spec["default"])
				and _unique_strings(values)
				and spec["min"] == null
				and spec["max"] == null
				and spec["step"] == null
			)
		"string":
			return (
				spec["default"] is String
				and values.is_empty()
				and spec["min"] == null
				and spec["max"] == null
				and spec["step"] == null
			)
	return false


func _unique_strings(values: Array) -> bool:
	var seen := {}
	for value in values:
		if not (value is String) or seen.has(value):
			return false
		seen[value] = true
	return true


func _has_exact_keys(value: Dictionary, allowed_keys: Array, required_keys: Array = []) -> bool:
	var required := allowed_keys if required_keys.is_empty() else required_keys
	for key in value.keys():
		if not allowed_keys.has(String(key)):
			return false
	for key in required:
		if not value.has(key):
			return false
	return true


func _is_positive_int_pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value[0] is int
		and value[1] is int
		and int(value[0]) > 0
		and int(value[1]) > 0
	)


func _matches(pattern: String, value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(pattern) == OK and expression.search(value) != null


func _error(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "recoverable": true}
