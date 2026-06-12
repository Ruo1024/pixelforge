class_name PFIdUtil
extends RefCounted

## 小型 ID/时间工具。
## 输出契约：UUID 使用小写连字符格式；时间使用 UTC ISO8601，匹配 PROJECT-FORMAT.md。


static func uuid_v4() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var bytes := PackedByteArray()
	for index in range(16):
		bytes.append(rng.randi_range(0, 255))

	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	var parts := [
		_bytes_to_hex(bytes.slice(0, 4)),
		_bytes_to_hex(bytes.slice(4, 6)),
		_bytes_to_hex(bytes.slice(6, 8)),
		_bytes_to_hex(bytes.slice(8, 10)),
		_bytes_to_hex(bytes.slice(10, 16)),
	]
	return "-".join(parts)


static func utc_now_iso() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return (
		"%04d-%02d-%02dT%02d:%02d:%02dZ"
		% [
			int(date["year"]),
			int(date["month"]),
			int(date["day"]),
			int(date["hour"]),
			int(date["minute"]),
			int(date["second"]),
		]
	)


static func filesystem_stamp() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return (
		"%04d%02d%02d_%02d%02d%02d"
		% [
			int(date["year"]),
			int(date["month"]),
			int(date["day"]),
			int(date["hour"]),
			int(date["minute"]),
			int(date["second"]),
		]
	)


static func _bytes_to_hex(bytes: PackedByteArray) -> String:
	var text := ""
	for byte in bytes:
		text += "%02x" % int(byte)
	return text
