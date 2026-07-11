class_name PFBoard
extends RefCounted

## Finite grid/free-layer scene model serialized as boards/{id}.json.

const IdUtil := preload("res://core/util/id_util.gd")

const LAYER_TILE := "tile"
const LAYER_FREE := "free"
const BLENDS := ["normal", "add", "multiply"]

var id := ""
var name := "Board"
var grid := {"tile_size": 16, "cols": 60, "rows": 40}
var layers: Array = []
var extra := {}


func _init(
	board_name: String = "Board", cols: int = 60, rows: int = 40, tile_size: int = 16
) -> void:
	id = IdUtil.uuid_v4()
	name = board_name
	grid = {
		"tile_size": maxi(1, tile_size),
		"cols": maxi(1, cols),
		"rows": maxi(1, rows),
	}


func add_layer(layer_name: String, kind: String = LAYER_TILE) -> String:
	var normalized_kind := kind if kind in [LAYER_TILE, LAYER_FREE] else LAYER_TILE
	var layer := {
		"id": IdUtil.uuid_v4(),
		"name": layer_name,
		"kind": normalized_kind,
		"visible": true,
		"opacity": 1.0,
		"blend": "normal",
	}
	if normalized_kind == LAYER_TILE:
		layer["cells"] = {}
	else:
		layer["items"] = []
	layers.append(layer)
	return String(layer["id"])


func remove_layer(layer_id: String) -> bool:
	var index := _layer_index(layer_id)
	if index < 0:
		return false
	layers.remove_at(index)
	return true


func move_layer(layer_id: String, new_index: int) -> bool:
	var index := _layer_index(layer_id)
	if index < 0 or layers.is_empty():
		return false
	var layer: Dictionary = layers[index]
	layers.remove_at(index)
	layers.insert(clampi(new_index, 0, layers.size()), layer)
	return true


func set_layer_visuals(layer_id: String, visible: bool, opacity: float, blend: String) -> bool:
	var layer := get_layer(layer_id)
	if layer.is_empty():
		return false
	layer["visible"] = visible
	layer["opacity"] = clampf(opacity, 0.0, 1.0)
	layer["blend"] = blend if blend in BLENDS else "normal"
	return true


func set_cell(layer_id: String, cell: Vector2i, asset_id: String, variant: int = 0) -> bool:
	var layer := get_layer(layer_id)
	if String(layer.get("kind", "")) != LAYER_TILE or not is_cell_in_bounds(cell):
		return false
	var cells: Dictionary = layer["cells"]
	var key := cell_key(cell)
	if asset_id.is_empty():
		cells.erase(key)
	else:
		cells[key] = {"asset_id": asset_id, "variant": maxi(0, variant)}
	return true


func add_free_item(
	layer_id: String,
	asset_id: String,
	position: Vector2i,
	anim_id: String = "",
	anim_offset_ms: int = 0
) -> String:
	var layer := get_layer(layer_id)
	if String(layer.get("kind", "")) != LAYER_FREE or (asset_id.is_empty() and anim_id.is_empty()):
		return ""
	var item_id := IdUtil.uuid_v4()
	(
		layer["items"]
		. append(
			{
				"id": item_id,
				"asset_id": asset_id,
				"anim_id": anim_id if not anim_id.is_empty() else null,
				"pos": [position.x, position.y],
				"z": 0,
				"flip_h": false,
				"anim_offset_ms": maxi(0, anim_offset_ms),
			}
		)
	)
	return item_id


func get_layer(layer_id: String) -> Dictionary:
	var index := _layer_index(layer_id)
	return layers[index] if index >= 0 else {}


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(grid["cols"]) and cell.y < int(grid["rows"])


func get_referenced_asset_ids() -> Array:
	var refs := {}
	for layer_value in layers:
		var layer: Dictionary = layer_value
		if String(layer.get("kind", "")) == LAYER_TILE:
			for cell_value in Dictionary(layer.get("cells", {})).values():
				refs[String(Dictionary(cell_value).get("asset_id", ""))] = true
		else:
			for item_value in layer.get("items", []):
				var asset_id := String(Dictionary(item_value).get("asset_id", ""))
				if not asset_id.is_empty():
					refs[asset_id] = true
	refs.erase("")
	return refs.keys()


func to_json() -> Dictionary:
	var data: Dictionary = extra.duplicate(true)
	data.merge(
		{"id": id, "name": name, "grid": grid.duplicate(true), "layers": layers.duplicate(true)},
		true
	)
	return data


static func from_json(data: Dictionary) -> PFBoard:
	var raw_grid: Dictionary = data.get("grid", {})
	var board := PFBoard.new(
		String(data.get("name", "Board")),
		int(raw_grid.get("cols", 60)),
		int(raw_grid.get("rows", 40)),
		int(raw_grid.get("tile_size", 16))
	)
	board.id = String(data.get("id", board.id))
	board.extra = data.duplicate(true)
	for known_key in ["id", "name", "grid", "layers"]:
		board.extra.erase(known_key)
	board.layers.clear()
	for layer_value in data.get("layers", []):
		if not (layer_value is Dictionary):
			continue
		var layer: Dictionary = layer_value.duplicate(true)
		layer["id"] = String(layer.get("id", IdUtil.uuid_v4()))
		layer["name"] = String(layer.get("name", "Layer"))
		layer["kind"] = String(layer.get("kind", LAYER_TILE))
		layer["visible"] = bool(layer.get("visible", true))
		layer["opacity"] = clampf(float(layer.get("opacity", 1.0)), 0.0, 1.0)
		layer["blend"] = String(layer.get("blend", "normal"))
		if layer["kind"] == LAYER_TILE:
			layer["cells"] = Dictionary(layer.get("cells", {}))
		else:
			layer["kind"] = LAYER_FREE
			layer["items"] = Array(layer.get("items", []))
		board.layers.append(layer)
	return board


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)


func _layer_index(layer_id: String) -> int:
	for index in range(layers.size()):
		if String(Dictionary(layers[index]).get("id", "")) == layer_id:
			return index
	return -1
