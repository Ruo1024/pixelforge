extends "res://addons/gut/test.gd"

const CredentialStoreScript := preload("res://services/credential_store.gd")
const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")
const ProviderServiceScript := preload("res://services/provider_service.gd")
const ProviderSettingsDialogScript := preload("res://ui/dialogs/provider_settings_dialog.gd")
const SettingsServiceScript := preload("res://services/settings_service.gd")
const SentinelScanner := preload("res://tests/helpers/credential_sentinel_scanner.gd")

const TEST_PATH := "user://tests/b7f2_api_credentials.cfg"
const SECRET_SENTINEL := "PF_B7F_API_KEY_SENTINEL_C18A7E"

var _base_url := ""
var _provider: PFOpenAIImageProvider = null
var _queue: Node = null
var _service: Node = null


func before_each() -> void:
	_remove_test_credentials()
	_base_url = OS.get_environment("PF_HTTP_MOCK_URL")
	assert_false(_base_url.is_empty(), "network tests must use the local fixture server")
	SettingsService.set_setting("provider_openai_image", "base_url", "https://api.openai.com/v1")
	SettingsService.set_setting("provider_openai_image", "remote_model", "gpt-image-2")
	SettingsService.set_setting("provider_openai_image", "api_mode", "images")
	SettingsService.set_setting("provider_openai_image", "validated", false)
	SettingsService.set_setting("provider_openai_image", "allow_unconfirmed_model", false)
	SettingsService.set_developer_mode_enabled(false)
	_queue = get_tree().root.get_node("TaskQueue")
	_queue.clear()
	_service = ProviderServiceScript.new()
	_service.load_builtin_plugins = false
	_service.set_credential_store(CredentialStoreScript.new(TEST_PATH, "b7f2-device", 64))
	add_child_autofree(_service)
	await wait_process_frames(1)
	_provider = OpenAIProviderScript.new("", "", "", 0.05)
	assert_true(_service.register_provider(_provider)["ok"])


func after_each() -> void:
	SettingsService.set_developer_mode_enabled(false)
	SettingsService.set_setting("provider_openai_image", "base_url", "https://api.openai.com/v1")
	SettingsService.set_setting("provider_openai_image", "remote_model", "gpt-image-2")
	SettingsService.set_setting("provider_openai_image", "api_mode", "images")
	SettingsService.set_setting("provider_openai_image", "validated", false)
	SettingsService.set_setting("provider_openai_image", "allow_unconfirmed_model", false)
	_remove_test_credentials()


func test_dialog_tests_draft_then_saves_base_url_and_encrypted_key() -> void:
	ProjectService.new_project("B7F-2 safe API settings")
	var log_path: String = get_tree().root.get_node("Logger").get_current_log_path()
	var log_offset := FileAccess.get_file_as_bytes(log_path).size()
	var dialog: PFProviderSettingsDialog = ProviderSettingsDialogScript.new()
	dialog.set_services(_service, _queue)
	add_child_autofree(dialog)
	await wait_process_frames(1)

	var base_url_edit := dialog.get_field_control("base_url") as LineEdit
	var key_edit := dialog.get_field_control("api_key") as LineEdit
	var model_edit := dialog.get_field_control("remote_model") as LineEdit
	var api_mode := dialog.get_field_control("api_mode") as OptionButton
	assert_not_null(base_url_edit)
	assert_not_null(key_edit)
	assert_not_null(model_edit)
	assert_not_null(api_mode)
	assert_eq(dialog.cancel_button_text, LocalizationService.text("ACTION_CANCEL"))
	assert_eq(base_url_edit.text, "https://api.openai.com/v1")
	base_url_edit.text = _base_url + "/ping-sentinel"
	key_edit.text = SECRET_SENTINEL
	base_url_edit.text_changed.emit(base_url_edit.text)
	key_edit.text_changed.emit(key_edit.text)
	assert_eq(dialog._status_label.text, LocalizationService.text("PROVIDER_PING_UNTESTED"))

	assert_true(dialog.validate_current_provider())
	assert_true(await _wait_for_validation_terminal())
	assert_eq(_service.get_validation_state("openai_image"), "verified")
	assert_eq(
		_service.get_validation_message("openai_image"),
		LocalizationService.text("PROVIDER_PING_SUCCESS")
	)
	assert_false(FileAccess.file_exists(TEST_PATH), "testing a draft must not persist its key")

	dialog.confirmed.emit()
	assert_eq(dialog._status_label.text, LocalizationService.text("PROVIDER_SETTINGS_SAVED"))
	assert_eq(
		_service.get_provider_config("openai_image")["base_url"], _base_url + "/ping-sentinel"
	)
	assert_true(_service.get_provider_config("openai_image")["api_key_saved"])
	assert_eq(_service.get_provider_config("openai_image")["remote_model"], "gpt-image-2")
	assert_eq(_service.get_provider_config("openai_image")["api_mode"], "images")
	assert_false(SentinelScanner.file_contains(TEST_PATH, SECRET_SENTINEL))
	assert_ne(SettingsService.get_setting("provider_openai_image", "api_key", ""), SECRET_SENTINEL)
	assert_false(SentinelScanner.file_contains(log_path, SECRET_SENTINEL, log_offset))
	assert_false(
		(
			SentinelScanner
			. contains(
				{
					"manifest": ProjectService.current_project.manifest,
					"canvas": ProjectService.current_project.canvas,
					"graphs": ProjectService.current_project.graphs,
				},
				SECRET_SENTINEL
			)
		)
	)


func test_chat_completions_relay_uses_saved_address_model_and_local_mock() -> void:
	var dialog: PFProviderSettingsDialog = ProviderSettingsDialogScript.new()
	dialog.set_services(_service, _queue)
	add_child_autofree(dialog)
	await wait_process_frames(1)
	var base_url_edit := dialog.get_field_control("base_url") as LineEdit
	var mode_control := dialog.get_field_control("api_mode") as OptionButton
	base_url_edit.text = _base_url + "/v1/chat/completions"
	base_url_edit.text_changed.emit(base_url_edit.text)
	assert_eq(mode_control.get_item_metadata(mode_control.selected), "chat_completions")

	var config := {
		"base_url": _base_url + "/v1/chat/completions",
		"remote_model": "relay-image-model-v2",
		"api_mode": "chat_completions",
		"api_key": SECRET_SENTINEL,
	}
	var validation: Variant = _service.validate_provider("openai_image", config)
	assert_not_null(validation)
	_queue.submit(validation)
	assert_true(await _wait_for_validation_terminal())
	assert_eq(_service.get_validation_state("openai_image"), "verified")
	assert_true(_service.save_provider_config("openai_image", config)["ok"])
	assert_eq(_provider.get_base_url(), _base_url + "/v1/chat/completions")
	assert_eq(_provider.get_remote_model(), "relay-image-model-v2")
	assert_eq(_provider.get_api_mode(), "chat_completions")
	assert_true(_service.get_selectable_provider_ids().has("openai_image"))

	var request := _chat_request()
	var body := _provider.build_chat_request_body(request)
	assert_eq(body["model"], "relay-image-model-v2")
	assert_eq(body["messages"][0]["role"], "user")
	assert_eq(body["messages"][0]["content"], request["prompt"])
	assert_eq(body["n"], 2)
	assert_eq(body["size"], "16x16")
	var generation: PFProviderTaskV2 = _provider.generate(request)
	var outcome := {"status": "pending", "value": null}
	generation.completed.connect(
		func(result: Dictionary) -> void:
			outcome["status"] = "completed"
			outcome["value"] = result
	)
	generation.failed.connect(
		func(error: Dictionary) -> void:
			outcome["status"] = "failed"
			outcome["value"] = error
	)
	assert_true(await _wait_until(func() -> bool: return outcome["status"] != "pending"))
	assert_eq(outcome["status"], "completed")
	assert_eq(outcome["value"]["items"].size(), 2)
	assert_true(
		outcome["value"]["items"].all(
			func(item: Dictionary) -> bool: return item["image"].get_size() == Vector2i(16, 16)
		)
	)


func test_reachable_unlisted_model_can_be_saved_and_selected() -> void:
	var config := {
		"base_url": _base_url + "/ping-model-unconfirmed",
		"remote_model": "relay-private-image-model",
		"api_mode": "images",
		"api_key": SECRET_SENTINEL,
	}
	var validation: Variant = _service.validate_provider("openai_image", config)
	assert_not_null(validation)
	_queue.submit(validation)
	assert_true(await _wait_for_validation_terminal())
	assert_eq(_service.get_validation_state("openai_image"), "configured")
	assert_true(_service.save_provider_config("openai_image", config)["ok"])
	assert_true(
		bool(SettingsService.get_setting("provider_openai_image", "allow_unconfirmed_model", false))
	)
	assert_true(_service.get_selectable_provider_ids().has("openai_image"))
	assert_eq(
		_service.get_validation_message("openai_image"),
		LocalizationService.text("PROVIDER_PING_MODEL_UNCONFIRMED_USABLE")
	)
	_service._unconfirmed_config_fingerprints.clear()
	assert_true(
		(
			_service
			. save_provider_config(
				"openai_image",
				{
					"base_url": config["base_url"],
					"remote_model": config["remote_model"],
					"api_mode": config["api_mode"],
					"api_key": "",
				}
			)["ok"]
		)
	)
	assert_true(_service.get_selectable_provider_ids().has("openai_image"))


func test_ping_statuses_are_distinct_single_attempt_and_local_only() -> void:
	var cases := [
		{"path": "/v1", "state": "verified", "key": "PROVIDER_PING_SUCCESS"},
		{"path": "/ping-auth", "state": "invalid", "key": "PROVIDER_PING_AUTH_FAILED"},
		{
			"path": "/ping-model-unconfirmed",
			"state": "configured",
			"key": "PROVIDER_PING_MODEL_UNCONFIRMED",
		},
		{
			"path": "/ping-rate",
			"state": "configured",
			"key": "PROVIDER_PING_RATE_LIMITED",
		},
		{
			"path": "/ping-timeout",
			"state": "configured",
			"key": "PROVIDER_PING_TIMEOUT",
		},
		{
			"path": "/ping-network",
			"state": "configured",
			"key": "PROVIDER_PING_NETWORK_ERROR",
		},
		{
			"path": "/ping-malformed",
			"state": "configured",
			"key": "PROVIDER_PING_PROTOCOL_ERROR",
		},
		{
			"path": "/ping-protocol",
			"state": "configured",
			"key": "PROVIDER_PING_PROTOCOL_ERROR",
		},
	]
	for case in cases:
		var attempts := []
		var record_attempt := func(_task_id: String, attempt: int, _timestamp_msec: int) -> void:
			attempts.append(attempt)
		_provider._http.request_attempted.connect(record_attempt, CONNECT_ONE_SHOT)
		var task: Variant = _service.validate_provider(
			"openai_image",
			{"base_url": _base_url + String(case["path"]), "api_key": SECRET_SENTINEL}
		)
		assert_not_null(task, String(case["path"]))
		assert_false(SentinelScanner.contains(task.payload, SECRET_SENTINEL))
		_queue.submit(task)
		assert_true(await _wait_for_validation_terminal(), String(case["path"]))
		assert_eq(attempts, [0], "%s ping must execute exactly once" % case["path"])
		assert_eq(_service.get_validation_state("openai_image"), case["state"])
		assert_eq(
			_service.get_validation_message("openai_image"),
			LocalizationService.text(String(case["key"])),
			String(case["path"])
		)
		assert_false(_service.get_validation_message("openai_image").contains(SECRET_SENTINEL))


func test_cancel_restores_saved_session_without_persisting_the_draft() -> void:
	var saved_url := _base_url + "/v1"
	assert_true(
		(
			_service
			. save_provider_config(
				"openai_image", {"base_url": saved_url, "api_key": SECRET_SENTINEL}
			)["ok"]
		)
	)
	var dialog: PFProviderSettingsDialog = ProviderSettingsDialogScript.new()
	dialog.set_services(_service, _queue)
	add_child_autofree(dialog)
	await wait_process_frames(1)
	var base_url_edit := dialog.get_field_control("base_url") as LineEdit
	base_url_edit.text = _base_url + "/ping-model-unconfirmed"
	base_url_edit.text_changed.emit(base_url_edit.text)
	assert_true(dialog.validate_current_provider())
	assert_true(await _wait_for_validation_terminal())
	assert_eq(_provider.get_base_url(), _base_url + "/ping-model-unconfirmed")

	dialog._on_cancel_requested()
	assert_eq(_provider.get_base_url(), saved_url)
	assert_eq(_service.get_provider_config("openai_image")["base_url"], saved_url)
	assert_false(SentinelScanner.file_contains(TEST_PATH, SECRET_SENTINEL))


func test_ping_does_not_follow_redirect_and_developer_mode_is_session_only() -> void:
	var attempts := []
	_provider._http.request_attempted.connect(
		func(_task_id: String, attempt: int, _timestamp_msec: int) -> void: attempts.append(attempt)
	)
	var task: Variant = _service.validate_provider(
		"openai_image", {"base_url": _base_url + "/ping-redirect", "api_key": SECRET_SENTINEL}
	)
	_queue.submit(task)
	assert_true(await _wait_for_validation_terminal())
	assert_eq(attempts, [0])
	assert_ne(_service.get_validation_state("openai_image"), "verified")

	var session_settings := SettingsServiceScript.new()
	assert_false(session_settings.is_developer_mode_enabled())
	var changes := []
	session_settings.developer_mode_changed.connect(
		func(enabled: bool) -> void: changes.append(enabled)
	)
	session_settings.set_developer_mode_enabled(true)
	assert_true(session_settings.is_developer_mode_enabled())
	assert_eq(changes, [true])
	assert_false(session_settings._config.has_section_key("ui", "developer_mode"))
	session_settings.free()


func test_main_exposes_api_settings_and_developer_mode_in_top_bar() -> void:
	SettingsService.set_developer_mode_enabled(false)
	var main: Control = load("res://ui/shell/main.gd").new()
	main.size = Vector2(1080, 720)
	add_child_autofree(main)
	await wait_process_frames(2)
	var api_button := main.find_child("ApiSettingsButton", true, false) as Button
	var developer_toggle := main.find_child("DeveloperModeToggle", true, false) as CheckButton
	assert_not_null(api_button)
	assert_not_null(developer_toggle)
	assert_eq(api_button.get_meta("action_id"), "api_settings")
	assert_eq(developer_toggle.get_meta("action_id"), "developer_mode")
	var recovery_dialog := main.get_node("RecoveryDialog") as Window
	if recovery_dialog.visible:
		recovery_dialog.hide()
		await wait_process_frames(1)
	api_button.pressed.emit()
	await wait_process_frames(1)
	var api_dialog := main.get_node("M21UiController/ProviderSettingsDialog") as Window
	assert_true(api_dialog.visible)
	api_dialog.hide()
	assert_false(developer_toggle.button_pressed)
	developer_toggle.button_pressed = true
	assert_true(SettingsService.is_developer_mode_enabled())
	assert_false(SettingsService._config.has_section_key("ui", "developer_mode"))


func _wait_for_validation_terminal(timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if _service.get_validation_state("openai_image") != "validating" and _queue.is_idle():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _wait_until(predicate: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if predicate.call():
			return true
		await wait_seconds(0.02)
		elapsed += 0.02
	return false


func _chat_request() -> Dictionary:
	return {
		"run_id": "chat-run",
		"request_id": "chat-request",
		"idempotency_key": "chat-idempotency",
		"provider_id": "openai_image",
		"mode": "txt2img",
		"model_id": "gpt-image-2",
		"prompt": "a tiny pixel shrine",
		"target_width": 16,
		"target_height": 16,
		"provider_output_size": [16, 16],
		"batch": 2,
		"seed": -1,
		"ref_images": [],
		"extra": {},
	}


func _remove_test_credentials() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
