class_name PFTerrainBlob
extends RefCounted

## Deterministic 8-neighbor blob normalization and stable terrain variants.

const N := 1 << 0
const NE := 1 << 1
const E := 1 << 2
const SE := 1 << 3
const S := 1 << 4
const SW := 1 << 5
const W := 1 << 6
const NW := 1 << 7

const OFFSETS := [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]


static func normalize_47(mask: int) -> int:
	var normalized := mask & 0xFF
	if not (normalized & N and normalized & E):
		normalized &= ~NE
	if not (normalized & E and normalized & S):
		normalized &= ~SE
	if not (normalized & S and normalized & W):
		normalized &= ~SW
	if not (normalized & W and normalized & N):
		normalized &= ~NW
	return normalized


static func role_47(mask: int) -> int:
	return _valid_47_masks().find(normalize_47(mask))


static func role_16(mask: int) -> int:
	var role := 0
	role |= 1 if mask & N else 0
	role |= 2 if mask & E else 0
	role |= 4 if mask & S else 0
	role |= 8 if mask & W else 0
	return role


static func neighbor_mask(occupied: Dictionary, cell: Vector2i) -> int:
	var mask := 0
	for index in range(OFFSETS.size()):
		var neighbor: Vector2i = cell + OFFSETS[index]
		if occupied.has(PFBoard.cell_key(neighbor)):
			mask |= 1 << index
	return mask


static func stable_variant_index(cell: Vector2i, variant_count: int, seed: int = 0) -> int:
	if variant_count <= 1:
		return 0
	var hash_value := int(hash("%d,%d:%d" % [cell.x, cell.y, seed]))
	return posmod(hash_value, variant_count)


static func _valid_47_masks() -> Array:
	var masks := []
	for mask in range(256):
		if normalize_47(mask) == mask:
			masks.append(mask)
	return masks
