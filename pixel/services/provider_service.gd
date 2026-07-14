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
const SCHEMA_TEXT_RESOLVER_PATH := "res://services/schema_text_resolver.gd"
const BUILTIN_PROVIDER_PLUGINS := [
	"res://plugins/provider_openai/main.gd",
	"res://plugins/provider_retrodiffusion/main.gd",
]
const API_VERSION := 2
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
		if not _provider_can_generate(String(provider_id)):
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
	return (
		ProviderContractV2.get_model_descriptor(provider.get_model_descriptors(), model_id)
		if provider != null
		else {}
	)


func resolve_model_id(provider_id: String, model_id: String = "") -> String:
	if provider_id == DEFAULT_PROVIDER:
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
	var ids := [DEFAULT_PROVIDER]
	for provider_id in get_provider_ids():
		if _provider_can_generate(String(provider_id)):
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
	_set_validation_state(provider_id, "configured", _configured_message(provider))
	provider_config_changed.emit(provider_id)
	return {"ok": true}


func delete_provider_credentials(provider_id: String) -> Error:
	var error: Error = _credential_store.delete_provider(provider_id)
	var provider := get_provider(provider_id)
	if provider != null and provider.has_method("clear_session_config"):
		provider.clear_session_config()
	SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
	_set_validation_state(
		provider_id,
		"unconfigured",
		LocalizationService.text("PROVIDER_STATUS_CREDENTIALS_REMOVED", "Credentials removed")
	)
	provider_config_changed.emit(provider_id)
	return error


func validate_provider(provider_id: String) -> Variant:
	var provider := get_provider(provider_id)
	if provider == null or not _safe_validation(provider):
		return null
	var task: Variant = provider.validate_credentials()
	if task == null:
		return null
	_set_validation_state(
		provider_id,
		"validating",
		LocalizationService.text("PROVIDER_STATUS_VALIDATING", "Validating credentials…")
	)
	task.finished.connect(
		func(_result: Variant) -> void:
			SettingsService.set_setting(_provider_settings_section(provider_id), "validated", true)
			_set_validation_state(
				provider_id,
				"verified",
				LocalizationService.text("PROVIDER_STATUS_VERIFIED", "Credentials verified")
			)
	)
	task.failed.connect(
		func(error: Dictionary) -> void:
			SettingsService.set_setting(_provider_settings_section(provider_id), "validated", false)
			_set_validation_state(
				provider_id,
				"invalid",
				LocalizationService.text("PROVIDER_STATUS_INVALID", "Credentials are invalid")
			)
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
			_set_validation_state(
				provider_id,
				"verified",
				LocalizationService.text("PROVIDER_STATUS_VERIFIED", "Credentials verified")
			)
		else:
			_set_validation_state(provider_id, "configured", _configured_message(provider))
	return error


func _set_validation_state(provider_id: String, state: String, message: String) -> void:
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
	if not ResourceLoader.exists(SCHEMA_TEXT_RESOLVER_PATH):
		return true
	var script: Script = load(SCHEMA_TEXT_RESOLVER_PATH)
	if script == null:
		return false
	var resolver: Variant = script.new()
	if resolver == null or not resolver.has_method("validate_schema"):
		return false
	var result: Variant = resolver.validate_schema(schema)
	return (
		result == null or result == true or (result is Dictionary and bool(result.get("ok", false)))
	)


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
