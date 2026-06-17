class_name PFPaletteRegistry
extends RefCounted

## 调色板解析入口。
## 职责：把内置调色板、自定义颜色数组、JSON 字典或 JSON 文件统一解析成 PFPalette。

const PaletteScript := preload("res://core/pixel/palette.gd")

const CUSTOM_PALETTE_DIR := "palettes"
const HEX_DIGITS := "0123456789ABCDEFabcdef"
const BUILTIN_IDS := [
	"db16",
	"db32",
	"pico8",
	"endesga32",
	"endesga64",
	"aap64",
	"gb_4",
	"nes_full",
	"bw_2",
]

static var _builtin_cache := {}
static var _custom_cache := {}


static func resolve(params: Dictionary, fallback_id: String = "db32") -> PFPalette:
	if params.has("palette") and params["palette"] is PFPalette:
		return params["palette"].duplicate_palette()
	if params.has("palette_json") and params["palette_json"] is Dictionary:
		return PaletteScript.from_json(params["palette_json"])
	if params.has("palette_colors"):
		var colors_palette := PaletteScript.from_color_values(
			String(params.get("palette_id", "custom")),
			String(params.get("palette_name", "Custom")),
			params["palette_colors"]
		)
		if colors_palette != null:
			return colors_palette
	if params.has("palette_path"):
		var path_palette := load_from_path(String(params["palette_path"]))
		if path_palette != null:
			return path_palette

	var palette_id := String(params.get("palette_id", fallback_id))
	if _custom_cache.has(palette_id):
		return _custom_cache[palette_id].duplicate_palette()
	var builtin := load_builtin(palette_id)
	if builtin != null:
		return builtin
	return load_builtin(fallback_id)


static func load_builtin(palette_id: String) -> PFPalette:
	if _builtin_cache.has(palette_id):
		return _builtin_cache[palette_id].duplicate_palette()

	var path := "res://assets/palettes/%s.json" % palette_id
	var palette := load_from_path(path)
	if palette == null:
		return null

	_builtin_cache[palette_id] = palette
	return palette.duplicate_palette()


static func load_from_path(path: String) -> PFPalette:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null

	var parsed := parse_palette_file(path)
	if not bool(parsed.get("ok", false)):
		return null
	return parsed["palette"].duplicate_palette()


static func parse_palette_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "Palette file does not exist: %s" % path}
	return parse_palette_text(FileAccess.get_file_as_string(path), path)


static func parse_palette_text(text: String, source_name: String = "palette JSON") -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"error":
			(
				"JSON parse error in %s at line %d: %s"
				% [source_name, parser.get_error_line(), parser.get_error_message()]
			),
		}
	return parse_palette_data(parser.data, source_name)


static func parse_palette_data(value: Variant, source_name: String = "palette JSON") -> Dictionary:
	if not (value is Dictionary):
		return {"ok": false, "error": "%s must be a JSON object." % source_name}

	var data: Dictionary = value
	if not data.has("colors"):
		return {"ok": false, "error": "%s is missing required field: colors." % source_name}
	if not (data["colors"] is Array):
		return {"ok": false, "error": "%s.colors must be an array." % source_name}

	var raw_colors: Array = data["colors"]
	if raw_colors.size() < PaletteScript.MIN_PALETTE_COLORS:
		return {
			"ok": false,
			"error":
			(
				"%s.colors must contain at least %d colors."
				% [source_name, PaletteScript.MIN_PALETTE_COLORS]
			),
		}
	if raw_colors.size() > PaletteScript.MAX_PALETTE_COLORS:
		return {
			"ok": false,
			"error":
			(
				"%s.colors must contain at most %d colors."
				% [source_name, PaletteScript.MAX_PALETTE_COLORS]
			),
		}

	var normalized_colors := []
	for index in range(raw_colors.size()):
		if not (raw_colors[index] is String):
			return {
				"ok": false,
				"error": "%s.colors[%d] must be a hex string." % [source_name, index],
			}
		var hex_text := _normalize_hex_rgb(String(raw_colors[index]))
		if hex_text.is_empty():
			return {
				"ok": false,
				"error": "%s.colors[%d] must be #RRGGBB or RRGGBB." % [source_name, index],
			}
		normalized_colors.append(hex_text)

	var palette_id := String(data.get("id", source_name.get_file().get_basename()))
	var palette_name := String(data.get("name", palette_id))
	return {
		"ok": true,
		"palette":
		PaletteScript.from_json(
			{"id": palette_id, "name": palette_name, "colors": normalized_colors}
		),
	}


static func import_custom_from_path(path: String) -> Dictionary:
	var parsed := parse_palette_file(path)
	if not bool(parsed.get("ok", false)):
		return parsed

	var palette: PFPalette = parsed["palette"]
	var registered := register_custom_palette(
		palette, {"fallback_id": path.get_file().get_basename(), "preserve_id": false}
	)
	return {"ok": true, "palette": registered}


static func register_custom_palette(palette: PFPalette, options: Dictionary = {}) -> PFPalette:
	var fallback_id := String(options.get("fallback_id", palette.name))
	var palette_id := _sanitize_custom_id(palette.id, fallback_id)
	if not bool(options.get("preserve_id", false)):
		palette_id = _unique_custom_id(palette_id)

	var palette_name := palette.name if not palette.name.is_empty() else palette_id
	var stored := PFPalette.new(palette_id, palette_name, palette.colors)
	_custom_cache[palette_id] = stored
	return stored.duplicate_palette()


static func unregister_custom_palette(palette_id: String) -> bool:
	if not _custom_cache.has(palette_id):
		return false
	_custom_cache.erase(palette_id)
	return true


static func clear_custom_palettes() -> void:
	_custom_cache.clear()


static func is_custom_palette(palette_id: String) -> bool:
	return _custom_cache.has(palette_id)


static func get_custom_ids() -> Array:
	var ids := _custom_cache.keys()
	ids.sort()
	return ids


static func get_palette_name(palette_id: String) -> String:
	if _custom_cache.has(palette_id):
		var custom: PFPalette = _custom_cache[palette_id]
		return custom.name
	var builtin := load_builtin(palette_id)
	if builtin != null:
		return builtin.name
	return palette_id


static func get_custom_manifest_entries() -> Array:
	var manifest_entries := []
	for palette_id in get_custom_ids():
		var palette: PFPalette = _custom_cache[palette_id]
		(
			manifest_entries
			. append(
				{
					"id": palette_id,
					"name": palette.name,
					"path": "%s/%s.json" % [CUSTOM_PALETTE_DIR, palette_id],
				}
			)
		)
	return manifest_entries


static func export_custom_zip_entries() -> Dictionary:
	var entries := {}
	for palette_id in get_custom_ids():
		entries["%s/%s.json" % [CUSTOM_PALETTE_DIR, palette_id]] = _palette_to_json(
			_custom_cache[palette_id]
		)
	return entries


static func load_custom_palettes_from_project(files: Dictionary, manifest: Dictionary) -> Error:
	clear_custom_palettes()
	var raw_entries: Variant = manifest.get("custom_palettes", [])
	if raw_entries == null:
		return OK
	if not (raw_entries is Array):
		return ERR_PARSE_ERROR

	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			return ERR_PARSE_ERROR
		var entry: Dictionary = raw_entry
		var path := String(entry.get("path", ""))
		if path.is_empty() or not files.has(path):
			return ERR_FILE_CORRUPT

		var bytes: PackedByteArray = files[path]
		var parsed := parse_palette_text(bytes.get_string_from_utf8(), path)
		if not bool(parsed.get("ok", false)):
			return ERR_PARSE_ERROR

		var parsed_palette: PFPalette = parsed["palette"]
		var manifest_id := String(entry.get("id", parsed_palette.id))
		var manifest_name := String(entry.get("name", parsed_palette.name))
		var stored := PFPalette.new(manifest_id, manifest_name, parsed_palette.colors)
		var normalized_id := _sanitize_custom_id(stored.id, path.get_file().get_basename())
		if _custom_cache.has(normalized_id) or BUILTIN_IDS.has(normalized_id):
			return ERR_FILE_CORRUPT
		register_custom_palette(stored, {"fallback_id": normalized_id, "preserve_id": true})
	return OK


static func get_builtin_ids() -> Array:
	return BUILTIN_IDS.duplicate()


static func _palette_to_json(palette: PFPalette) -> Dictionary:
	var colors := []
	for color in palette.colors:
		colors.append(PaletteScript.color_to_hex(color))
	return {
		"id": palette.id,
		"name": palette.name,
		"colors": colors,
		"source": "custom",
		"license": "",
	}


static func _normalize_hex_rgb(hex_text: String) -> String:
	var normalized := hex_text.strip_edges().trim_prefix("#")
	if normalized.length() != 6:
		return ""
	for index in range(normalized.length()):
		if HEX_DIGITS.find(normalized.substr(index, 1)) < 0:
			return ""
	return "#%s" % normalized.to_upper()


static func _sanitize_custom_id(raw_id: String, fallback_id: String) -> String:
	var source := raw_id.strip_edges().to_lower()
	if source.is_empty():
		source = fallback_id.strip_edges().to_lower()
	if source.is_empty():
		source = "palette"

	var output := ""
	for index in range(source.length()):
		var character := source.substr(index, 1)
		var code := character.unicode_at(0)
		var is_digit := code >= 48 and code <= 57
		var is_lower := code >= 97 and code <= 122
		if is_digit or is_lower:
			output += character
		elif character == "-" or character == "_":
			output += "_"
		else:
			output += "_"

	while output.contains("__"):
		output = output.replace("__", "_")
	output = output.trim_prefix("_").trim_suffix("_")
	if output.is_empty():
		output = "palette"
	if not output.begins_with("custom_"):
		output = "custom_%s" % output
	return output


static func _unique_custom_id(base_id: String) -> String:
	var candidate := base_id
	var suffix := 2
	while _custom_cache.has(candidate) or BUILTIN_IDS.has(candidate):
		candidate = "%s_%d" % [base_id, suffix]
		suffix += 1
	return candidate
