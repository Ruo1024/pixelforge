class_name PFCanvasCardContract
extends RefCounted

## Beta 0.6 card geometry and canvas-only field normalization.
## contract: PROJECT-FORMAT §4.1 and BETA-0.6-CARD-DESIGN-SPEC §6–§7.

const HEADER_HEIGHT := 44
const CONTENT_RAIL_HEIGHT := 32
const COLLAPSED_HEIGHT := 56
const PADDING := 16
const ACTION_ROW_HEIGHT := 40
const THUMBNAIL_SIZE := 128
const GAP := 12
const REQUEST_MAX := Vector2i(1600, 1200)
const TITLE_LIMIT := 80

const DEFAULT_SIZES := {
	"text_prompt": Vector2i(360, 300),
	"object_list": Vector2i(400, 520),
	"prompt_preset": Vector2i(320, 280),
	"pixel_cleanup": Vector2i(420, 680),
	"image_input": Vector2i(320, 380),
	"reference_set": Vector2i(400, 480),
	"ai_generate": Vector2i(400, 520),
	"batch": Vector2i(600, 240),
	"batch_card": Vector2i(600, 240),
	"sprite": Vector2i(320, 380),
	"unknown": Vector2i(320, 180),
}
const MIN_SIZES := {
	"text_prompt": Vector2i(320, 240),
	"object_list": Vector2i(360, 360),
	"prompt_preset": Vector2i(280, 220),
	"pixel_cleanup": Vector2i(360, 480),
	"image_input": Vector2i(280, 300),
	"reference_set": Vector2i(360, 320),
	"ai_generate": Vector2i(360, 400),
	"batch": Vector2i(360, 240),
	"batch_card": Vector2i(360, 240),
	"sprite": Vector2i(200, 188),
	"unknown": Vector2i(240, 144),
}


static func normalize_display_title(value: Variant) -> String:
	if not (value is String):
		return ""
	var normalized := String(value).replace("\r\n", " ").replace("\r", " ")
	normalized = normalized.replace("\n", " ").replace("\t", " ").strip_edges()
	return normalized.left(TITLE_LIMIT)


static func default_size_for_type(
	card_type: String, image_size: Vector2i = Vector2i.ZERO, scale_factor: int = 1
) -> Vector2i:
	if card_type == "sprite" and image_size.x > 0 and image_size.y > 0:
		var legacy_scale := maxi(1, scale_factor)
		return Vector2i(
			clampi(image_size.x * legacy_scale + 32, 200, REQUEST_MAX.x),
			clampi(image_size.y * legacy_scale + 60, 188, REQUEST_MAX.y)
		)
	return DEFAULT_SIZES.get(card_type, DEFAULT_SIZES["unknown"])


static func minimum_size_for_type(card_type: String) -> Vector2i:
	return MIN_SIZES.get(card_type, MIN_SIZES["unknown"])


static func normalize_requested_size(
	card_type: String, value: Variant, image_size: Vector2i = Vector2i.ZERO, scale_factor: int = 1
) -> Vector2i:
	var fallback := default_size_for_type(card_type, image_size, scale_factor)
	var values: Array = []
	if value is Vector2i:
		values = [value.x, value.y]
	elif value is Vector2:
		values = [value.x, value.y]
	elif value is Array and Array(value).size() == 2:
		values = value
	else:
		return fallback
	if not _is_number(values[0]) or not _is_number(values[1]):
		return fallback
	var minimum := minimum_size_for_type(card_type)
	var request_max := Vector2i(800, 1000) if card_type == "pixel_cleanup" else REQUEST_MAX
	return Vector2i(
		clampi(int(round(float(values[0]))), minimum.x, request_max.x),
		clampi(int(round(float(values[1]))), minimum.y, request_max.y)
	)


static func size_array(value: Vector2i) -> Array:
	return [value.x, value.y]


static func effective_size(
	card_type: String,
	requested_size: Vector2i,
	collapsed: bool,
	slot_count: int = 0,
	focus_active: bool = false
) -> Vector2i:
	if collapsed:
		return Vector2i(requested_size.x, COLLAPSED_HEIGHT)
	if card_type not in ["batch", "batch_card"]:
		return requested_size
	var geometry := batch_geometry(requested_size, slot_count, focus_active)
	return Vector2i(requested_size.x, int(geometry["effective_height"]))


static func batch_geometry(
	requested_size: Vector2i, slot_count: int, focus_active: bool = false
) -> Dictionary:
	var width := maxi(1, requested_size.x)
	var columns := maxi(
		1, int(floor(float(width - PADDING * 2 + GAP) / float(THUMBNAIL_SIZE + GAP)))
	)
	var safe_count := maxi(0, slot_count)
	var rows := int(ceil(float(safe_count) / float(columns))) if safe_count > 0 else 0
	var grid_height := rows * THUMBNAIL_SIZE + maxi(0, rows - 1) * GAP if rows > 0 else 0
	var focus_height := clampi(int(round(float(width - PADDING * 2) * 9.0 / 16.0)), 240, 480)
	var action_y := HEADER_HEIGHT + PADDING
	var preview_y := action_y + ACTION_ROW_HEIGHT + GAP
	var grid_y := preview_y + (focus_height + GAP if focus_active else 0)
	var required_height := maxi(240, grid_y + grid_height + PADDING)
	return {
		"columns": columns,
		"rows": rows,
		"slot_count": safe_count,
		"grid_height": grid_height,
		"focus_preview_height": focus_height,
		"action_y": action_y,
		"preview_y": preview_y,
		"grid_y": grid_y,
		"required_height": required_height,
		"effective_height": maxi(requested_size.y, required_height),
	}


static func slot_rect(requested_size: Vector2i, index: int, focus_active: bool = false) -> Rect2:
	var geometry := batch_geometry(requested_size, index + 1, focus_active)
	var columns := int(geometry["columns"])
	var column := index % columns
	var row := int(index / columns)
	return Rect2(
		Vector2(
			PADDING + column * (THUMBNAIL_SIZE + GAP),
			int(geometry["grid_y"]) + row * (THUMBNAIL_SIZE + GAP)
		),
		Vector2(THUMBNAIL_SIZE, THUMBNAIL_SIZE)
	)


static func lod_mode(camera_zoom: float) -> String:
	if camera_zoom < 0.25:
		return "map"
	if camera_zoom < 0.5:
		return "browse"
	if camera_zoom < 0.75:
		return "summary"
	if camera_zoom < 4.0:
		return "edit"
	return "inspect"


static func _is_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT]
