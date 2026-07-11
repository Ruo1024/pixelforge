class_name PFTerrainBrush
extends RefCounted

## Incremental blob brush; each edit recomputes the changed cell and its eight neighbors.

const Blob := preload("res://core/board/terrain_blob.gd")


func paint(
	board: PFBoard, layer_id: String, cell: Vector2i, group: PFTerrainGroup, erase: bool = false
) -> Dictionary:
	var layer := board.get_layer(layer_id)
	if String(layer.get("kind", "")) != PFBoard.LAYER_TILE or not board.is_cell_in_bounds(cell):
		return {"ok": false, "fallback_cells": []}
	var occupied: Dictionary = layer["cells"]
	if erase:
		occupied.erase(PFBoard.cell_key(cell))
	else:
		occupied[PFBoard.cell_key(cell)] = {"asset_id": "", "variant": 0}
	var fallback_cells := []
	for offset in [Vector2i.ZERO] + Blob.OFFSETS:
		var target: Vector2i = cell + offset
		var key := PFBoard.cell_key(target)
		if not board.is_cell_in_bounds(target) or not occupied.has(key):
			continue
		var mask := Blob.neighbor_mask(occupied, target)
		var role := Blob.role_47(mask) if group.mode == 47 else Blob.role_16(mask)
		var choice := group.choose_asset(role, target)
		occupied[key] = {
			"asset_id": choice["asset_id"],
			"variant": choice["variant"],
			"terrain_role": role,
			"fallback": choice["fallback"],
		}
		if bool(choice["fallback"]):
			fallback_cells.append(target)
	return {"ok": true, "fallback_cells": fallback_cells}


func rectangle_fill(
	board: PFBoard, layer_id: String, rect: Rect2i, group: PFTerrainGroup
) -> Dictionary:
	var fallbacks := []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var result := paint(board, layer_id, Vector2i(x, y), group)
			fallbacks.append_array(result.get("fallback_cells", []))
	return {"ok": true, "fallback_cells": fallbacks}


func flood_fill(
	board: PFBoard, layer_id: String, start: Vector2i, group: PFTerrainGroup
) -> Dictionary:
	var layer := board.get_layer(layer_id)
	if String(layer.get("kind", "")) != PFBoard.LAYER_TILE:
		return {"ok": false, "fallback_cells": []}
	var cells: Dictionary = layer["cells"]
	var target_occupied := cells.has(PFBoard.cell_key(start))
	var queue := [start]
	var visited := {}
	var fallbacks := []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var key := PFBoard.cell_key(cell)
		if visited.has(key) or not board.is_cell_in_bounds(cell):
			continue
		visited[key] = true
		if cells.has(key) != target_occupied:
			continue
		var result := paint(board, layer_id, cell, group, false)
		fallbacks.append_array(result.get("fallback_cells", []))
		for offset in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			queue.append(cell + offset)
	return {"ok": true, "fallback_cells": fallbacks}
