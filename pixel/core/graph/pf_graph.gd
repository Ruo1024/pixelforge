class_name PFGraph
extends RefCounted

## 节点图领域模型。
## contract: 02-contracts/GRAPH-SCHEMA.md §1/§2；保存逻辑节点、边、端口类型规则与无环约束。

const IdUtil := preload("res://core/util/id_util.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const PromptPresetRegistryScript := preload("res://services/prompt_preset_registry.gd")
const CleanupPresetRegistryScript := preload("res://services/cleanup_preset_registry.gd")
const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const GRAPH_VERSION := 2
const PARAM_KEYS := {
	"text_prompt": ["text"],
	"object_list": ["rows"],
	"prompt_preset": ["preset"],
	"image_input": ["asset_id"],
	"reference_set": ["asset_ids"],
	"ai_generate":
	["provider_id", "model_id", "target_width", "target_height", "batch_size", "seed", "extra"],
	"pixel_cleanup": ["preset_id", "settings"],
	"batch":
	[
		"label",
		"source_node_id",
		"source_run_id",
		"role",
		"input_snapshots",
		"request_records",
		"result_slots",
	],
}
const RETIRED_NODE_TYPES := ["size_spec", "style_preset"]

var graph_version := GRAPH_VERSION
var id := "graph_main"
var name := "Main Graph"
var nodes := {}
var edges: Array[Dictionary] = []

var _node_order := []
var _raw_graph_fields := {}


static func from_json(data: Dictionary, registry: Variant = null) -> PFGraph:
	var graph := PFGraph.new()
	var node_registry: Variant = registry
	if node_registry == null:
		node_registry = NodeRegistryScript.new()

	graph.graph_version = int(data.get("graph_version", GRAPH_VERSION))
	graph.id = String(data.get("id", "graph_main"))
	graph.name = String(data.get("name", "Main Graph"))
	graph._raw_graph_fields = data.duplicate(true)
	for known_key in ["graph_version", "id", "name", "nodes", "edges"]:
		graph._raw_graph_fields.erase(known_key)

	for raw_node in data.get("nodes", []):
		if raw_node is Dictionary:
			graph._load_node(raw_node, node_registry)

	for raw_edge in data.get("edges", []):
		if raw_edge is Dictionary:
			graph.edges.append(graph._normalize_edge(raw_edge))

	return graph


static func parse_v2(data: Dictionary, registry: Variant = null) -> Dictionary:
	var version: Variant = data.get("graph_version", null)
	if not (version is int) or version != GRAPH_VERSION:
		return {
			"ok": false,
			"error": {"code": "unsupported_graph_version", "args": {}},
		}
	var issue := _validate_v2_data(data)
	if not issue.is_empty():
		return {"ok": false, "error": issue}
	var graph := from_json(data, registry)
	var edge_errors := graph.validate_edges()
	if not edge_errors.is_empty():
		return {
			"ok": false,
			"error": {"code": "invalid_graph_edge", "args": {"index": edge_errors[0]["index"]}},
		}
	return {"ok": true, "graph": graph}


func add_node(
	node: PFNode, node_id: String = "", params: Dictionary = {}, _position: Vector2 = Vector2.ZERO
) -> String:
	var resolved_id := node_id
	if resolved_id.is_empty():
		resolved_id = IdUtil.uuid_v4()
	if nodes.has(resolved_id):
		return ""

	nodes[resolved_id] = {
		"node": node,
		"params": node.validate_params(params),
		"raw_fields": {},
	}
	_node_order.append(resolved_id)
	return resolved_id


func remove_node(node_id: String) -> bool:
	if not nodes.has(node_id):
		return false
	nodes.erase(node_id)
	_node_order.erase(node_id)
	var kept_edges: Array[Dictionary] = []
	for edge in edges:
		if _edge_from_node(edge) != node_id and _edge_to_node(edge) != node_id:
			kept_edges.append(edge)
	edges = kept_edges
	return true


func set_node_params(node_id: String, params: Dictionary) -> bool:
	if not nodes.has(node_id):
		return false
	var node: PFNode = nodes[node_id]["node"]
	nodes[node_id]["params"] = node.validate_params(params)
	return true


func get_node(node_id: String) -> PFNode:
	if not nodes.has(node_id):
		return null
	return nodes[node_id]["node"]


func get_node_params(node_id: String) -> Dictionary:
	if not nodes.has(node_id):
		return {}
	return Dictionary(nodes[node_id]["params"]).duplicate(true)


func add_edge(from_node: String, from_port: String, to_node: String, to_port: String) -> Dictionary:
	var edge := {"from": [from_node, from_port], "to": [to_node, to_port]}
	if _has_edge(edge):
		return {"ok": false, "reason": "Connection already exists", "auto_wrap": false}

	var result := can_connect(from_node, from_port, to_node, to_port)
	if not bool(result["ok"]):
		return result

	edges.append(edge)
	return result


func can_connect(
	from_node: String, from_port: String, to_node: String, to_port: String
) -> Dictionary:
	var result := _validate_connect_endpoints(from_node, to_node)
	if bool(result["ok"]):
		var source: PFNode = nodes[from_node]["node"]
		var target: PFNode = nodes[to_node]["node"]
		result = _validate_connect_ports(source, from_port, target, to_port)
	if bool(result["ok"]) and _input_port_has_source(to_node, to_port):
		result = _connect_result(false, "Input port already has a connection")
	if bool(result["ok"]) and _would_create_cycle(from_node, to_node):
		result = _connect_result(false, "Connection would create a cycle")
	return result


func validate_edges() -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var seen_edges := {}
	var seen_inputs := {}
	for index in range(edges.size()):
		var edge := _normalize_edge(edges[index])
		var edge_key := _edge_key(edge)
		if seen_edges.has(edge_key):
			errors.append(
				_edge_validation_error(index, edge, "duplicate_edge", "Connection already exists")
			)
			continue
		seen_edges[edge_key] = true

		var from_node := _edge_from_node(edge)
		var to_node := _edge_to_node(edge)
		if not nodes.has(from_node):
			errors.append(
				_edge_validation_error(
					index, edge, "missing_endpoint", "Source node does not exist"
				)
			)
			continue
		if not nodes.has(to_node):
			errors.append(
				_edge_validation_error(
					index, edge, "missing_endpoint", "Target node does not exist"
				)
			)
			continue

		var source: PFNode = nodes[from_node]["node"]
		var target: PFNode = nodes[to_node]["node"]
		if source.is_ghost() or target.is_ghost():
			continue

		var from_port := _edge_from_port(edge)
		var to_port := _edge_to_port(edge)
		var port_result := _validate_connect_ports(source, from_port, target, to_port)
		if not bool(port_result["ok"]):
			errors.append(
				_edge_validation_error(index, edge, "invalid_port", String(port_result["reason"]))
			)
			continue

		var input_key := _input_key(to_node, to_port)
		if seen_inputs.has(input_key):
			errors.append(
				_edge_validation_error(
					index, edge, "input_already_connected", "Input port already has a connection"
				)
			)
			continue
		seen_inputs[input_key] = true
	return errors


func validate_edges_for_node(node_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for error in validate_edges():
		var edge: Dictionary = error.get("edge", {})
		if _edge_from_node(edge) == node_id or _edge_to_node(edge) == node_id:
			result.append(error)
	return result


func to_json() -> Dictionary:
	var node_json := []
	for node_id in _node_order:
		if nodes.has(node_id):
			node_json.append(_node_to_json(String(node_id)))
	var result := _raw_graph_fields.duplicate(true)
	result["graph_version"] = graph_version
	result["id"] = id
	result["name"] = name
	result["nodes"] = node_json
	result["edges"] = edges.duplicate(true)
	return result


func _load_node(raw_node: Dictionary, registry: Variant) -> void:
	var type_name := String(raw_node.get("type", ""))
	var node: PFNode = registry.create(type_name)
	if node == null:
		node = PFNode.create_ghost(type_name, raw_node)

	var node_id := String(raw_node.get("id", IdUtil.uuid_v4()))
	var raw_fields := raw_node.duplicate(true)
	for known_key in ["id", "type", "params", "position", "display_title", "size", "collapsed"]:
		raw_fields.erase(known_key)
	nodes[node_id] = {
		"node": node,
		"params": node.validate_params(raw_node.get("params", {})),
		"raw_fields": raw_fields,
	}
	_node_order.append(node_id)


func _node_to_json(node_id: String) -> Dictionary:
	var entry: Dictionary = nodes[node_id]
	var node: PFNode = entry["node"]
	if node.is_ghost():
		var ghost_json := node.get_ghost_json()
		ghost_json["id"] = node_id
		ghost_json["type"] = node.get_type()
		ghost_json["params"] = entry["params"]
		return ghost_json
	var result: Dictionary = Dictionary(entry.get("raw_fields", {})).duplicate(true)
	result["id"] = node_id
	result["type"] = node.get_type()
	result["params"] = entry["params"]
	return result


static func _validate_v2_data(data: Dictionary) -> Dictionary:
	for key in data.keys():
		if String(key) not in ["graph_version", "id", "name", "nodes", "edges"]:
			return _load_error("unknown_graph_field", "graph.%s" % String(key))
	if String(data.get("id", "")).is_empty() or not (data.get("name", null) is String):
		return _load_error("invalid_graph_identity", "graph")
	var nodes_value: Variant = data.get("nodes", null)
	var edges_value: Variant = data.get("edges", null)
	if not (nodes_value is Array) or not (edges_value is Array):
		return _load_error("invalid_graph_shape", "graph")
	var node_ids := {}
	var current_outputs_by_source := {}
	var registry := NodeRegistryScript.new()
	for index in range(nodes_value.size()):
		var raw_node: Variant = nodes_value[index]
		if not (raw_node is Dictionary):
			return _load_error("invalid_graph_node", "nodes[%d]" % index)
		for key in raw_node.keys():
			if String(key) not in ["id", "type", "params"]:
				return _load_error("unknown_graph_node_field", "nodes[%d].%s" % [index, key])
		var node_id := String(raw_node.get("id", ""))
		var node_type := String(raw_node.get("type", ""))
		var params: Variant = raw_node.get("params", null)
		if (
			node_id.is_empty()
			or node_ids.has(node_id)
			or node_type.is_empty()
			or not (params is Dictionary)
		):
			return _load_error("invalid_graph_node", "nodes[%d]" % index)
		node_ids[node_id] = true
		if node_type in RETIRED_NODE_TYPES:
			return _load_error("retired_graph_node", "nodes[%d].type" % index)
		if PARAM_KEYS.has(node_type):
			for key in params.keys():
				if String(key) not in PARAM_KEYS[node_type]:
					return _load_error("unknown_graph_param", "nodes[%d].params.%s" % [index, key])
			if node_type not in ["batch", "object_list"]:
				var known_node: PFNode = registry.create(node_type)
				if (
					known_node == null
					or var_to_str(known_node.validate_params(params)) != var_to_str(params)
				):
					return _load_error("invalid_graph_param", "nodes[%d].params" % index)
		if node_type == "batch":
			var output_issue: Dictionary = BatchNodeScript.validate_v2_domain(params)
			if not bool(output_issue.get("ok", false)):
				return _load_error(
					"invalid_output_domain",
					"nodes[%d].%s" % [index, String(output_issue.get("path", "params"))]
				)
			if String(params.get("role", "")) == "current":
				var source_id := String(params.get("source_node_id", ""))
				if current_outputs_by_source.has(source_id):
					return _load_error(
						"duplicate_current_output", "nodes[%d].params.source_node_id" % index
					)
				current_outputs_by_source[source_id] = true
		if node_type == "object_list":
			var rows_issue: Dictionary = ObjectListNodeScript.validate_v2_rows(params)
			if not bool(rows_issue.get("ok", false)):
				return _load_error(
					"invalid_object_rows",
					"nodes[%d].%s" % [index, String(rows_issue.get("path", "params"))]
				)
		if node_type == "prompt_preset":
			var preset: Variant = params.get("preset", null)
			if (
				not (preset is Dictionary)
				or not bool(PromptPresetRegistryScript.validate_preset(preset).get("ok", false))
			):
				return _load_error("invalid_prompt_preset", "nodes[%d].params.preset" % index)
		if node_type == "pixel_cleanup":
			if (
				not (params.get("preset_id", null) is String)
				or String(params["preset_id"]).is_empty()
			):
				return _load_error("invalid_cleanup_preset", "nodes[%d].params.preset_id" % index)
			var settings: Variant = params.get("settings", null)
			if (
				not (settings is Dictionary)
				or not bool(
					CleanupPresetRegistryScript._validate_settings(settings).get("ok", false)
				)
			):
				return _load_error("invalid_cleanup_preset", "nodes[%d].params.settings" % index)
		if node_type == "ai_generate":
			var descriptor := ProviderService.get_model_descriptor(
				String(params.get("provider_id", "")), String(params.get("model_id", ""))
			)
			if (
				descriptor.is_empty()
				and String(params.get("provider_id", "")) == ProviderService.AUTOMATION_PROVIDER
				and (
					String(params.get("model_id", ""))
					== String(ProviderService.MOCK_MODEL_DESCRIPTOR["model_id"])
				)
			):
				descriptor = ProviderService.MOCK_MODEL_DESCRIPTOR
			if descriptor.is_empty():
				return _load_error("invalid_provider_model", "nodes[%d].params.model_id" % index)
			var extra_issue: Variant = ProviderContractV2._validate_dynamic_params(
				params.get("extra", {}), descriptor.get("dynamic_params", [])
			)
			if extra_issue != null:
				return _load_error("invalid_dynamic_param", "nodes[%d].params.extra" % index)
	for index in range(edges_value.size()):
		var raw_edge: Variant = edges_value[index]
		if not (raw_edge is Dictionary) or raw_edge.keys().size() != 2:
			return _load_error("invalid_graph_edge", "edges[%d]" % index)
		if not raw_edge.has("from") or not raw_edge.has("to"):
			return _load_error("invalid_graph_edge", "edges[%d]" % index)
		for endpoint_key in ["from", "to"]:
			var endpoint: Variant = raw_edge[endpoint_key]
			if not (endpoint is Array) or endpoint.size() != 2:
				return _load_error("invalid_graph_edge", "edges[%d].%s" % [index, endpoint_key])
	return {}


static func _load_error(code: String, path: String) -> Dictionary:
	return {"code": code, "args": {"path": path}}


func _normalize_edge(edge: Dictionary) -> Dictionary:
	var normalized := edge.duplicate(true)
	normalized["from"] = _normalize_edge_endpoint(edge.get("from", []))
	normalized["to"] = _normalize_edge_endpoint(edge.get("to", []))
	return normalized


func _normalize_edge_endpoint(value: Variant) -> Array:
	var endpoint := ["", ""]
	if not (value is Array):
		return endpoint
	var source: Array = value
	if source.size() >= 1:
		endpoint[0] = String(source[0])
	if source.size() >= 2:
		endpoint[1] = String(source[1])
	return endpoint


func _validate_connect_endpoints(from_node: String, to_node: String) -> Dictionary:
	if not nodes.has(from_node):
		return _connect_result(false, "Source node does not exist")
	if not nodes.has(to_node):
		return _connect_result(false, "Target node does not exist")
	if from_node == to_node:
		return _connect_result(false, "Connection would create a cycle")
	return _connect_result(true, "")


func _validate_connect_ports(
	source: PFNode, from_port: String, target: PFNode, to_port: String
) -> Dictionary:
	var source_port := source.get_output_port(from_port)
	var target_port := target.get_input_port(to_port)
	if source_port.is_empty():
		return _connect_result(false, "Source output port does not exist")
	if target_port.is_empty():
		return _connect_result(false, "Target input port does not exist")

	var source_type := String(source_port.get("type", ""))
	var target_type := String(target_port.get("type", ""))
	if source_type == target_type:
		return _connect_result(true, "")
	return _connect_result(false, "Cannot connect %s to %s" % [source_type, target_type])


func _would_create_cycle(from_node: String, to_node: String) -> bool:
	return _has_path(to_node, from_node)


func _has_path(start_node: String, target_node: String) -> bool:
	var visited := {}
	var stack := [start_node]
	while not stack.is_empty():
		var current := String(stack.pop_back())
		if current == target_node:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for edge in edges:
			if _edge_from_node(edge) == current:
				stack.append(_edge_to_node(edge))
	return false


func _has_edge(candidate: Dictionary) -> bool:
	for edge in edges:
		if edge == candidate:
			return true
	return false


func _input_port_has_source(node_id: String, port_name: String) -> bool:
	for edge in edges:
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[0]) == node_id and String(to_data[1]) == port_name:
			return true
	return false


func _edge_from_node(edge: Dictionary) -> String:
	var from_data: Array = edge.get("from", ["", ""])
	return String(from_data[0])


func _edge_to_node(edge: Dictionary) -> String:
	var to_data: Array = edge.get("to", ["", ""])
	return String(to_data[0])


func _edge_from_port(edge: Dictionary) -> String:
	var from_data: Array = edge.get("from", ["", ""])
	return String(from_data[1])


func _edge_to_port(edge: Dictionary) -> String:
	var to_data: Array = edge.get("to", ["", ""])
	return String(to_data[1])


func _edge_key(edge: Dictionary) -> String:
	return (
		"%s/%s>%s/%s"
		% [
			_edge_from_node(edge),
			_edge_from_port(edge),
			_edge_to_node(edge),
			_edge_to_port(edge),
		]
	)


func _input_key(node_id: String, port_name: String) -> String:
	return "%s/%s" % [node_id, port_name]


func _edge_validation_error(
	index: int, edge: Dictionary, code: String, message: String
) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"edge": edge.duplicate(true),
		"index": index,
	}


func _connect_result(ok: bool, reason: String, auto_wrap: bool = false) -> Dictionary:
	return {"ok": ok, "reason": reason, "auto_wrap": auto_wrap}
