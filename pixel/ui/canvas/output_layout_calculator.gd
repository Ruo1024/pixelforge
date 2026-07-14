class_name PFOutputLayoutCalculator
extends RefCounted

## Pure §10.2 Output geometry. Scrollbar metrics never participate in column width.

const DEFAULT_WIDTH := 600
const MIN_WIDTH := 360
const MAX_WIDTH := 960
const TOP_RAIL_HEIGHT := 32
const HORIZONTAL_PADDING := 16
const VERTICAL_PADDING := 16
const TILE_GAP := 8
const MAX_COLUMNS := 4
const MAX_VISIBLE_ROWS := 3
const TILE_MIN := 96
const TILE_MAX := 176
const EMPTY_HEIGHT := 240
const SCROLLBAR_VISUAL_WIDTH := 4
const SCROLLBAR_HIT_WIDTH := 12


static func calculate(
	card_width: int, slot_count: int, single_source_size: Vector2i = Vector2i(1, 1)
) -> Dictionary:
	var width := clamp_output_width(card_width)
	var count := maxi(0, slot_count)
	if count == 0:
		return {
			"width": width,
			"columns": 0,
			"rows": 0,
			"visible_rows": 0,
			"tile_size": 0,
			"grid_height": 0,
			"content_height": 0,
			"natural_height": EMPTY_HEIGHT,
		}
	if count == 1:
		var viewport_height := single_viewport_height(width, single_source_size)
		return {
			"width": width,
			"columns": 1,
			"rows": 1,
			"visible_rows": 1,
			"tile_size": width - HORIZONTAL_PADDING * 2,
			"grid_height": viewport_height,
			"content_height": viewport_height,
			"natural_height": TOP_RAIL_HEIGHT + VERTICAL_PADDING * 2 + viewport_height,
		}
	var capacity_columns := clampi(
		int(floor(float(width - HORIZONTAL_PADDING * 2 + TILE_GAP) / float(TILE_MIN + TILE_GAP))),
		1,
		MAX_COLUMNS
	)
	var desired_columns := clampi(int(ceil(sqrt(float(count)))), 1, MAX_COLUMNS)
	var columns := mini(capacity_columns, desired_columns)
	var tile_size := mini(
		TILE_MAX,
		int(
			floor(float(width - HORIZONTAL_PADDING * 2 - (columns - 1) * TILE_GAP) / float(columns))
		)
	)
	var rows := int(ceil(float(count) / float(columns)))
	var visible_rows := mini(rows, MAX_VISIBLE_ROWS)
	var grid_height := visible_rows * tile_size + maxi(0, visible_rows - 1) * TILE_GAP
	var content_height := rows * tile_size + maxi(0, rows - 1) * TILE_GAP
	return {
		"width": width,
		"columns": columns,
		"rows": rows,
		"visible_rows": visible_rows,
		"tile_size": tile_size,
		"grid_height": grid_height,
		"content_height": content_height,
		"natural_height": TOP_RAIL_HEIGHT + VERTICAL_PADDING * 2 + grid_height,
	}


static func single_viewport_height(card_width: int, source_size: Vector2i) -> int:
	var width := clamp_output_width(card_width)
	var source_width := maxi(1, source_size.x)
	var source_height := maxi(1, source_size.y)
	return clampi(
		int(round(float(width - HORIZONTAL_PADDING * 2) * source_height / source_width)), 176, 420
	)


static func clamp_output_width(value: int) -> int:
	return clampi(value, MIN_WIDTH, MAX_WIDTH)


static func natural_height(card_width: int, slot_count: int) -> int:
	return int(calculate(card_width, slot_count)["natural_height"])
