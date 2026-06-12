class_name FileIO
extends RefCounted

## 文件 IO 工具类。
## contract: 02-contracts/PROJECT-FORMAT.md §1/§5，项目保存必须 ZIP 可检查且原子写。


static func save_png(image: Image, path: String) -> Error:
	_ensure_parent_dir(path)
	return image.save_png(path)


static func load_png(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image


static func atomic_write(path: String, bytes: PackedByteArray) -> Error:
	_ensure_parent_dir(path)
	var temp_path := "%s.tmp-%s" % [path, str(Time.get_ticks_usec())]
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_buffer(bytes)
	file.flush()
	file.close()

	var target_global := _global_path(path)
	var temp_global := _global_path(temp_path)
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(target_global)
		if remove_error != OK and remove_error != ERR_DOES_NOT_EXIST:
			DirAccess.remove_absolute(temp_global)
			return remove_error

	var rename_error := DirAccess.rename_absolute(temp_global, target_global)
	if rename_error != OK:
		DirAccess.remove_absolute(temp_global)
	return rename_error


static func zip_pack(dir_map: Dictionary, path: String) -> Error:
	_ensure_parent_dir(path)
	var temp_path := "%s.ziptmp-%s" % [path, str(Time.get_ticks_usec())]
	var packer := ZIPPacker.new()
	var open_error := packer.open(temp_path)
	if open_error != OK:
		return open_error

	var file_names := dir_map.keys()
	file_names.sort()
	for file_name in file_names:
		var start_error := packer.start_file(String(file_name))
		if start_error != OK:
			packer.close()
			DirAccess.remove_absolute(_global_path(temp_path))
			return start_error

		var bytes := _variant_to_bytes(dir_map[file_name])
		packer.write_file(bytes)
		packer.close_file()

	packer.close()
	return _replace_file(temp_path, path)


static func zip_unpack(path: String) -> Dictionary:
	var reader := ZIPReader.new()
	var open_error := reader.open(path)
	if open_error != OK:
		return {"ok": false, "error": open_error, "files": {}}

	var files := {}
	for file_name in reader.get_files():
		files[file_name] = reader.read_file(file_name)
	reader.close()

	return {"ok": true, "error": OK, "files": files}


static func json_to_bytes(value: Variant) -> PackedByteArray:
	return JSON.stringify(value, "\t").to_utf8_buffer()


static func bytes_to_json(bytes: PackedByteArray) -> Variant:
	var parser := JSON.new()
	var error := parser.parse(bytes.get_string_from_utf8())
	if error != OK:
		return null
	return parser.data


static func _replace_file(temp_path: String, target_path: String) -> Error:
	var target_global := _global_path(target_path)
	var temp_global := _global_path(temp_path)
	if FileAccess.file_exists(target_path):
		var remove_error := DirAccess.remove_absolute(target_global)
		if remove_error != OK and remove_error != ERR_DOES_NOT_EXIST:
			DirAccess.remove_absolute(temp_global)
			return remove_error
	return DirAccess.rename_absolute(temp_global, target_global)


static func _variant_to_bytes(value: Variant) -> PackedByteArray:
	if value is PackedByteArray:
		return value
	if value is Image:
		return value.save_png_to_buffer()
	if value is Dictionary or value is Array:
		return json_to_bytes(value)
	return str(value).to_utf8_buffer()


static func _ensure_parent_dir(path: String) -> void:
	var parent := _global_path(path).get_base_dir()
	if not parent.is_empty():
		DirAccess.make_dir_recursive_absolute(parent)


static func _global_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path
