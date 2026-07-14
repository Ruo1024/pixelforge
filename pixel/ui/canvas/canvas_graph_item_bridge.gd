class_name PFCanvasGraphItemBridge
extends RefCounted

## Graph 节点引用与画布卡片之间的桥接 helper。
## contract: 02-contracts/PROJECT-FORMAT.md §4；canvas 只存 node 引用，batch 队列回写 graph params。

const GraphScript := preload("res://core/graph/pf_graph.gd")


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


static func graph_deletion_snapshots_for_canvas_snapshots(canvas_snapshots: Array) -> Dictionary:
	var graph_node_ids := _graph_node_ids_by_graph(canvas_snapshots)
	var result := {}
	for graph_id in graph_node_ids.keys():
		var before := ProjectService.get_graph_data(String(graph_id))
		if before.is_empty():
			continue
		var graph: PFGraph = GraphScript.from_json(before)
		var changed := false
		var before_edge_count := graph.edges.size()
		var removed_node_count := 0
		for node_id in graph_node_ids[graph_id]:
			var removed := graph.remove_node(String(node_id))
			if removed:
				removed_node_count += 1
			changed = removed or changed
		if changed:
			result[String(graph_id)] = {
				"before": before,
				"after": graph.to_json(),
				"removed_nodes": removed_node_count,
				"removed_edges": before_edge_count - graph.edges.size(),
			}
	return result


static func apply_graph_deletion_snapshots(
	graph_snapshots: Dictionary, version_key: String
) -> void:
	for graph_id in graph_snapshots.keys():
		var versions: Dictionary = graph_snapshots[graph_id]
		if not versions.has(version_key):
			continue
		ProjectService.set_graph_data(String(graph_id), Dictionary(versions[version_key]))


static func deletion_counts(graph_snapshots: Dictionary) -> Dictionary:
	var removed_nodes := 0
	var removed_edges := 0
	for graph_id in graph_snapshots.keys():
		var versions: Dictionary = graph_snapshots[graph_id]
		removed_nodes += int(versions.get("removed_nodes", 0))
		removed_edges += int(versions.get("removed_edges", 0))
	return {"nodes": removed_nodes, "edges": removed_edges}


static func _graph_node_ids_by_graph(canvas_snapshots: Array) -> Dictionary:
	var result := {}
	for raw_snapshot in canvas_snapshots:
		if not (raw_snapshot is Dictionary):
			continue
		var snapshot: Dictionary = raw_snapshot
		var data: Dictionary = snapshot.get("data", {})
		if String(data.get("type", "")) != "node":
			continue
		var graph_id := String(data.get("graph_id", ""))
		var node_id := String(data.get("node_id", ""))
		if graph_id.is_empty() or node_id.is_empty():
			continue
		if not result.has(graph_id):
			result[graph_id] = []
		result[graph_id].append(node_id)
	return result
