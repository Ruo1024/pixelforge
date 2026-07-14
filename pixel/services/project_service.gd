# gdlint: disable=max-returns
class_name PFProjectService
extends Node

## 项目服务。
## contract: 02-contracts/PROJECT-FORMAT.md；负责 v2 新建、保存、打开和自动保存。

signal project_loaded(project: Variant)
signal project_saved(path: String)
signal dirty_changed(is_dirty: bool)
signal recovery_available(autosaves: Array)
signal autosave_failed(error: Error, path: String)

const AUTOSAVE_INTERVAL_SECONDS := 180.0
const AUTOSAVE_KEEP_COUNT := 5
const LOCK_PATH := "user://pixelforge_session.lock"
const ProjectModel := preload("res://services/pf_project.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GenerationRunCoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const AssetReferenceScanner := preload("res://services/asset_reference_scanner.gd")
const Log := preload("res://core/util/log_util.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")
const CANVAS_NODE_KEYS := [
	"id",
	"type",
	"graph_id",
	"node_id",
	"position",
	"z_index",
	"display_title",
	"size",
	"collapsed",
	"locked",
	"frame_id",
]
const LEGACY_CANVAS_KEYS := [
	"asset_ids",
	"selected_asset_ids",
	"review_states",
	"review_filter",
	"review_layout",
	"focus_asset_id",
	"compare_asset_ids",
	"compare_mode",
	"graph_anchor",
	"role",
	"source_node_id",
	"source_run_id",
	"input_snapshots",
	"request_records",
	"result_slots",
]
var current_project: Variant = ProjectModel.new()
var last_load_error: Dictionary = {}

var _autosave_timer: Timer = null
var _pending_recovery_autosaves: Array = []
var _validation_warnings: Array[Dictionary] = []


func _ready() -> void:
	current_project.reset()
	_setup_autosave_timer()
	_check_recovery_state()
	_write_session_lock()


func new_project(name: String = "Untitled") -> void:
	AssetLibrary.clear()
	PaletteRegistry.clear_custom_palettes()
	UndoService.clear()
	current_project.reset(name)
	_refresh_validation_warnings()
	project_loaded.emit(current_project)
	EventBus.project_created.emit(current_project.get_id())
	_emit_dirty(false)


func set_canvas_data(canvas_data: Dictionary, mark_dirty: bool = true) -> void:
	current_project.canvas = canvas_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)
		EventBus.canvas_changed.emit()


func set_graphs_data(graphs_data: Dictionary, mark_dirty: bool = true) -> void:
	current_project.graphs = graphs_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)


func set_graph_data(graph_id: String, graph_data: Dictionary, mark_dirty: bool = true) -> void:
	if graph_id.is_empty():
		return
	current_project.graphs[graph_id] = graph_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)


func set_document_data(
	kind: String, document_id: String, document_data: Dictionary, mark_dirty: bool = true
) -> void:
	if document_id.is_empty() or kind not in ["boards", "animations"]:
		return
	var collection: Dictionary = current_project.get(kind)
	collection[document_id] = document_data.duplicate(true)
	if mark_dirty:
		_emit_dirty(true)


func remove_document(kind: String, document_id: String, mark_dirty: bool = true) -> void:
	if kind not in ["boards", "animations"]:
		return
	var collection: Dictionary = current_project.get(kind)
	collection.erase(document_id)
	if mark_dirty:
		_emit_dirty(true)


func mark_dirty() -> void:
	_emit_dirty(true)


func get_graphs_data() -> Dictionary:
	return current_project.graphs.duplicate(true)


func get_graph_data(graph_id: String) -> Dictionary:
	return Dictionary(current_project.graphs.get(graph_id, {})).duplicate(true)


func get_document_data(kind: String, document_id: String = "") -> Dictionary:
	if kind not in ["boards", "animations"]:
		return {}
	var collection: Dictionary = current_project.get(kind)
	return (
		collection.duplicate(true)
		if document_id.is_empty()
		else Dictionary(collection.get(document_id, {})).duplicate(true)
	)


func get_validation_warnings() -> Array[Dictionary]:
	return _validation_warnings.duplicate(true)


func get_asset_reference_locations(asset_id: String) -> Array[Dictionary]:
	var scan: Dictionary = AssetReferenceScanner.scan(current_project, AssetLibrary)
	var result: Array[Dictionary] = []
	for strength in ["live", "history"]:
		var source: Dictionary = scan["%s_by_asset" % strength]
		for reference in source.get(asset_id, []):
			result.append(Dictionary(reference).duplicate(true))
	return result


func has_live_asset_reference(asset_id: String) -> bool:
	var scan: Dictionary = AssetReferenceScanner.scan(current_project, AssetLibrary)
	return Dictionary(scan["live_by_asset"]).has(asset_id)


func save_project(path: String = "") -> Error:
	var target_path := path
	if target_path.is_empty():
		target_path = current_project.project_path
	if target_path.is_empty():
		return ERR_FILE_BAD_PATH

	var error := _save_to_path(target_path)
	if error == OK:
		current_project.project_path = target_path
		current_project.recovered_from_path = ""
		SettingsService.add_recent_project(target_path)
		_emit_dirty(false)
		project_saved.emit(target_path)
		EventBus.project_saved.emit(target_path)
	return error


func open_project(path: String) -> Error:
	return _open_project(path, false)


func recover_project(path: String) -> Error:
	return _open_project(path, true)


func _open_project(path: String, as_recovered_copy: bool) -> Error:
	last_load_error = {}
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

	var version: Variant = manifest.get("format_version", null)
	if version is float and version == float(AppInfo.PROJECT_FORMAT_VERSION):
		manifest["format_version"] = AppInfo.PROJECT_FORMAT_VERSION
		version = manifest["format_version"]
	if not (version is int) or version != AppInfo.PROJECT_FORMAT_VERSION:
		last_load_error = {"code": "unsupported_project_version", "args": {}}
		return ERR_FILE_UNRECOGNIZED
	var boundary_error := _validate_project_v2_boundary(manifest, canvas)
	if not boundary_error.is_empty():
		last_load_error = boundary_error
		return ERR_FILE_CORRUPT

	_normalize_loaded_project(manifest, canvas)
	var loaded_graphs := _load_graphs_from_files(files, manifest)
	var loaded_boards := _load_json_collection(files, manifest, "boards", "boards")
	var loaded_animations := _load_json_collection(files, manifest, "animations", "anim", ".anim")
	var load_error := int(loaded_graphs.get("error", OK))
	if load_error == OK:
		load_error = int(loaded_boards.get("error", OK))
	if load_error == OK:
		load_error = int(loaded_animations.get("error", OK))
	if load_error == OK:
		load_error = PaletteRegistry.load_custom_palettes_from_project(files, manifest)
	if load_error == OK:
		load_error = AssetLibrary.load_from_zip_files(files)
	if load_error != OK:
		return load_error
	_normalize_loaded_node_card_fields(canvas, loaded_graphs["graphs"])
	_normalize_loaded_sprite_sizes(canvas)

	current_project = ProjectModel.new()
	current_project.manifest = manifest
	current_project.canvas = canvas
	current_project.graphs = loaded_graphs["graphs"]
	current_project.boards = loaded_boards["items"]
	current_project.animations = loaded_animations["items"]
	current_project.project_path = "" if as_recovered_copy else path
	current_project.recovered_from_path = path if as_recovered_copy else ""
	current_project.dirty = false
	var recovery: Dictionary = recover_interrupted_runs_before_ui(false)
	_refresh_validation_warnings()

	if not as_recovered_copy:
		SettingsService.add_recent_project(path)
	else:
		_pending_recovery_autosaves.erase(path)
	UndoService.clear()
	project_loaded.emit(current_project)
	EventBus.project_opened.emit(path)
	_emit_dirty(as_recovered_copy or int(recovery.get("recovered_outputs", 0)) > 0)
	return OK


func recover_interrupted_runs_before_ui(mark_dirty: bool = true) -> Dictionary:
	var recovered_outputs := 0
	var recovered_graphs := 0
	for graph_id_value in current_project.graphs.keys():
		var graph_id := String(graph_id_value)
		var graph: PFGraph = GraphScript.from_json(current_project.graphs[graph_id])
		var coordinator := GenerationRunCoordinatorScript.new()
		var result: Dictionary = coordinator.recover_interrupted(graph)
		if not bool(result.get("ok", false)):
			return result
		var outputs: Dictionary = result.get("outputs", {})
		if outputs.is_empty():
			continue
		current_project.graphs[graph_id] = graph.to_json()
		recovered_outputs += outputs.size()
		recovered_graphs += 1
	if mark_dirty and recovered_outputs > 0:
		_emit_dirty(true)
	return {
		"ok": true,
		"recovered_outputs": recovered_outputs,
		"recovered_graphs": recovered_graphs,
		"dialog_count": 0,
		"network_count": 0,
		"worker_count": 0,
		"undo_count": 0,
	}


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


func get_pending_recovery_autosaves() -> Array:
	return _pending_recovery_autosaves.duplicate()


func mark_clean_shutdown() -> void:
	if FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


func _save_to_path(path: String) -> Error:
	_refresh_validation_warnings()
	_update_manifest_before_save()
	var entries := {
		"manifest.json": current_project.manifest,
		"canvas/canvas.json": _canvas_for_persistence(),
	}
	for graph_id in _sorted_graph_ids():
		entries["graphs/%s.json" % graph_id] = current_project.graphs[graph_id]
	for board_id in _sorted_ids(current_project.boards):
		entries["boards/%s.json" % board_id] = current_project.boards[board_id]
	for anim_id in _sorted_ids(current_project.animations):
		entries["anim/%s.anim.json" % anim_id] = current_project.animations[anim_id]
	var asset_entries := AssetLibrary.export_zip_entries()
	for asset_path in asset_entries.keys():
		entries[asset_path] = asset_entries[asset_path]
	var palette_entries := PaletteRegistry.export_custom_zip_entries()
	for palette_path in palette_entries.keys():
		entries[palette_path] = palette_entries[palette_path]
	return FileIOScript.zip_pack(entries, path)


func _refresh_validation_warnings() -> void:
	var scan: Dictionary = AssetReferenceScanner.scan(current_project, AssetLibrary)
	_validation_warnings = Array(scan.get("warnings", [])).duplicate(true)
	_validation_warnings.append_array(_scan_canvas_structure_warnings())


func _scan_canvas_structure_warnings() -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	var frames := {}
	for raw_item in current_project.canvas.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		if String(item.get("type", "")) == "frame":
			frames[String(item.get("id", ""))] = item

	for raw_item in current_project.canvas.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		if String(item.get("type", "")) != "node":
			continue
		var raw_frame_id: Variant = item.get("frame_id", null)
		var frame_id := "" if raw_frame_id == null else String(raw_frame_id)
		if frame_id.is_empty():
			continue
		var warning := {
			"path": "canvas.items[%s].frame_id" % String(item.get("id", "")),
			"frame_id": frame_id,
			"node_id": String(item.get("node_id", "")),
			"strength": "live",
		}
		if not frames.has(frame_id):
			warning["code"] = "frame_reference_not_found"
			warnings.append(warning)
			continue
		var frame: Dictionary = frames[frame_id]
		if String(frame.get("graph_id", "")) != String(item.get("graph_id", "")):
			warning["code"] = "frame_graph_mismatch"
			warnings.append(warning)
	return warnings


func _update_manifest_before_save() -> void:
	var source: Dictionary = current_project.manifest
	var entries: Dictionary = current_project.manifest.get("entries", {})
	entries["canvases"] = ["canvas"]
	entries["graphs"] = _sorted_graph_ids()
	entries["boards"] = _sorted_ids(current_project.boards)
	entries["animations"] = _sorted_ids(current_project.animations)
	entries["asset_count"] = AssetLibrary.get_all_meta().size()
	var canonical := {
		"format_version": AppInfo.PROJECT_FORMAT_VERSION,
		"app_version": AppInfo.APP_VERSION,
		"id": String(source.get("id", "")),
		"name": String(source.get("name", "Untitled")),
		"created_at": String(source.get("created_at", IdUtil.utc_now_iso())),
		"modified_at": IdUtil.utc_now_iso(),
		"entries": entries,
	}
	var custom_palettes := PaletteRegistry.get_custom_manifest_entries()
	canonical["custom_palettes"] = custom_palettes
	current_project.manifest = canonical


func _canvas_for_persistence() -> Dictionary:
	var result: Dictionary = current_project.canvas.duplicate(true)
	var items: Array = []
	for raw_item in result.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		var item_type := String(item.get("type", ""))
		if item_type == "batch_card":
			continue
		if item_type != "node":
			var clean_item := item.duplicate(true)
			_erase_legacy_canvas_keys(clean_item)
			items.append(clean_item)
			continue
		var display_item := {}
		for key in CANVAS_NODE_KEYS:
			if item.has(key):
				display_item[key] = item[key]
		items.append(display_item)
	result["items"] = items
	return result


func _normalize_loaded_project(manifest: Dictionary, canvas: Dictionary) -> void:
	var entries: Dictionary = manifest.get("entries", {})
	entries["asset_count"] = int(entries.get("asset_count", 0))
	if not entries.has("graphs"):
		entries["graphs"] = []
	if not entries.has("boards"):
		entries["boards"] = []
	if not entries.has("animations"):
		entries["animations"] = []
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
		item_data["scale_factor"] = maxi(1, int(item_data.get("scale_factor", 1)))
		item_data["z_index"] = int(item_data.get("z_index", 0))
		item_data["locked"] = bool(item_data.get("locked", false))
		var item_type := String(item_data.get("type", ""))
		if item_type == "node":
			item_data["node_id"] = String(item_data.get("node_id", ""))
			item_data["graph_id"] = String(item_data.get("graph_id", ""))
			item_data["collapsed"] = bool(item_data.get("collapsed", false))
			if item_data.has("frame_id") and item_data["frame_id"] != null:
				item_data["frame_id"] = String(item_data["frame_id"])
			_normalize_canvas_card_title(item_data)
		elif item_type == "sprite":
			_normalize_canvas_card_title(item_data)
			if item_data.has("size"):
				item_data["size"] = CardContract.size_array(
					CardContract.normalize_requested_size("sprite", item_data["size"])
				)
		elif item_type == "frame":
			item_data["graph_id"] = String(item_data.get("graph_id", ""))
			item_data["title"] = CardContract.normalize_display_title(item_data.get("title", ""))
			item_data["color"] = String(item_data.get("color", "4f6f8fff"))
			var raw_size: Variant = item_data.get("size", [320, 240])
			if not (raw_size is Array) or Array(raw_size).size() != 2:
				raw_size = [320, 240]
			item_data["size"] = [
				clampi(int(round(float(raw_size[0]))), 320, 32768),
				clampi(int(round(float(raw_size[1]))), 240, 32768),
			]
		normalized_items.append(item_data)
	canvas["items"] = normalized_items


func _validate_project_v2_boundary(manifest: Dictionary, canvas: Dictionary) -> Dictionary:
	if not (manifest.get("entries", null) is Dictionary):
		return _project_load_error("invalid_project_manifest", "manifest.entries")
	if not (canvas.get("camera", null) is Dictionary) or not (canvas.get("items", null) is Array):
		return _project_load_error("invalid_canvas_shape", "canvas")
	var camera: Dictionary = canvas["camera"]
	if (
		not _valid_number_pair(camera.get("center", null))
		or not (camera.get("zoom", null) is int or camera.get("zoom", null) is float)
	):
		return _project_load_error("invalid_canvas_shape", "canvas.camera")
	for index in range(canvas["items"].size()):
		var raw_item: Variant = canvas["items"][index]
		if not (raw_item is Dictionary):
			return _project_load_error("invalid_canvas_item", "canvas.items[%d]" % index)
		var item: Dictionary = raw_item
		var item_type := String(item.get("type", ""))
		if item_type == "batch_card":
			return _project_load_error("legacy_canvas_item", "canvas.items[%d].type" % index)
		for raw_key in item.keys():
			var key := String(raw_key)
			if key in LEGACY_CANVAS_KEYS or key.begins_with("compare_"):
				return _project_load_error(
					"legacy_canvas_field", "canvas.items[%d].%s" % [index, key]
				)
			if item_type == "node" and key not in CANVAS_NODE_KEYS:
				return _project_load_error(
					"unknown_canvas_node_field", "canvas.items[%d].%s" % [index, key]
				)
		if item_type not in ["node", "sprite", "frame"]:
			return _project_load_error("invalid_canvas_item", "canvas.items[%d].type" % index)
		if not _valid_number_pair(item.get("position", null)):
			return _project_load_error("invalid_canvas_item", "canvas.items[%d].position" % index)
	return {}


func _erase_legacy_canvas_keys(item: Dictionary) -> void:
	for key in item.keys():
		var name := String(key)
		if name in LEGACY_CANVAS_KEYS or name.begins_with("compare_"):
			item.erase(key)


func _project_load_error(code: String, path: String) -> Dictionary:
	return {"code": code, "args": {"path": path}}


func _valid_number_pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and (value[0] is int or value[0] is float)
		and (value[1] is int or value[1] is float)
	)


func _normalize_canvas_card_fields(item_data: Dictionary, card_type: String) -> void:
	_normalize_canvas_card_title(item_data)
	item_data["size"] = CardContract.size_array(
		CardContract.normalize_requested_size(card_type, item_data.get("size", null))
	)


func _normalize_canvas_card_title(item_data: Dictionary) -> void:
	var title := CardContract.normalize_display_title(item_data.get("display_title", ""))
	if title.is_empty():
		item_data.erase("display_title")
	else:
		item_data["display_title"] = title


func _node_type_for_canvas_item(item_data: Dictionary, graphs: Dictionary) -> String:
	var graph_data: Dictionary = graphs.get(String(item_data.get("graph_id", "")), {})
	for raw_node in graph_data.get("nodes", []):
		if (
			raw_node is Dictionary
			and String(raw_node.get("id", "")) == String(item_data.get("node_id", ""))
		):
			return String(raw_node.get("type", "unknown"))
	return "unknown"


func _normalize_loaded_node_card_fields(canvas: Dictionary, graphs: Dictionary) -> void:
	for raw_item in canvas.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		if String(item.get("type", "")) == "node":
			_normalize_canvas_card_fields(item, _node_type_for_canvas_item(item, graphs))


func _normalize_loaded_sprite_sizes(canvas: Dictionary) -> void:
	for raw_item in canvas.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		if String(item.get("type", "")) != "sprite" or item.has("size"):
			continue
		var image: Image = AssetLibrary.get_image(String(item.get("asset_id", "")))
		var image_size := image.get_size() if image != null else Vector2i.ZERO
		item["size"] = CardContract.size_array(
			CardContract.default_size_for_type(
				"sprite", image_size, maxi(1, int(item.get("scale_factor", 1)))
			)
		)


func _load_graphs_from_files(files: Dictionary, manifest: Dictionary) -> Dictionary:
	var graphs := {}
	var graph_ids := _manifest_graph_ids(manifest, files)
	for graph_id in graph_ids:
		var path := "graphs/%s.json" % graph_id
		if not files.has(path):
			return {"ok": false, "error": ERR_FILE_CORRUPT, "graphs": {}}
		var graph_data: Variant = FileIOScript.bytes_to_json(files[path])
		if not (graph_data is Dictionary):
			return {"ok": false, "error": ERR_PARSE_ERROR, "graphs": {}}
		_normalize_graph_json_integer_fields(graph_data)
		var parsed: Dictionary = GraphScript.parse_v2(graph_data)
		if not bool(parsed.get("ok", false)):
			last_load_error = Dictionary(parsed.get("error", {})).duplicate(true)
			return {"ok": false, "error": ERR_FILE_UNRECOGNIZED, "graphs": {}}
		graphs[graph_id] = _normalize_graph_data(graph_id, parsed["graph"])
	return {"ok": true, "error": OK, "graphs": graphs}


func _normalize_graph_json_integer_fields(graph_data: Dictionary) -> void:
	if (
		graph_data.get("graph_version", null) is float
		and graph_data["graph_version"] == float(GraphScript.GRAPH_VERSION)
	):
		graph_data["graph_version"] = GraphScript.GRAPH_VERSION
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary) or not (raw_node.get("params", null) is Dictionary):
			continue
		var node: Dictionary = raw_node
		var params: Dictionary = node["params"]
		match String(node.get("type", "")):
			"object_list":
				for raw_row in params.get("rows", []):
					if (
						raw_row is Dictionary
						and raw_row.get("count", null) is float
						and raw_row["count"] == floorf(raw_row["count"])
					):
						raw_row["count"] = int(raw_row["count"])
			"ai_generate":
				_normalize_known_ints(
					params, ["target_width", "target_height", "batch_size", "seed"]
				)
			"prompt_preset":
				var preset: Variant = params.get("preset", null)
				if preset is Dictionary:
					_normalize_known_ints(preset, ["prompt_preset_version"])
			"batch":
				for raw_snapshot in Dictionary(params.get("input_snapshots", {})).values():
					if not (raw_snapshot is Dictionary):
						continue
					if String(raw_snapshot.get("kind", "")) == "generation":
						_normalize_known_ints(
							raw_snapshot, ["target_width", "target_height", "requested_seed"]
						)
						_normalize_size_pair(raw_snapshot, "provider_output_size")
					elif String(raw_snapshot.get("kind", "")) == "cleanup":
						_normalize_size_pair(raw_snapshot, "effective_target_size")
				for raw_record in params.get("request_records", []):
					if raw_record is Dictionary:
						_normalize_known_ints(
							raw_record, ["requested_count", "received_count", "attempts"]
						)
				for raw_slot in params.get("result_slots", []):
					if raw_slot is Dictionary:
						_normalize_size_pair(raw_slot, "planned_size")


func _normalize_known_ints(data: Dictionary, keys: Array) -> void:
	for key in keys:
		if data.get(key, null) is float and data[key] == floorf(data[key]):
			data[key] = int(data[key])


func _normalize_size_pair(data: Dictionary, key: String) -> void:
	var value: Variant = data.get(key, null)
	if not (value is Array) or value.size() != 2:
		return
	for index in range(2):
		if value[index] is float and value[index] == floorf(value[index]):
			value[index] = int(value[index])


func _normalize_graph_data(graph_id: String, graph: PFGraph) -> Dictionary:
	if graph.id.is_empty():
		graph.id = graph_id
	return graph.to_json()


func _manifest_graph_ids(manifest: Dictionary, files: Dictionary) -> Array:
	var entries: Dictionary = manifest.get("entries", {})
	var graph_ids := []
	for raw_id in entries.get("graphs", []):
		var graph_id := String(raw_id)
		if not graph_id.is_empty():
			graph_ids.append(graph_id)
	if not graph_ids.is_empty():
		return graph_ids

	for path in files.keys():
		var file_path := String(path)
		if file_path.begins_with("graphs/") and file_path.ends_with(".json"):
			graph_ids.append(file_path.get_file().get_basename())
	graph_ids.sort()
	return graph_ids


func _sorted_graph_ids() -> Array:
	var graph_ids: Array = current_project.graphs.keys()
	graph_ids.sort()
	return graph_ids


func _sorted_ids(items: Dictionary) -> Array:
	var ids: Array = items.keys()
	ids.sort()
	return ids


func _load_json_collection(
	files: Dictionary,
	manifest: Dictionary,
	entry_key: String,
	directory: String,
	name_suffix: String = ""
) -> Dictionary:
	var items := {}
	var entries: Dictionary = manifest.get("entries", {})
	for raw_id in entries.get(entry_key, []):
		var item_id := String(raw_id)
		var path := "%s/%s%s.json" % [directory, item_id, name_suffix]
		if not files.has(path):
			return {"error": ERR_FILE_CORRUPT, "items": {}}
		var data: Variant = FileIOScript.bytes_to_json(files[path])
		if not (data is Dictionary):
			return {"error": ERR_PARSE_ERROR, "items": {}}
		items[item_id] = data
	return {"error": OK, "items": items}


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
			autosave_failed.emit(error, "user://autosave")


func _check_recovery_state() -> void:
	_pending_recovery_autosaves.clear()
	if not FileAccess.file_exists(LOCK_PATH):
		return

	_pending_recovery_autosaves = list_autosaves()
	if not _pending_recovery_autosaves.is_empty():
		recovery_available.emit(_pending_recovery_autosaves.duplicate())
		EventBus.recovery_available.emit(_pending_recovery_autosaves.duplicate())


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
