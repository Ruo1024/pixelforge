class_name PFAssetLibrary
extends Node

## 项目素材库。
## 职责：注册 Image、维护 meta、PNG 字节和一个简单 LRU 图像缓存；保存时导出 assets/{id}.png/meta.json。

signal asset_added(asset_id: String)
signal asset_removed(asset_id: String)

const CACHE_LIMIT_BYTES := 256 * 1024 * 1024
const IdUtil := preload("res://core/util/id_util.gd")
const ImageMath := preload("res://core/util/image_math.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const Log := preload("res://core/util/log_util.gd")
const SENSITIVE_KEY_FRAGMENTS := [
	"api_key",
	"authorization",
	"credential",
	"header",
	"password",
	"raw",
	"response",
	"secret",
	"token"
]
const GENERATION_SNAPSHOT_KEYS := [
	"provider_id",
	"model_id",
	"mode",
	"target_width",
	"target_height",
	"provider_output_size",
	"actual_width",
	"actual_height",
	"requested_seed",
	"actual_seed",
	"run_id",
	"request_id",
	"source_node_id",
	"source_row_id",
	"prompt_preset_id",
	"prompt_prefix",
	"prompt",
	"reference_asset_ids",
	"reference_content_sha256s",
	"extra",
]

var _metadata := {}
var _png_bytes := {}
var _image_cache := {}
var _lru_order: Array = []
var _ref_counts := {}
var _bitmap_status := {}
var _cache_limit_bytes := CACHE_LIMIT_BYTES
var _cache_bytes := 0


func clear() -> void:
	_metadata.clear()
	_png_bytes.clear()
	_image_cache.clear()
	_lru_order.clear()
	_ref_counts.clear()
	_bitmap_status.clear()
	_cache_limit_bytes = CACHE_LIMIT_BYTES
	_cache_bytes = 0


func register_image(image: Image, name: String, extra_meta: Dictionary = {}) -> String:
	var asset_id := String(extra_meta.get("id", IdUtil.uuid_v4()))
	var rgba: Image = ImageMath.duplicate_rgba8(image)
	var now: String = IdUtil.utc_now_iso()
	var default_provenance := {
		"provider": null,
		"model": null,
		"prompt": "",
		"seed": null,
		"parent_asset": null,
		"graph_id": null,
		"created_at": now,
	}

	var meta := {
		"id": asset_id,
		"name": name,
		"tags": extra_meta.get("tags", []),
		"size": [rgba.get_width(), rgba.get_height()],
		"origin": extra_meta.get("origin", "imported"),
		"provenance": extra_meta.get("provenance", default_provenance),
		"palette_ref": extra_meta.get("palette_ref", null),
		"editor_palette": extra_meta.get("editor_palette", null),
		"anim": extra_meta.get("anim", null),
	}

	var raw_snapshot: Variant = Dictionary(meta.get("provenance", {})).get(
		"generation_snapshot", null
	)
	if raw_snapshot is Dictionary and not validate_generation_snapshot(raw_snapshot):
		return ""
	var safe_meta := _meta_for_persistence(meta)
	_metadata[asset_id] = safe_meta
	_png_bytes[asset_id] = rgba.save_png_to_buffer()
	_store_in_cache(asset_id, rgba)
	_ref_counts[asset_id] = int(_ref_counts.get(asset_id, 0))
	_bitmap_status[asset_id] = "ready"

	asset_added.emit(asset_id)
	EventBus.asset_added.emit(asset_id)
	return asset_id


func load_from_zip_files(files: Dictionary) -> Error:
	clear()
	for file_name in files.keys():
		var path := String(file_name)
		if path.begins_with("assets/") and path.ends_with(".meta.json"):
			var meta: Variant = FileIOScript.bytes_to_json(files[file_name])
			if meta is Dictionary and meta.has("id"):
				_metadata[String(meta["id"])] = meta

	for asset_id in _metadata.keys():
		var png_path := "assets/%s.png" % asset_id
		if not files.has(png_path):
			Log.warn("Asset PNG missing from project", {"asset_id": asset_id})
			_bitmap_status[asset_id] = "missing"
			continue

		var bytes: PackedByteArray = files[png_path]
		_png_bytes[asset_id] = bytes
		if not _has_png_signature(bytes):
			_bitmap_status[asset_id] = "decode_failed"
			Log.warn("Asset PNG signature is invalid", {"asset_id": asset_id})
			continue
		var image := Image.new()
		var load_error := image.load_png_from_buffer(bytes)
		if load_error == OK:
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			_store_in_cache(asset_id, image)
			_bitmap_status[asset_id] = "ready"
		else:
			_bitmap_status[asset_id] = "decode_failed"
			Log.warn("Asset PNG could not be decoded", {"asset_id": asset_id, "error": load_error})

	return OK


func export_zip_entries() -> Dictionary:
	var entries := {}
	for asset_id in _metadata.keys():
		entries["assets/%s.meta.json" % asset_id] = _meta_for_persistence(_metadata[asset_id])
		if _png_bytes.has(asset_id):
			entries["assets/%s.png" % asset_id] = _png_bytes[asset_id]
	return entries


func _meta_for_persistence(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var provenance: Variant = result.get("provenance", null)
	if not (provenance is Dictionary):
		return result
	var provenance_copy: Dictionary = provenance
	var snapshot: Variant = provenance_copy.get("generation_snapshot", null)
	if not (snapshot is Dictionary):
		return result
	var safe_snapshot := {}
	for key in [
		"provider_id",
		"model_id",
		"mode",
		"target_width",
		"target_height",
		"provider_output_size",
		"actual_width",
		"actual_height",
		"requested_seed",
		"actual_seed",
		"run_id",
		"request_id",
		"source_node_id",
		"source_row_id",
		"prompt_preset_id",
		"prompt_prefix",
		"prompt",
		"reference_asset_ids",
		"reference_content_sha256s",
		"extra",
	]:
		if snapshot.has(key):
			safe_snapshot[key] = _safe_persisted_value(snapshot[key])
	provenance_copy["generation_snapshot"] = safe_snapshot
	result["provenance"] = provenance_copy
	return result


func _safe_persisted_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for raw_key in value:
			var key := String(raw_key)
			var normalized := key.to_lower()
			var forbidden := false
			for fragment in SENSITIVE_KEY_FRAGMENTS:
				if fragment in normalized:
					forbidden = true
					break
			if not forbidden:
				result[key] = _safe_persisted_value(value[raw_key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_safe_persisted_value(item))
		return result
	return value


static func validate_generation_snapshot(snapshot: Dictionary) -> bool:
	if snapshot.size() != GENERATION_SNAPSHOT_KEYS.size():
		return false
	for key in GENERATION_SNAPSHOT_KEYS:
		if not snapshot.has(key):
			return false
	for key in [
		"provider_id",
		"model_id",
		"mode",
		"run_id",
		"request_id",
		"source_node_id",
		"source_row_id",
		"prompt_preset_id",
		"prompt_prefix",
		"prompt",
	]:
		if not (snapshot[key] is String):
			return false
	if (
		String(snapshot["provider_id"]).is_empty()
		or String(snapshot["model_id"]).is_empty()
		or String(snapshot["run_id"]).is_empty()
		or String(snapshot["request_id"]).is_empty()
		or String(snapshot["source_node_id"]).is_empty()
		or String(snapshot["mode"]) not in ["txt2img", "img2img"]
	):
		return false
	for key in ["target_width", "target_height", "actual_width", "actual_height"]:
		if not (snapshot[key] is int) or int(snapshot[key]) < 1:
			return false
	if not _positive_int_pair(snapshot["provider_output_size"]):
		return false
	if (
		not (snapshot["requested_seed"] is int)
		or int(snapshot["requested_seed"]) < -1
		or int(snapshot["requested_seed"]) > 2147483647
	):
		return false
	if (
		snapshot["actual_seed"] != null
		and (
			not (snapshot["actual_seed"] is int)
			or int(snapshot["actual_seed"]) < 0
			or int(snapshot["actual_seed"]) > 2147483647
		)
	):
		return false
	if (
		not (snapshot["reference_asset_ids"] is Array)
		or not (snapshot["reference_content_sha256s"] is Array)
		or snapshot["reference_asset_ids"].size() != snapshot["reference_content_sha256s"].size()
		or not (snapshot["extra"] is Dictionary)
	):
		return false
	for index in range(snapshot["reference_asset_ids"].size()):
		if (
			not (snapshot["reference_asset_ids"][index] is String)
			or String(snapshot["reference_asset_ids"][index]).is_empty()
			or not _is_lower_sha256(String(snapshot["reference_content_sha256s"][index]))
		):
			return false
	return true


static func _positive_int_pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value[0] is int
		and value[1] is int
		and int(value[0]) > 0
		and int(value[1]) > 0
	)


static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func has_asset(asset_id: String) -> bool:
	return _metadata.has(asset_id)


func get_bitmap_status(asset_id: String) -> String:
	return String(_bitmap_status.get(asset_id, "missing" if has_asset(asset_id) else "not_found"))


func get_image(asset_id: String) -> Image:
	if _image_cache.has(asset_id):
		_touch_lru(asset_id)
		return _image_cache[asset_id].duplicate()

	if get_bitmap_status(asset_id) != "ready" or not _png_bytes.has(asset_id):
		return null

	var image := Image.new()
	var error := image.load_png_from_buffer(_png_bytes[asset_id])
	if error != OK:
		Log.warn("Failed to decode asset PNG", {"asset_id": asset_id, "error": error})
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	_store_in_cache(asset_id, image)
	return image.duplicate()


func get_asset_meta(asset_id: String) -> Dictionary:
	return _metadata.get(asset_id, {}).duplicate(true)


func get_all_meta() -> Dictionary:
	return _metadata.duplicate(true)


func add_ref(asset_id: String) -> void:
	_ref_counts[asset_id] = int(_ref_counts.get(asset_id, 0)) + 1


func release_ref(asset_id: String) -> void:
	_ref_counts[asset_id] = maxi(0, int(_ref_counts.get(asset_id, 0)) - 1)


func get_ref_count(asset_id: String) -> int:
	return int(_ref_counts.get(asset_id, 0))


func get_cache_bytes() -> int:
	return _cache_bytes


func get_cache_limit_bytes() -> int:
	return _cache_limit_bytes


func configure_cache_limit(max_bytes: int) -> void:
	_cache_limit_bytes = maxi(1, max_bytes)
	_prune_cache()


func get_cached_asset_ids() -> Array:
	return _lru_order.duplicate()


func estimate_cache_bytes(image: Image) -> int:
	var rgba: Image = ImageMath.duplicate_rgba8(image)
	return ImageMath.estimate_rgba8_bytes(rgba)


func remove_asset(asset_id: String) -> Error:
	if get_ref_count(asset_id) > 0 or _is_referenced_by_project(asset_id):
		return ERR_BUSY

	_metadata.erase(asset_id)
	_png_bytes.erase(asset_id)
	_remove_from_cache(asset_id)
	_ref_counts.erase(asset_id)
	_bitmap_status.erase(asset_id)
	asset_removed.emit(asset_id)
	EventBus.asset_removed.emit(asset_id)
	return OK


func _is_referenced_by_project(asset_id: String) -> bool:
	var project_service := get_tree().root.get_node_or_null("ProjectService")
	return (
		project_service != null
		and project_service.has_method("has_live_asset_reference")
		and project_service.has_live_asset_reference(asset_id)
	)


func _store_in_cache(asset_id: String, image: Image) -> void:
	_remove_from_cache(asset_id)
	var copy: Image = ImageMath.duplicate_rgba8(image)
	_image_cache[asset_id] = copy
	# 缓存统一保存 RGBA8 图像。width * height * 4 与 Image.get_data().size()
	# 的字节单位一致，但不会为计费额外创建 PackedByteArray。
	_cache_bytes += estimate_cache_bytes(copy)
	_touch_lru(asset_id)
	_prune_cache()


func _touch_lru(asset_id: String) -> void:
	_lru_order.erase(asset_id)
	_lru_order.append(asset_id)


func _remove_from_cache(asset_id: String) -> void:
	if not _image_cache.has(asset_id):
		return

	var old_image: Image = _image_cache[asset_id]
	_cache_bytes -= estimate_cache_bytes(old_image)
	_image_cache.erase(asset_id)
	_lru_order.erase(asset_id)
	_cache_bytes = maxi(0, _cache_bytes)


func _prune_cache() -> void:
	while _cache_bytes > _cache_limit_bytes and not _lru_order.is_empty():
		var oldest_id := String(_lru_order.pop_front())
		_remove_from_cache(oldest_id)


func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	return bytes.size() >= signature.size() and bytes.slice(0, signature.size()) == signature
