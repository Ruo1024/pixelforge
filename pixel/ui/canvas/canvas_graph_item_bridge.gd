class_name PFCanvasGraphItemBridge
extends RefCounted

## Graph 节点引用与画布卡片之间的桥接 helper。
## contract: 02-contracts/PROJECT-FORMAT.md §4；canvas 只存 node 引用，batch 队列回写 graph params。

const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")


static func is_graph_batch_node_data(item_data: Dictionary) -> bool:
	if String(item_data.get("type", "")) != "node":
		return false
	var graph_id := String(item_data.get("graph_id", ""))
	var node_id := String(item_data.get("node_id", ""))
	if graph_id.is_empty() or node_id.is_empty():
		return false

	var graph_data := ProjectService.get_graph_data(graph_id)
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			continue
		var node_data: Dictionary = raw_node
		if String(node_data.get("id", "")) == node_id:
			return String(node_data.get("type", "")) == "batch"
	return false


static func apply_batch_asset_ids(item: Node, asset_ids: Array, asset_library: Node) -> void:
	for asset_id in item.asset_ids:
		asset_library.release_ref(asset_id)
	item.set_asset_ids(asset_ids)
	for asset_id in item.asset_ids:
		asset_library.add_ref(asset_id)


static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
		return

	var graph_data := ProjectService.get_graph_data(item.graph_id)
	if graph_data.is_empty():
		return

	var nodes := []
	var changed := false
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			nodes.append(raw_node)
			continue
		var node_data: Dictionary = raw_node
		if (
			String(node_data.get("id", "")) == item.node_id
			and String(node_data.get("type", "")) == "batch"
		):
			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
			params["asset_ids"] = _string_array(asset_ids)
			params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
			params["review_filter"] = _review_filter(params.get("review_filter", "all"))
			params["focus_asset_id"] = _focus_asset_id(params.get("focus_asset_id", ""), asset_ids)
			node_data["params"] = params
			changed = true
		nodes.append(node_data)

	if changed:
		graph_data["nodes"] = nodes
		ProjectService.set_graph_data(item.graph_id, graph_data, true)


static func sync_batch_node_review_states(item: Node, review_states: Dictionary) -> void:
	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
		return

	var graph_data := ProjectService.get_graph_data(item.graph_id)
	if graph_data.is_empty():
		return

	var nodes := []
	var changed := false
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			nodes.append(raw_node)
			continue
		var node_data: Dictionary = raw_node
		if (
			String(node_data.get("id", "")) == item.node_id
			and String(node_data.get("type", "")) == "batch"
		):
			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
			params["review_states"] = _review_state_map(review_states, params.get("asset_ids", []))
			node_data["params"] = params
			changed = true
		nodes.append(node_data)

	if changed:
		graph_data["nodes"] = nodes
		ProjectService.set_graph_data(item.graph_id, graph_data, true)


static func sync_batch_node_review_filter(item: Node, review_filter: String) -> void:
	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
		return

	var graph_data := ProjectService.get_graph_data(item.graph_id)
	if graph_data.is_empty():
		return

	var nodes := []
	var changed := false
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			nodes.append(raw_node)
			continue
		var node_data: Dictionary = raw_node
		if (
			String(node_data.get("id", "")) == item.node_id
			and String(node_data.get("type", "")) == "batch"
		):
			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
			params["review_filter"] = _review_filter(review_filter)
			node_data["params"] = params
			changed = true
		nodes.append(node_data)

	if changed:
		graph_data["nodes"] = nodes
		ProjectService.set_graph_data(item.graph_id, graph_data, true)


static func sync_batch_node_focus_asset_id(item: Node, focus_asset_id: String) -> void:
	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
		return

	var graph_data := ProjectService.get_graph_data(item.graph_id)
	if graph_data.is_empty():
		return

	var nodes := []
	var changed := false
	for raw_node in graph_data.get("nodes", []):
		if not (raw_node is Dictionary):
			nodes.append(raw_node)
			continue
		var node_data: Dictionary = raw_node
		if (
			String(node_data.get("id", "")) == item.node_id
			and String(node_data.get("type", "")) == "batch"
		):
			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
			params["focus_asset_id"] = _focus_asset_id(focus_asset_id, params.get("asset_ids", []))
			node_data["params"] = params
			changed = true
		nodes.append(node_data)

	if changed:
		graph_data["nodes"] = nodes
		ProjectService.set_graph_data(item.graph_id, graph_data, true)


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in Array(value):
			var id := String(item)
			if not id.is_empty():
				result.append(id)
	return result


static func _review_state_map(value: Variant, valid_asset_ids: Variant) -> Dictionary:
	var result := {}
	if not (value is Dictionary):
		return result
	var valid_lookup := {}
	for asset_id in _string_array(valid_asset_ids):
		valid_lookup[asset_id] = true
	var raw_states: Dictionary = value
	for key in raw_states.keys():
		var asset_id := String(key)
		if not valid_lookup.has(asset_id):
			continue
		var review_state := String(raw_states[key])
		if review_state in ["keep", "reject", "flag"]:
			result[asset_id] = review_state
	return result


static func _review_filter(value: Variant) -> String:
	var filter := String(value)
	if (
		filter
		in [
			CanvasBatchCardScript.FILTER_ALL,
			CanvasBatchCardScript.FILTER_PENDING,
			CanvasBatchCardScript.REVIEW_KEEP,
			CanvasBatchCardScript.REVIEW_REJECT,
			CanvasBatchCardScript.REVIEW_FLAG,
		]
	):
		return filter
	return CanvasBatchCardScript.FILTER_ALL


static func _focus_asset_id(value: Variant, valid_asset_ids: Variant) -> String:
	var asset_id := String(value)
	return asset_id if _string_array(valid_asset_ids).has(asset_id) else ""
