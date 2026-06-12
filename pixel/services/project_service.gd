class_name PFProjectService
extends Node

## 项目服务。
## contract: 02-contracts/PROJECT-FORMAT.md；负责新建、保存、打开、自动保存和版本迁移框架。

signal project_loaded(project: Variant)
signal project_saved(path: String)
signal dirty_changed(is_dirty: bool)
signal recovery_available(autosaves: Array)

const AUTOSAVE_INTERVAL_SECONDS := 180.0
const AUTOSAVE_KEEP_COUNT := 5
const LOCK_PATH := "user://pixelforge_session.lock"
const ProjectModel := preload("res://services/pf_project.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")
const MIGRATIONS: Array = []

var current_project: Variant = ProjectModel.new()

var _autosave_timer: Timer = null


func _ready() -> void:
	current_project.reset()
	_setup_autosave_timer()
	_check_recovery_state()
	_write_session_lock()


func new_project(name: String = "Untitled") -> void:
	AssetLibrary.clear()
	UndoService.clear()
	current_project.reset(name)
	project_loaded.emit(current_project)
	EventBus.project_created.emit(current_project.get_id())
	_emit_dirty(false)


func set_canvas_data(canvas_data: Dictionary, mark_dirty: bool = true) -> void:
	current_project.canvas = canvas_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)
		EventBus.canvas_changed.emit()


func get_canvas_data() -> Dictionary:
	return current_project.canvas.duplicate(true)


func save_project(path: String = "") -> Error:
	var target_path := path
	if target_path.is_empty():
		target_path = current_project.project_path
	if target_path.is_empty():
		return ERR_FILE_BAD_PATH

	var error := _save_to_path(target_path)
	if error == OK:
		current_project.project_path = target_path
		SettingsService.add_recent_project(target_path)
		_emit_dirty(false)
		project_saved.emit(target_path)
		EventBus.project_saved.emit(target_path)
	return error


func open_project(path: String) -> Error:
	var unpacked: Dictionary = FileIOScript.zip_unpack(path)
	if not bool(unpacked.get("ok", false)):
		return int(unpacked.get("error", ERR_FILE_CANT_OPEN))

	var files: Dictionary = unpacked["files"]
	if not files.has("manifest.json") or not files.has("canvas/canvas.json"):
		return ERR_FILE_CORRUPT

	var manifest: Variant = FileIOScript.bytes_to_json(files["manifest.json"])
	var canvas: Variant = FileIOScript.bytes_to_json(files["canvas/canvas.json"])
	if not (manifest is Dictionary) or not (canvas is Dictionary):
		return ERR_PARSE_ERROR

	var migration_error := _migrate_manifest(manifest)
	if migration_error != OK:
		return migration_error

	_normalize_loaded_project(manifest, canvas)

	var asset_error := AssetLibrary.load_from_zip_files(files)
	if asset_error != OK:
		return asset_error

	current_project = ProjectModel.new()
	current_project.manifest = manifest
	current_project.canvas = canvas
	current_project.project_path = path
	current_project.dirty = false

	SettingsService.add_recent_project(path)
	UndoService.clear()
	project_loaded.emit(current_project)
	EventBus.project_opened.emit(path)
	_emit_dirty(false)
	return OK


func autosave_now() -> Error:
	if current_project.get_id().is_empty():
		return ERR_UNCONFIGURED

	var autosave_dir := "user://autosave/%s" % current_project.get_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(autosave_dir))
	var autosave_path := "%s/%s.pxproj" % [autosave_dir, IdUtil.filesystem_stamp()]
	var error := _save_to_path(autosave_path)
	if error == OK:
		_prune_autosaves(autosave_dir)
	return error


func list_autosaves(project_id: String = "") -> Array:
	var root := "user://autosave"
	var autosaves: Array = []
	var root_dir := DirAccess.open(root)
	if root_dir == null:
		return autosaves

	var project_dirs: Array = []
	if project_id.is_empty():
		project_dirs = root_dir.get_directories()
	else:
		project_dirs = [project_id]

	for dir_name in project_dirs:
		var autosave_dir := "%s/%s" % [root, dir_name]
		var dir := DirAccess.open(autosave_dir)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".pxproj"):
				autosaves.append("%s/%s" % [autosave_dir, file_name])

	autosaves.sort()
	return autosaves


func mark_clean_shutdown() -> void:
	if FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


func _save_to_path(path: String) -> Error:
	_update_manifest_before_save()
	var entries := {
		"manifest.json": current_project.manifest,
		"canvas/canvas.json": current_project.canvas,
	}
	var asset_entries := AssetLibrary.export_zip_entries()
	for asset_path in asset_entries.keys():
		entries[asset_path] = asset_entries[asset_path]
	return FileIOScript.zip_pack(entries, path)


func _update_manifest_before_save() -> void:
	current_project.manifest["modified_at"] = IdUtil.utc_now_iso()
	current_project.manifest["app_version"] = AppInfo.APP_VERSION
	current_project.manifest["format_version"] = AppInfo.PROJECT_FORMAT_VERSION
	var entries: Dictionary = current_project.manifest.get("entries", {})
	entries["canvases"] = ["canvas"]
	entries["asset_count"] = AssetLibrary.get_all_meta().size()
	current_project.manifest["entries"] = entries


func _migrate_manifest(manifest: Dictionary) -> Error:
	var version := int(manifest.get("format_version", 0))
	if version <= 0:
		return ERR_FILE_CORRUPT
	if version > AppInfo.PROJECT_FORMAT_VERSION:
		return ERR_FILE_UNRECOGNIZED

	while version < AppInfo.PROJECT_FORMAT_VERSION:
		var migration_index := version - 1
		if migration_index < 0 or migration_index >= MIGRATIONS.size():
			return ERR_UNAVAILABLE
		var migration: Callable = MIGRATIONS[migration_index]
		manifest = migration.call(manifest)
		version = int(manifest.get("format_version", version + 1))

	return OK


func _normalize_loaded_project(manifest: Dictionary, canvas: Dictionary) -> void:
	manifest["format_version"] = int(manifest.get("format_version", AppInfo.PROJECT_FORMAT_VERSION))
	var entries: Dictionary = manifest.get("entries", {})
	entries["asset_count"] = int(entries.get("asset_count", 0))
	manifest["entries"] = entries

	var camera: Dictionary = canvas.get("camera", {})
	var center: Variant = camera.get("center", [0, 0])
	camera["center"] = [int(round(float(center[0]))), int(round(float(center[1])))]
	camera["zoom"] = float(camera.get("zoom", 1.0))
	canvas["camera"] = camera

	var normalized_items := []
	for item in canvas.get("items", []):
		if not (item is Dictionary):
			continue
		var item_data: Dictionary = item
		var position: Variant = item_data.get("position", [0, 0])
		item_data["position"] = [int(round(float(position[0]))), int(round(float(position[1])))]
		item_data["scale_factor"] = int(item_data.get("scale_factor", 1))
		item_data["z_index"] = int(item_data.get("z_index", 0))
		item_data["locked"] = bool(item_data.get("locked", false))
		normalized_items.append(item_data)
	canvas["items"] = normalized_items


func _emit_dirty(value: bool) -> void:
	if current_project.dirty == value:
		return
	current_project.set_dirty(value)
	dirty_changed.emit(value)
	EventBus.project_dirty_changed.emit(value)


func _setup_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)


func _on_autosave_timeout() -> void:
	if current_project.dirty:
		var error := autosave_now()
		if error != OK:
			Log.warn("Autosave failed", {"error": error})


func _check_recovery_state() -> void:
	if not FileAccess.file_exists(LOCK_PATH):
		return

	var autosaves := list_autosaves()
	if not autosaves.is_empty():
		recovery_available.emit(autosaves)
		EventBus.recovery_available.emit(autosaves)


func _write_session_lock() -> void:
	var file := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(IdUtil.utc_now_iso())


func _prune_autosaves(autosave_dir: String) -> void:
	var dir := DirAccess.open(autosave_dir)
	if dir == null:
		return

	var files := Array(dir.get_files())
	files.sort()
	while files.size() > AUTOSAVE_KEEP_COUNT:
		var file_name := String(files.pop_front())
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s/%s" % [autosave_dir, file_name])
		)
