class_name PFTerrainGroup
extends RefCounted

## Role-to-asset mapping for 16/47 blob terrain groups.

var id := ""
var name := "Terrain"
var mode := 16
var roles := {}
var seed := 0


func get_assets_for_role(role: int) -> Array:
	return Array(roles.get(str(role), []))


func choose_asset(role: int, cell: Vector2i) -> Dictionary:
	var assets := get_assets_for_role(role)
	var fallback := false
	if assets.is_empty():
		var nearest := _nearest_available_role(role)
		assets = get_assets_for_role(nearest)
		fallback = true
	if assets.is_empty():
		return {"asset_id": "", "variant": 0, "fallback": true}
	var variant := PFTerrainBlob.stable_variant_index(cell, assets.size(), seed)
	return {"asset_id": String(assets[variant]), "variant": variant, "fallback": fallback}


func _nearest_available_role(role: int) -> int:
	var best_role := -1
	var best_distance := 100
	for key in roles.keys():
		var candidate := int(key)
		if Array(roles[key]).is_empty():
			continue
		var distance := _bit_count(candidate ^ role)
		if distance < best_distance:
			best_distance = distance
			best_role = candidate
	return best_role


func _bit_count(value: int) -> int:
	var count := 0
	var remaining := value
	while remaining != 0:
		count += remaining & 1
		remaining >>= 1
	return count
