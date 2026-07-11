extends SceneTree

## Packs a development plugin directory into a namespaced PixelForge PCK.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: pack_plugin.gd PLUGIN_DIRECTORY OUTPUT.pck")
		quit(2)
		return
	var source := ProjectSettings.globalize_path(String(args[0]))
	var output := ProjectSettings.globalize_path(String(args[1]))
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(source.path_join("plugin.json"))
	)
	if not (manifest is Dictionary) or not manifest.has("id"):
		push_error("plugin.json with id is required")
		quit(3)
		return
	var plugin_id := String(manifest["id"])
	if output.get_file().get_basename() != plugin_id:
		push_error("output filename must match plugin id: %s.pck" % plugin_id)
		quit(4)
		return
	var packer := PCKPacker.new()
	var error: Error = packer.pck_start(output)
	if error == OK:
		error = _add_directory(packer, source, source, "res://plugins/%s" % plugin_id)
	if error == OK:
		error = packer.flush()
	quit(0 if error == OK else int(error))


func _add_directory(
	packer: PCKPacker, root: String, current: String, virtual_root: String
) -> Error:
	var directory := DirAccess.open(current)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name in directory.get_files():
		var relative := current.trim_prefix(root).trim_prefix("/")
		var target := virtual_root.path_join(relative).path_join(file_name)
		var error := packer.add_file(target, current.path_join(file_name))
		if error != OK:
			return error
	for child in directory.get_directories():
		var error := _add_directory(packer, root, current.path_join(child), virtual_root)
		if error != OK:
			return error
	return OK
