class_name PFCredentialSentinelScanner
extends RefCounted

## Recursively scans user-visible and persisted values. The raw mock transport buffer
## is intentionally excluded and is asserted separately by a boolean fixture endpoint.

const VALUE := "PF_B7_CREDENTIAL_SENTINEL_7B1E9C42"


static func contains(value: Variant, sentinel: String) -> bool:
	if value == null:
		return false
	if value is String or value is StringName:
		return String(value).contains(sentinel)
	if value is Dictionary:
		for key in value:
			if contains(key, sentinel) or contains(value[key], sentinel):
				return true
		return false
	if value is Array:
		for item in value:
			if contains(item, sentinel):
				return true
		return false
	if value is PackedStringArray:
		for item in value:
			if String(item).contains(sentinel):
				return true
		return false
	if value is PackedByteArray:
		return _bytes_contain(value, sentinel.to_utf8_buffer())
	return false


static func _bytes_contain(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	if needle.is_empty() or needle.size() > haystack.size():
		return false
	for start in range(haystack.size() - needle.size() + 1):
		var matches := true
		for offset in range(needle.size()):
			if haystack[start + offset] != needle[offset]:
				matches = false
				break
		if matches:
			return true
	return false


static func file_contains(path: String, sentinel: String, start_offset: int = 0) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	file.seek(maxi(0, start_offset))
	return file.get_buffer(file.get_length() - file.get_position()).get_string_from_utf8().contains(
		sentinel
	)
