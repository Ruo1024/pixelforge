extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")
const CredentialStoreScript := preload("res://services/credential_store.gd")
const FakeProviderScript := preload("res://tests/fixtures/providers/fake_provider.gd")
const SentinelScanner := preload("res://tests/helpers/credential_sentinel_scanner.gd")

const TEST_PATH := "user://tests/m4_provider_service_credentials.cfg"

var _service: Node = null
var _queue: Node = null


func before_each() -> void:
	_remove_test_credentials()
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_service = ProviderServiceScript.new()
	_service.load_builtin_plugins = false
	_service.set_credential_store(CredentialStoreScript.new(TEST_PATH, "service-device", 64))
	add_child_autofree(_service)
	await wait_process_frames(1)
	assert_true(_service.register_provider(FakeProviderScript.new())["ok"])


func after_each() -> void:
	SettingsService.set_setting("provider", "default_id", "mock")
	SettingsService.set_setting("provider_fixture_provider", "validated", false)
	_remove_test_credentials()


func test_saved_provider_is_encrypted_validated_and_filtered_for_nodes() -> void:
	var result: Dictionary = _service.save_provider_config(
		"fixture_provider", {"api_key": "fixture-good-key", "endpoint": "https://local.fixture"}
	)

	assert_true(result["ok"])
	assert_eq(_service.get_validation_state("fixture_provider"), "configured")
	assert_eq(_service.get_selectable_provider_ids(), ["mock"])
	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	assert_not_null(file)
	assert_false(file.get_as_text().contains("fixture-good-key"))
	var task: Variant = _service.validate_provider("fixture_provider")
	assert_not_null(task)
	_queue.submit(task)
	assert_true(await _wait_until(func() -> bool: return _queue.is_idle()))
	assert_eq(_service.get_validation_state("fixture_provider"), "verified")
	assert_eq(_service.get_selectable_provider_ids(), ["mock", "fixture_provider"])
	assert_true(_service.set_default_provider_id("fixture_provider"))
	assert_eq(_service.get_default_provider_id(), "fixture_provider")


func test_saved_provider_configuration_decrypts_after_service_restart() -> void:
	assert_true(
		(
			_service
			. save_provider_config(
				"fixture_provider", {"api_key": "fixture-good-key", "endpoint": "https://restart"}
			)["ok"]
		)
	)
	var restarted := ProviderServiceScript.new()
	restarted.load_builtin_plugins = false
	restarted.set_credential_store(CredentialStoreScript.new(TEST_PATH, "service-device", 64))
	add_child_autofree(restarted)
	await wait_process_frames(1)
	var provider: Variant = FakeProviderScript.new()
	assert_true(restarted.register_provider(provider)["ok"])

	assert_eq(provider.configured_key, "fixture-good-key")
	assert_eq(provider.configured_endpoint, "https://restart")
	assert_eq(restarted.get_validation_state("fixture_provider"), "configured")
	assert_eq(restarted.delete_provider_credentials("fixture_provider"), OK)
	assert_eq(provider.configured_key, "")


func test_unsafe_validation_provider_is_offline_until_explicit_first_generation() -> void:
	var provider: Variant = _service.get_provider("fixture_provider")
	provider.safe_validation = false
	var result: Dictionary = _service.save_provider_config(
		"fixture_provider", {"api_key": "fixture-good-key", "endpoint": "https://local.fixture"}
	)

	assert_true(result["ok"])
	assert_eq(_service.get_validation_state("fixture_provider"), "configured")
	assert_string_contains(
		_service.get_validation_message("fixture_provider"), "first real generation"
	)
	assert_null(_service.validate_provider("fixture_provider"))
	assert_eq(_service.get_selectable_provider_ids(), ["mock", "fixture_provider"])
	var task: Variant = _service.generate("fixture_provider", _generation_request())
	assert_not_null(task)
	assert_true(task is PFProviderTaskV2)
	assert_true(
		await _wait_until(
			func() -> bool: return _service.get_validation_state("fixture_provider") == "verified"
		)
	)
	assert_eq(_service.get_validation_state("fixture_provider"), "verified")


func test_unsafe_validation_provider_auth_failure_becomes_invalid() -> void:
	var provider: Variant = _service.get_provider("fixture_provider")
	provider.safe_validation = false
	assert_true(
		(
			_service
			. save_provider_config(
				"fixture_provider",
				{"api_key": "fixture-bad-key", "endpoint": "https://local.fixture"}
			)["ok"]
		)
	)
	var task: Variant = _service.generate("fixture_provider", _generation_request())
	assert_not_null(task)
	assert_true(task is PFProviderTaskV2)
	assert_true(
		await _wait_until(
			func() -> bool: return _service.get_validation_state("fixture_provider") == "invalid"
		)
	)
	assert_eq(_service.get_validation_state("fixture_provider"), "invalid")
	assert_eq(_service.get_selectable_provider_ids(), ["mock"])


func test_unique_credential_sentinel_is_persisted_only_as_ciphertext() -> void:
	var result: Dictionary = _service.save_provider_config(
		"fixture_provider", {"api_key": SentinelScanner.VALUE, "endpoint": "https://local.fixture"}
	)

	assert_true(result["ok"])
	assert_false(SentinelScanner.file_contains(TEST_PATH, SentinelScanner.VALUE))
	var encrypted := FileAccess.get_file_as_string(TEST_PATH)
	assert_false(encrypted.is_empty())
	assert_false(encrypted.contains(SentinelScanner.VALUE))


func test_fake_v2_cancel_is_cached_and_orders_generation_before_cancel_terminal() -> void:
	var provider: Variant = _service.get_provider("fixture_provider")
	assert_null(
		provider.configure({"api_key": "fixture-good-key", "endpoint": "https://local.fixture"})
	)
	var request := _generation_request()
	request["request_id"] = "fixture-cancel"
	var generation: PFProviderTaskV2 = provider.generate(request)
	var terminals := []
	generation.canceled.connect(func(_request_id: String) -> void: terminals.append("generation"))
	var first: PFCancelTaskV2 = provider.cancel("fixture-cancel")
	var second: PFCancelTaskV2 = provider.cancel("fixture-cancel")
	first.resolved.connect(func(_result: Dictionary) -> void: terminals.append("cancel"))
	assert_same(first, second)
	assert_true(await _wait_until(func() -> bool: return terminals.size() == 2))
	assert_eq(terminals, ["generation", "cancel"])


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _generation_request() -> Dictionary:
	return {
		"run_id": "fixture-run",
		"request_id": "fixture-request",
		"idempotency_key": "fixture-idempotency",
		"provider_id": "fixture_provider",
		"mode": "txt2img",
		"model_id": "fixture-model",
		"prompt": "approved user action",
		"target_width": 8,
		"target_height": 8,
		"provider_output_size": [8, 8],
		"batch": 1,
		"seed": 0,
		"ref_images": [],
		"extra": {},
	}


func _remove_test_credentials() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
