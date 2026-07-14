class_name PFCanvasGraphStatusPresenter
extends RefCounted

## Centralized localized status text for canvas graph interactions.

const Strings := preload("res://ui/shell/strings.gd")


static func text(event: Dictionary) -> String:
	var event_type := String(event.get("type", ""))
	match event_type:
		"connect_preview":
			if String(event.get("state", "none")) == "valid":
				return Strings.text("STATUS_GRAPH_CONNECT_PREVIEW_VALID")
			if String(event.get("state", "none")) == "invalid":
				return (
					Strings.text("STATUS_GRAPH_CONNECT_PREVIEW_INVALID_FORMAT")
					% String(event.get("reason", ""))
				)
		"connect_succeeded":
			return (
				Strings.text("STATUS_GRAPH_CONNECT_DONE")
				% _edge_status_parts(event.get("edge", {}))
			)
		"edge_selected":
			return (
				Strings.text("STATUS_GRAPH_EDGE_SELECTED")
				% _edge_status_parts(event.get("edge", {}))
			)
		"edge_deleted":
			return (
				Strings.text("STATUS_GRAPH_EDGE_DELETED")
				% _edge_status_parts(event.get("edge", {}))
			)
		"nodes_deleted":
			return (
				Strings.text("STATUS_GRAPH_NODES_DELETED")
				% [int(event.get("nodes", 0)), int(event.get("edges", 0))]
			)
		"nodes_grouped":
			return Strings.text("STATUS_FRAME_GROUPED_FORMAT") % int(event.get("count", 0))
		"nodes_ungrouped":
			return Strings.text("STATUS_FRAME_UNGROUPED")
		"group_failed":
			if String(event.get("reason", "")) == "cross_graph":
				return Strings.text("STATUS_FRAME_GROUP_CROSS_GRAPH")
			return Strings.text("STATUS_FRAME_GROUP_NEEDS_NODES")
	return ""


static func _edge_status_parts(edge: Variant) -> Array:
	if not (edge is Dictionary):
		return ["", "", "", ""]
	var edge_data: Dictionary = edge
	var from_data := _edge_endpoint(edge_data.get("from", []))
	var to_data := _edge_endpoint(edge_data.get("to", []))
	return [String(from_data[0]), String(from_data[1]), String(to_data[0]), String(to_data[1])]


static func _edge_endpoint(value: Variant) -> Array:
	var endpoint := ["", ""]
	if not (value is Array):
		return endpoint
	var source: Array = value
	if source.size() >= 1:
		endpoint[0] = String(source[0])
	if source.size() >= 2:
		endpoint[1] = String(source[1])
	return endpoint
