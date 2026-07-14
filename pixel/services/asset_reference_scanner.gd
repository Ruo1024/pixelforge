class_name PFAssetReferenceScanner
extends RefCounted

## Contract-listed project asset references. This scanner never guesses arbitrary strings.


static func scan(project: Variant, asset_library: Node) -> Dictionary:
	var references: Array[Dictionary] = []
	if project == null:
		return _result(references, asset_library)
	_scan_canvas(Dictionary(project.canvas), references)
	_scan_graphs(Dictionary(project.graphs), references)
	_scan_boards(Dictionary(project.boards), references)
	_scan_animations(Dictionary(project.animations), references)
	_scan_history(asset_library, references)
	return _result(references, asset_library)


static func _scan_canvas(canvas: Dictionary, references: Array[Dictionary]) -> void:
	for item_value in canvas.get("items", []):
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("id", "unknown"))
		var base := "canvas/items/%s" % item_id
		match String(item.get("type", "")):
			"sprite":
				_add(references, item.get("asset_id", ""), "%s/asset_id" % base, "live")


static func _scan_graphs(graphs: Dictionary, references: Array[Dictionary]) -> void:
	for graph_id_value in graphs.keys():
		var graph_id := String(graph_id_value)
		var graph: Dictionary = graphs[graph_id_value]
		for node_value in graph.get("nodes", []):
			if not (node_value is Dictionary):
				continue
			var node: Dictionary = node_value
			var base := "graphs/%s/nodes/%s/params" % [graph_id, String(node.get("id", "unknown"))]
			var params: Dictionary = node.get("params", {})
			match String(node.get("type", "")):
				"image_input":
					_add(references, params.get("asset_id", ""), "%s/asset_id" % base, "live")
				"reference_set":
					_scan_array_field(params, "asset_ids", base, "live", references)
				"batch":
					_scan_batch_fields(params, base, references)


static func _scan_batch_fields(
	data: Dictionary, base: String, references: Array[Dictionary]
) -> void:
	var slots: Variant = data.get("result_slots", [])
	if slots is Array:
		for index in range(slots.size()):
			var raw_slot: Variant = slots[index]
			if not (raw_slot is Dictionary):
				continue
			var slot: Dictionary = raw_slot
			var asset_id := String(slot.get("asset_id", ""))
			if asset_id.is_empty():
				continue
			var strength := (
				"live"
				if String(slot.get("status", "")) == "succeeded" and not bool(slot.get("detached", false))
				else "history"
			)
			_add(references, asset_id, "%s/result_slots/%d/asset_id" % [base, index], strength)
	var snapshots: Variant = data.get("input_snapshots", {})
	if snapshots is Dictionary:
		for snapshot_id_value in snapshots:
			var raw_snapshot: Variant = snapshots[snapshot_id_value]
			if not (raw_snapshot is Dictionary):
				continue
			var snapshot: Dictionary = raw_snapshot
			var snapshot_base := "%s/input_snapshots/%s" % [base, String(snapshot_id_value)]
			if String(snapshot.get("kind", "")) == "generation":
				_scan_array_field(
					snapshot, "reference_asset_ids", snapshot_base, "history", references
				)
			elif String(snapshot.get("kind", "")) == "cleanup":
				_add(
					references,
					snapshot.get("source_asset_id", ""),
					"%s/source_asset_id" % snapshot_base,
					"history"
				)


static func _scan_boards(boards: Dictionary, references: Array[Dictionary]) -> void:
	for board_id_value in boards.keys():
		var board_id := String(board_id_value)
		var board: Dictionary = boards[board_id_value]
		for layer_value in board.get("layers", []):
			if not (layer_value is Dictionary):
				continue
			var layer: Dictionary = layer_value
			var layer_id := String(layer.get("id", "unknown"))
			var base := "boards/%s/layers/%s" % [board_id, layer_id]
			for cell_key in Dictionary(layer.get("cells", {})).keys():
				var cell: Dictionary = Dictionary(layer.get("cells", {}))[cell_key]
				_add(
					references,
					cell.get("asset_id", ""),
					"%s/cells/%s/asset_id" % [base, cell_key],
					"live"
				)
			for item_value in layer.get("items", []):
				if item_value is Dictionary:
					var item: Dictionary = item_value
					_add(
						references,
						item.get("asset_id", ""),
						"%s/items/%s/asset_id" % [base, String(item.get("id", "unknown"))],
						"live"
					)


static func _scan_animations(animations: Dictionary, references: Array[Dictionary]) -> void:
	for animation_id_value in animations.keys():
		var animation_id := String(animation_id_value)
		var animation: Dictionary = animations[animation_id_value]
		for index in range(Array(animation.get("frames", [])).size()):
			_add(
				references,
				Array(animation.get("frames", []))[index],
				"animations/%s/frames/%d" % [animation_id, index],
				"live"
			)


static func _scan_history(asset_library: Node, references: Array[Dictionary]) -> void:
	if asset_library == null or not asset_library.has_method("get_all_meta"):
		return
	for owner_id_value in Dictionary(asset_library.get_all_meta()).keys():
		var owner_id := String(owner_id_value)
		var meta: Dictionary = asset_library.get_asset_meta(owner_id)
		var provenance: Dictionary = meta.get("provenance", {})
		var base := "assets/%s/meta/provenance" % owner_id
		_add(references, provenance.get("parent_asset", ""), "%s/parent_asset" % base, "history")
		var generation_snapshot: Dictionary = provenance.get("generation_snapshot", {})
		_scan_array_field(
			generation_snapshot,
			"reference_asset_ids",
			"%s/generation_snapshot" % base,
			"history",
			references
		)
		var cleanup: Dictionary = provenance.get("cleanup", {})
		_add(
			references, cleanup.get("source_asset", ""), "%s/cleanup/source_asset" % base, "history"
		)


static func _scan_array_field(
	data: Dictionary, key: String, base: String, strength: String, references: Array[Dictionary]
) -> void:
	var values: Variant = data.get(key, [])
	if not (values is Array or values is PackedStringArray):
		return
	for index in range(values.size()):
		_add(references, values[index], "%s/%s/%d" % [base, key, index], strength)


static func _add(
	references: Array[Dictionary], asset_id_value: Variant, path: String, strength: String
) -> void:
	if asset_id_value == null:
		return
	var asset_id := String(asset_id_value).strip_edges()
	if not asset_id.is_empty():
		references.append({"asset_id": asset_id, "path": path, "strength": strength})


static func _result(references: Array[Dictionary], asset_library: Node) -> Dictionary:
	var live_by_asset := {}
	var history_by_asset := {}
	var warnings: Array[Dictionary] = []
	for reference in references:
		var asset_id := String(reference["asset_id"])
		var target: Dictionary = (
			live_by_asset if reference["strength"] == "live" else history_by_asset
		)
		if not target.has(asset_id):
			target[asset_id] = []
		target[asset_id].append(reference.duplicate(true))
		var code := _warning_code(asset_library, asset_id)
		if not code.is_empty():
			(
				warnings
				. append(
					{
						"code": code,
						"path": reference["path"],
						"asset_id": asset_id,
						"strength": reference["strength"],
					}
				)
			)
	return {
		"references": references,
		"live_by_asset": live_by_asset,
		"history_by_asset": history_by_asset,
		"warnings": warnings,
	}


static func _warning_code(asset_library: Node, asset_id: String) -> String:
	if (
		asset_library == null
		or not asset_library.has_method("has_asset")
		or not asset_library.has_asset(asset_id)
	):
		return "asset_reference_not_found"
	if not asset_library.has_method("get_bitmap_status"):
		return ""
	match String(asset_library.get_bitmap_status(asset_id)):
		"missing":
			return "asset_bitmap_missing"
		"decode_failed":
			return "asset_decode_failed"
	return ""
