extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")
const CredentialStoreScript := preload("res://services/credential_store.gd")
const FakeProviderScript := preload("res://tests/fixtures/providers/fake_provider.gd")

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
	assert_true(_service.register_provider(FakeProviderScript.new()))


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
	assert_true(restarted.register_provider(provider))

	assert_eq(provider.configured_key, "fixture-good-key")
	assert_eq(provider.configured_endpoint, "https://restart")
	assert_eq(restarted.get_validation_state("fixture_provider"), "configured")
	assert_eq(restarted.delete_provider_credentials("fixture_provider"), OK)
	assert_eq(provider.configured_key, "")


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _remove_test_credentials() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
