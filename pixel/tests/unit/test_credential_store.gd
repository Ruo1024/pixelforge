extends "res://addons/gut/test.gd"

const CredentialStoreScript := preload("res://services/credential_store.gd")

const TEST_PATH := "user://tests/m4_credentials.cfg"
const DEVICE_ID := "pixelforge-test-device"
const SECRET := "sk-test-plaintext-must-not-survive"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	_remove_test_file()


func after_each() -> void:
	_remove_test_file()


func test_pbkdf2_matches_sha256_reference_vector() -> void:
	var store := CredentialStoreScript.new(TEST_PATH, DEVICE_ID, 1)
	var derived: PackedByteArray = store.call(
		"_pbkdf2_hmac_sha256", "password".to_utf8_buffer(), "salt".to_utf8_buffer(), 1, 32
	)

	assert_eq(
		derived.hex_encode(), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
	)


func test_secret_roundtrip_uses_ciphertext_and_no_plaintext() -> void:
	var store := CredentialStoreScript.new(TEST_PATH, DEVICE_ID, 64)

	assert_eq(store.set_secret("openai_image", "api_key", SECRET), OK)
	assert_eq(store.get_secret("openai_image", "api_key"), SECRET)
	assert_true(store.has_secret("openai_image", "api_key"))
	var file := FileAccess.open(TEST_PATH, FileAccess.READ)
	assert_not_null(file)
	assert_false(file.get_as_text().contains(SECRET))


func test_wrong_device_id_cannot_decrypt_and_delete_removes_secret() -> void:
	var store := CredentialStoreScript.new(TEST_PATH, DEVICE_ID, 64)
	assert_eq(store.set_secret("openai_image", "api_key", SECRET), OK)
	var wrong_device_store := CredentialStoreScript.new(TEST_PATH, "different-device", 64)
	assert_eq(wrong_device_store.get_secret("openai_image", "api_key"), "")

	assert_eq(store.delete_secret("openai_image", "api_key"), OK)
	assert_false(store.has_secret("openai_image", "api_key"))


func _remove_test_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute)
