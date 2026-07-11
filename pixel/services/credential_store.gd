class_name PFCredentialStore
extends RefCounted

## Provider secret store using PBKDF2-HMAC-SHA256, AES-256-CBC, and encrypt-then-MAC.
## contract: 02-contracts/PROVIDER-API.md §3。
## Threat model: encryption prevents accidental plaintext disclosure; it cannot resist malicious
## software running as the same user because the device identifier is available to that software.

const CREDENTIALS_PATH := "user://credentials.cfg"
const FORMAT_VERSION := 1
const PBKDF2_ITERATIONS := 20_000
const SALT_BYTES := 16
const IV_BYTES := 16
const KEY_BYTES := 64
const AES_BLOCK_BYTES := 16

var _path := CREDENTIALS_PATH
var _device_id := ""
var _iterations := PBKDF2_ITERATIONS
var _crypto := Crypto.new()


func _init(path: String = CREDENTIALS_PATH, device_id: String = "", iterations: int = 0) -> void:
	_path = path
	_device_id = device_id if not device_id.is_empty() else OS.get_unique_id()
	_iterations = iterations if iterations > 0 else PBKDF2_ITERATIONS


func set_secret(provider_id: String, key: String, value: String) -> Error:
	if provider_id.is_empty() or key.is_empty() or _device_id.is_empty():
		return ERR_INVALID_PARAMETER
	var secrets_result := _load_provider_secrets(provider_id)
	if not bool(secrets_result["ok"]):
		return int(secrets_result["error"])
	var secrets: Dictionary = secrets_result["value"]
	secrets[key] = value
	return _save_provider_secrets(provider_id, secrets)


func get_secret(provider_id: String, key: String) -> String:
	var result := _load_provider_secrets(provider_id)
	if not bool(result["ok"]):
		return ""
	return String(result["value"].get(key, ""))


func has_secret(provider_id: String, key: String) -> bool:
	return not get_secret(provider_id, key).is_empty()


func delete_secret(provider_id: String, key: String) -> Error:
	var result := _load_provider_secrets(provider_id)
	if not bool(result["ok"]):
		return int(result["error"])
	var secrets: Dictionary = result["value"]
	secrets.erase(key)
	if secrets.is_empty():
		return delete_provider(provider_id)
	return _save_provider_secrets(provider_id, secrets)


func delete_provider(provider_id: String) -> Error:
	var config := ConfigFile.new()
	var load_error := config.load(_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	if config.has_section(provider_id):
		config.erase_section(provider_id)
	return config.save(_path)


func _save_provider_secrets(provider_id: String, secrets: Dictionary) -> Error:
	var salt := _crypto.generate_random_bytes(SALT_BYTES)
	var iv := _crypto.generate_random_bytes(IV_BYTES)
	if salt.size() != SALT_BYTES or iv.size() != IV_BYTES:
		return ERR_CANT_CREATE
	var keys := _derive_keys(salt)
	if keys.size() != KEY_BYTES:
		return ERR_CANT_CREATE
	var encryption_key := keys.slice(0, 32)
	var mac_key := keys.slice(32, 64)
	var plaintext := JSON.stringify(secrets).to_utf8_buffer()
	var padded := _pkcs7_pad(plaintext)
	var aes := AESContext.new()
	var aes_error := aes.start(AESContext.MODE_CBC_ENCRYPT, encryption_key, iv)
	if aes_error != OK:
		return aes_error
	var ciphertext := aes.update(padded)
	aes.finish()
	var mac := _crypto.hmac_digest(
		HashingContext.HASH_SHA256, mac_key, _mac_payload(salt, iv, ciphertext)
	)

	var config := ConfigFile.new()
	var load_error := config.load(_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return load_error
	config.set_value(provider_id, "version", FORMAT_VERSION)
	config.set_value(provider_id, "salt", Marshalls.raw_to_base64(salt))
	config.set_value(provider_id, "iv", Marshalls.raw_to_base64(iv))
	config.set_value(provider_id, "ciphertext", Marshalls.raw_to_base64(ciphertext))
	config.set_value(provider_id, "mac", Marshalls.raw_to_base64(mac))
	return config.save(_path)


func _load_provider_secrets(provider_id: String) -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(_path)
	if load_error == ERR_FILE_NOT_FOUND:
		return {"ok": true, "value": {}}
	if load_error != OK:
		return {"ok": false, "error": load_error}
	if not config.has_section(provider_id):
		return {"ok": true, "value": {}}
	if _device_id.is_empty():
		return {"ok": false, "error": ERR_UNAUTHORIZED}
	return _decrypt_provider_config(config, provider_id)


func _decrypt_provider_config(config: ConfigFile, provider_id: String) -> Dictionary:
	if int(config.get_value(provider_id, "version", 0)) != FORMAT_VERSION:
		return {"ok": false, "error": ERR_FILE_UNRECOGNIZED}

	var salt := Marshalls.base64_to_raw(String(config.get_value(provider_id, "salt", "")))
	var iv := Marshalls.base64_to_raw(String(config.get_value(provider_id, "iv", "")))
	var ciphertext := Marshalls.base64_to_raw(
		String(config.get_value(provider_id, "ciphertext", ""))
	)
	var stored_mac := Marshalls.base64_to_raw(String(config.get_value(provider_id, "mac", "")))
	if salt.size() != SALT_BYTES or iv.size() != IV_BYTES or ciphertext.is_empty():
		return {"ok": false, "error": ERR_FILE_CORRUPT}

	var keys := _derive_keys(salt)
	var encryption_key := keys.slice(0, 32)
	var mac_key := keys.slice(32, 64)
	var expected_mac := _crypto.hmac_digest(
		HashingContext.HASH_SHA256, mac_key, _mac_payload(salt, iv, ciphertext)
	)
	if not _crypto.constant_time_compare(expected_mac, stored_mac):
		return {"ok": false, "error": ERR_UNAUTHORIZED}

	var aes := AESContext.new()
	var aes_error := aes.start(AESContext.MODE_CBC_DECRYPT, encryption_key, iv)
	if aes_error != OK:
		return {"ok": false, "error": aes_error}
	var padded := aes.update(ciphertext)
	aes.finish()
	return _parse_secret_payload(_pkcs7_unpad(padded))


func _parse_secret_payload(plaintext: PackedByteArray) -> Dictionary:
	if plaintext.is_empty():
		return {"ok": false, "error": ERR_FILE_CORRUPT}
	var json := JSON.new()
	if json.parse(plaintext.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		return {"ok": false, "error": ERR_FILE_CORRUPT}
	return {"ok": true, "value": json.data}


func _derive_keys(salt: PackedByteArray) -> PackedByteArray:
	return _pbkdf2_hmac_sha256(_device_id.to_utf8_buffer(), salt, _iterations, KEY_BYTES)


func _pbkdf2_hmac_sha256(
	password: PackedByteArray, salt: PackedByteArray, iterations: int, output_bytes: int
) -> PackedByteArray:
	var result := PackedByteArray()
	var block_index := 1
	while result.size() < output_bytes:
		var block_salt := salt.duplicate()
		(
			block_salt
			. append_array(
				PackedByteArray(
					[
						(block_index >> 24) & 0xff,
						(block_index >> 16) & 0xff,
						(block_index >> 8) & 0xff,
						block_index & 0xff,
					]
				)
			)
		)
		var u := _crypto.hmac_digest(HashingContext.HASH_SHA256, password, block_salt)
		var accumulator := u.duplicate()
		for _iteration in range(1, iterations):
			u = _crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
			for byte_index in range(accumulator.size()):
				accumulator[byte_index] ^= u[byte_index]
		result.append_array(accumulator)
		block_index += 1
	result.resize(output_bytes)
	return result


func _pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var padded := data.duplicate()
	var padding := AES_BLOCK_BYTES - data.size() % AES_BLOCK_BYTES
	for _index in range(padding):
		padded.append(padding)
	return padded


func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return PackedByteArray()
	var padding := int(data[data.size() - 1])
	if padding <= 0 or padding > AES_BLOCK_BYTES or padding > data.size():
		return PackedByteArray()
	for index in range(data.size() - padding, data.size()):
		if int(data[index]) != padding:
			return PackedByteArray()
	return data.slice(0, data.size() - padding)


func _mac_payload(
	salt: PackedByteArray, iv: PackedByteArray, ciphertext: PackedByteArray
) -> PackedByteArray:
	var payload := PackedByteArray([FORMAT_VERSION])
	payload.append_array(salt)
	payload.append_array(iv)
	payload.append_array(ciphertext)
	return payload
