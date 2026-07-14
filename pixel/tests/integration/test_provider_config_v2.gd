extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")
const CredentialStoreScript := preload("res://services/credential_store.gd")
const ProviderSettingsDialogScript := preload("res://ui/dialogs/provider_settings_dialog.gd")
const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const RetroProviderScript := preload(
	"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd"
)
const FakeProviderScript := preload("res://tests/fixtures/providers/fake_provider.gd")

const TEST_PATH := "user://tests/b7_provider_config_v2.cfg"

var _service: Node = null
var _queue: Node = null


func before_each() -> void:
	_remove_test_credentials()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	SettingsService.set_setting("provider_fixture_provider", "validated", false)
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_service = ProviderServiceScript.new()
	_service.load_builtin_plugins = false
	_service.set_credential_store(CredentialStoreScript.new(TEST_PATH, "b7-config-device", 64))
	add_child_autofree(_service)
	await wait_process_frames(1)
	assert_true(_service.register_provider(FakeProviderScript.new())["ok"])


func after_each() -> void:
	SettingsService.set_setting("provider_fixture_provider", "validated", false)
	SettingsService.set_setting("provider_fixture_provider", "endpoint", "https://fixture.invalid")
	_remove_test_credentials()


func test_single_data_path_and_five_states() -> void:
	assert_false(_service.has_method("configure_session"))
	assert_false(_service.has_method("clear_session"))
	assert_false(_service.has_method("has_session_credentials"))
	assert_false(FileAccess.file_exists("res://ui/dialogs/openai_session_dialog.gd"))

	var provider: Variant = _service.get_provider("fixture_provider")
	assert_eq(_service.get_validation_state("fixture_provider"), "unconfigured")
	assert_true(
		(
			_service
			. save_provider_config(
				"fixture_provider",
				{"api_key": "fixture-good-key", "endpoint": "https://local.fixture"}
			)["ok"]
		)
	)
	assert_eq(_service.get_validation_state("fixture_provider"), "configured")

	var good_task: Variant = _service.validate_provider("fixture_provider")
	assert_not_null(good_task)
	assert_eq(_service.get_validation_state("fixture_provider"), "validating")
	_queue.submit(good_task)
	assert_true(await _wait_for_state("verified"))

	assert_true(
		(
			_service
			. save_provider_config(
				"fixture_provider",
				{"api_key": "fixture-bad-key", "endpoint": "https://local.fixture"}
			)["ok"]
		)
	)
	assert_eq(_service.get_validation_state("fixture_provider"), "configured")
	var bad_task: Variant = _service.validate_provider("fixture_provider")
	assert_not_null(bad_task)
	assert_eq(_service.get_validation_state("fixture_provider"), "validating")
	_queue.submit(bad_task)
	assert_true(await _wait_for_state("invalid"))

	_service._set_validation_state("fixture_provider", "outside_contract", "invalid state")
	assert_eq(_service.get_validation_state("fixture_provider"), "invalid")
	assert_eq(_service.delete_provider_credentials("fixture_provider"), OK)
	assert_eq(_service.get_validation_state("fixture_provider"), "unconfigured")
	assert_eq(provider.configured_key, "")
	assert_false(bool(SettingsService.get_setting("provider_fixture_provider", "validated", true)))
	assert_false(FileAccess.get_file_as_string(TEST_PATH).contains("fixture-bad-key"))


func test_exact_config_schema() -> void:
	var openai: PFProvider = OpenAIProviderScript.new()
	var retro: PFProvider = RetroProviderScript.new()
	assert_eq(
		openai.get_config_schema(),
		[
			{
				"key": "api_key",
				"kind": "password",
				"label_key": "OPENAI_FIELD_API_KEY",
				"help_key": "OPENAI_FIELD_API_KEY_HELP",
				"required": true,
				"default": "",
			}
		]
	)
	assert_eq(
		retro.get_config_schema(),
		[
			{
				"key": "api_key",
				"kind": "password",
				"label_key": "RETRO_FIELD_API_KEY",
				"help_key": "RETRO_FIELD_API_KEY_HELP",
				"required": true,
				"default": "",
			},
			{
				"key": "endpoint",
				"kind": "string",
				"label_key": "RETRO_FIELD_ENDPOINT",
				"help_key": "RETRO_FIELD_ENDPOINT_HELP",
				"required": true,
				"default": "https://api.retrodiffusion.ai/v1/inferences",
			},
		]
	)

	for invalid_schema: Array[Dictionary] in [
		_schema(_field("text")),
		_schema(_field("string", {"label": "Raw label"})),
		_schema(_field("string", {"unknown": true})),
		_schema(_field("enum", {"values": ["a", "a"], "default": "a"})),
	]:
		assert_false(_service._config_schema_is_valid(invalid_schema))

	var dialog: ConfirmationDialog = ProviderSettingsDialogScript.new()
	var enum_control: OptionButton = dialog._make_control(
		_field("enum", {"values": ["fast", "quality"], "default": "fast"}), "quality"
	)
	assert_eq(enum_control.item_count, 2)
	if enum_control.item_count > 0:
		assert_eq(enum_control.get_item_text(enum_control.selected), "quality")
	enum_control.free()
	dialog.free()

	var config_error: Variant = openai.configure(
		{"api_key": "fixture-key", "generation_url": "https://unlisted.invalid"}
	)
	assert_not_null(config_error)
	if config_error is Dictionary:
		assert_eq(String(config_error.get("field", "")), "generation_url")


func _field(kind: String, overrides: Dictionary = {}) -> Dictionary:
	var field := {
		"key": "mode",
		"kind": kind,
		"label_key": "RETRO_FIELD_ENDPOINT",
		"help_key": "RETRO_FIELD_ENDPOINT_HELP",
		"required": true,
		"default": "",
	}
	field.merge(overrides, true)
	return field


func _schema(field: Dictionary) -> Array[Dictionary]:
	return [field]


func _wait_for_state(expected: String, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if _service.get_validation_state("fixture_provider") == expected:
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _remove_test_credentials() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
