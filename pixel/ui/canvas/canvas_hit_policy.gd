class_name PFCanvasHitPolicy
extends RefCounted

## Canvas hit-test arbitration for item-level interactions.

const KIND_EMPTY := "empty"
const KIND_ITEM := "item"
const KIND_BATCH_THUMBNAIL := "batch_thumbnail"
const KIND_GRAPH_PORT := "graph_port"


static func hit_at_world(
	item_layer: Node,
	world_position: Vector2,
	batch_card_script: Script,
	sprite_script: Script,
	node_card_script: Script,
	frame_script: Script = null
) -> Dictionary:
	var children := _hit_order_children(
		item_layer, batch_card_script, sprite_script, node_card_script, frame_script
	)
	var frame_hit: Dictionary = {}
	for index in range(children.size() - 1, -1, -1):
		var item: Node = children[index]
		if not _is_canvas_item(
			item, batch_card_script, sprite_script, node_card_script, frame_script
		):
			continue
		if not item.visible:
			continue
		var port_hit := _graph_port_at_world(item, world_position)
		if not port_hit.is_empty():
			return _graph_port_hit(item, port_hit)
		if not item.contains_world_point(world_position):
			continue
		if frame_script != null and item.get_script() == frame_script:
			frame_hit = _hit(KIND_ITEM, item, -1)
			continue
		if item.get_script() == batch_card_script:
			var asset_index: int = item.asset_index_at_world(world_position)
			if asset_index >= 0:
				return _hit(KIND_BATCH_THUMBNAIL, item, asset_index)
		return _hit(KIND_ITEM, item, -1)
	return (
		frame_hit
		if not frame_hit.is_empty()
		else {"kind": KIND_EMPTY, "item": null, "item_id": "", "asset_index": -1}
	)


static func _hit_order_children(
	item_layer: Node,
	batch_card_script: Script,
	sprite_script: Script,
	node_card_script: Script,
	frame_script: Script
) -> Array:
	var regular := []
	var selected := []
	for child in item_layer.get_children():
		if _is_canvas_item(child, batch_card_script, sprite_script, node_card_script, frame_script):
			regular.append(child)
			continue
		if child.name != "SelectedItemLayer":
			continue
		for selected_child in child.get_children():
			if _is_canvas_item(
				selected_child, batch_card_script, sprite_script, node_card_script, frame_script
			):
				selected.append(selected_child)
	regular.sort_custom(func(a: Node, b: Node) -> bool: return a.z_index < b.z_index)
	regular.append_array(selected)
	return regular


static func _is_canvas_item(
	item: Variant,
	batch_card_script: Script,
	sprite_script: Script,
	node_card_script: Script,
	frame_script: Script
) -> bool:
	if not (item is Node):
		return false
	var script: Script = item.get_script()
	return (
		script == batch_card_script
		or script == sprite_script
		or script == node_card_script
		or (frame_script != null and script == frame_script)
	)


static func _graph_port_at_world(item: Node, world_position: Vector2) -> Dictionary:
	if not item.has_method("_graph_port_at_world"):
		return {}
	var raw_hit: Variant = item.call("_graph_port_at_world", world_position)
	if raw_hit is Dictionary:
		return raw_hit
	return {}


static func _hit(kind: String, item: Node, asset_index: int) -> Dictionary:
	return {"kind": kind, "item": item, "item_id": item.item_id, "asset_index": asset_index}


static func _graph_port_hit(item: Node, port_hit: Dictionary) -> Dictionary:
	var hit := _hit(KIND_GRAPH_PORT, item, -1)
	hit["port_name"] = String(port_hit.get("port_name", ""))
	hit["is_input"] = bool(port_hit.get("is_input", false))
	hit["port_index"] = int(port_hit.get("port_index", -1))
	return hit
