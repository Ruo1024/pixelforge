class_name PFWorkflowTemplateService
extends RefCounted

const FileIO := preload("res://infra/file_io.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const CardContract := preload("res://ui/canvas/canvas_card_contract.gd")

const SCHEMA := "pixelforge.workflow-template"
const VERSION := 1
const STORAGE_DIR := "user://workflow_templates"
const PARAM_WHITELIST := {
	"text_prompt": ["text"],
	"object_list": ["items", "rows"],
	"style_preset": ["preset_ref", "preset"],
	"image_input": ["asset_id"],
	"reference_set": ["asset_ids"],
	"size_spec": ["width", "height", "per_subject"],
	"ai_generate": ["provider_id", "model_id", "batch_size", "seed"],
	"batch": ["label"],
}
const TRANSIENT_PARAMS := {
	"batch":
	[
		"asset_ids",
		"review_state",
		"review_filter",
		"focus_asset_id",
		"compare_asset_ids",
		"run_state",
		"run_error",
		"expected_count",
	]
}
const SENSITIVE_FRAGMENTS := [
	"api_key", "authorization", "credential", "header", "password", "response", "secret", "token"
]


static func build_from_frame(
	name: String, graph_data: Dictionary, canvas_data: Dictionary, frame_id: String
) -> Dictionary:
	var frame := _canvas_item(canvas_data, frame_id)
	if frame.is_empty() or String(frame.get("type", "")) != "frame":
		return _failure("frame_not_found", frame_id)
	var graph_id := String(frame.get("graph_id", graph_data.get("id", "")))
	var member_items: Array[Dictionary] = []
	var node_ids := {}
	for raw_item in canvas_data.get("items", []):
		if not (raw_item is Dictionary):
			continue
		var item: Dictionary = raw_item
		var raw_frame_id: Variant = item.get("frame_id", null)
		var item_frame_id := "" if raw_frame_id == null else String(raw_frame_id)
		if item_frame_id != frame_id:
			continue
		if String(item.get("type", "")) != "node" or String(item.get("graph_id", "")) != graph_id:
			return _failure("unsupported_frame_member", String(item.get("id", "")))
		member_items.append(item)
		node_ids[String(item.get("node_id", ""))] = item
	if member_items.is_empty():
		return _failure("empty_frame", frame_id)

	var graph_nodes := _graph_nodes_by_id(graph_data)
	var template_nodes: Array[Dictionary] = []
	var frame_position := _vector2(frame.get("position", [0, 0]))
	for node_id in node_ids:
		if not graph_nodes.has(node_id):
			return _failure("node_not_found", node_id)
		var raw_node: Dictionary = graph_nodes[node_id]
		var sanitized := _sanitize_node(raw_node)
		if not bool(sanitized.get("ok", false)):
			return sanitized
		var item: Dictionary = node_ids[node_id]
		var relative := _vector2(item.get("position", [0, 0])) - frame_position
		var template_node := {
			"id": node_id,
			"type": String(raw_node.get("type", "")),
			"params": sanitized["params"],
			"position": _position(relative),
			"size":
			CardContract.size_array(
				CardContract.normalize_requested_size(
					String(raw_node.get("type", "unknown")), item.get("size", null)
				)
			),
			"collapsed": bool(item.get("collapsed", false)),
		}
		var title := CardContract.normalize_display_title(item.get("display_title", ""))
		if not title.is_empty():
			template_node["display_title"] = title
		template_nodes.append(template_node)
	var internal_edges: Array[Dictionary] = []
	var external_edge_count := 0
	for raw_edge in graph_data.get("edges", []):
		if not (raw_edge is Dictionary):
			continue
		var edge: Dictionary = raw_edge
		var from_id := _endpoint_node(edge.get("from", []))
		var to_id := _endpoint_node(edge.get("to", []))
		if node_ids.has(from_id) and node_ids.has(to_id):
			internal_edges.append(edge.duplicate(true))
		elif node_ids.has(from_id) or node_ids.has(to_id):
			external_edge_count += 1
	var template := {
		"schema": SCHEMA,
		"version": VERSION,
		"id": IdUtil.uuid_v4(),
		"name": name.strip_edges(),
		"description": "",
		"created_at": IdUtil.utc_now_iso(),
		"nodes": template_nodes,
		"edges": internal_edges,
		"frame":
		{
			"label": String(frame.get("title", name)),
			"position": [0, 0],
			"size": frame.get("size", [320, 240]),
			"color": String(frame.get("color", "4f6f8fff")),
		},
		"requirements": _requirements(template_nodes),
	}
	var validation := validate_template(template)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "template": template, "external_edge_count": external_edge_count}


static func save_template(template: Dictionary) -> Dictionary:
	var validation := validate_template(template)
	if not bool(validation.get("ok", false)):
		return validation
	var template_id := String(template.get("id", ""))
	var error := FileIO.atomic_write(_template_path(template_id), FileIO.json_to_bytes(template))
	return {"ok": error == OK, "error": error, "template": template.duplicate(true)}


static func rename_template(template_id: String, name: String) -> Dictionary:
	var loaded := load_template(template_id)
	if not bool(loaded.get("ok", false)):
		return loaded
	var template: Dictionary = loaded["template"]
	template["name"] = name.strip_edges()
	return save_template(template)


static func delete_template(template_id: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_template_path(template_id)))


static func load_template(template_id: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_template_path(template_id))) != OK:
		return _failure("template_corrupt", template_id)
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return _failure("template_corrupt", template_id)
	var validation := validate_template(parsed)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "template": Dictionary(parsed).duplicate(true)}


static func list_templates(query: String = "") -> Dictionary:
	var normalized := query.strip_edges().to_lower()
	var templates: Array[Dictionary] = builtin_templates()
	var warnings: Array[Dictionary] = []
	var directory := DirAccess.open(STORAGE_DIR)
	if directory != null:
		var files := directory.get_files()
		files.sort()
		for file_name in files:
			if not file_name.ends_with(".json"):
				continue
			var loaded := load_template(file_name.get_basename())
			if bool(loaded.get("ok", false)):
				templates.append(loaded["template"])
			else:
				warnings.append({"file": file_name, "code": loaded.get("code", "template_corrupt")})
	if not normalized.is_empty():
		templates = templates.filter(
			func(template: Dictionary) -> bool:
				return (
					normalized
					in (
						("%s %s" % [template.get("name", ""), template.get("description", "")])
						. to_lower()
					)
				)
		)
	return {"templates": templates, "warnings": warnings}


static func instantiate(
	template: Dictionary, graph_data: Dictionary, canvas_data: Dictionary, anchor: Vector2
) -> Dictionary:
	var validation := validate_template(template)
	if not bool(validation.get("ok", false)):
		return validation
	var graph_id := String(graph_data.get("id", "graph_main"))
	var frame_id := IdUtil.uuid_v4()
	var node_id_map := {}
	var item_ids: Array[String] = [frame_id]
	var graph_after := graph_data.duplicate(true)
	var canvas_after := canvas_data.duplicate(true)
	var graph_nodes: Array = graph_after.get("nodes", []).duplicate(true)
	var canvas_items: Array = canvas_after.get("items", []).duplicate(true)
	for raw_node in template.get("nodes", []):
		var node: Dictionary = raw_node
		var old_id := String(node.get("id", ""))
		var new_id := IdUtil.uuid_v4()
		node_id_map[old_id] = new_id
		var position := anchor + _vector2(node.get("position", [0, 0]))
		(
			graph_nodes
			. append(
				{
					"id": new_id,
					"type": String(node.get("type", "")),
					"position": _position(position),
					"params": Dictionary(node.get("params", {})).duplicate(true),
				}
			)
		)
		var item_id := IdUtil.uuid_v4()
		item_ids.append(item_id)
		var canvas_item := {
			"id": item_id,
			"type": "node",
			"graph_id": graph_id,
			"node_id": new_id,
			"position": _position(position),
			"z_index": canvas_items.size(),
			"size":
			CardContract.size_array(
				CardContract.normalize_requested_size(
					String(node.get("type", "unknown")), node.get("size", null)
				)
			),
			"collapsed": bool(node.get("collapsed", false)),
			"frame_id": frame_id,
		}
		if node.has("display_title"):
			canvas_item["display_title"] = node["display_title"]
		canvas_items.append(canvas_item)
	var graph_edges: Array = graph_after.get("edges", []).duplicate(true)
	for raw_edge in template.get("edges", []):
		var edge: Dictionary = raw_edge.duplicate(true)
		edge["from"] = _remap_endpoint(edge.get("from", []), node_id_map)
		edge["to"] = _remap_endpoint(edge.get("to", []), node_id_map)
		graph_edges.append(edge)
	var frame: Dictionary = template.get("frame", {})
	(
		canvas_items
		. append(
			{
				"id": frame_id,
				"type": "frame",
				"graph_id": graph_id,
				"title": String(frame.get("label", template.get("name", "Workflow"))),
				"color": String(frame.get("color", "4f6f8fff")),
				"position": _position(anchor),
				"size": frame.get("size", [320, 240]),
				"z_index": -1,
			}
		)
	)
	graph_after["nodes"] = graph_nodes
	graph_after["edges"] = graph_edges
	canvas_after["items"] = canvas_items
	return {
		"ok": true,
		"graph": graph_after,
		"canvas": canvas_after,
		"frame_id": frame_id,
		"item_ids": item_ids,
		"node_id_map": node_id_map,
	}


static func validate_template(template: Dictionary) -> Dictionary:
	if String(template.get("schema", "")) != SCHEMA or int(template.get("version", 0)) != VERSION:
		return _failure("unsupported_template_version", String(template.get("id", "")))
	if (
		String(template.get("id", "")).is_empty()
		or String(template.get("name", "")).strip_edges().is_empty()
	):
		return _failure("invalid_template_identity", String(template.get("id", "")))
	var sensitive_path := _first_unsafe_path(template)
	if not sensitive_path.is_empty():
		return _failure("unsafe_template_value", sensitive_path)
	var node_ids := {}
	for raw_node in template.get("nodes", []):
		if not (raw_node is Dictionary):
			return _failure("invalid_template_node", "nodes")
		var node: Dictionary = raw_node
		var node_id := String(node.get("id", ""))
		var node_type := String(node.get("type", ""))
		if node_id.is_empty() or node_ids.has(node_id) or not PARAM_WHITELIST.has(node_type):
			return _failure("unsupported_template_node", "%s:%s" % [node_id, node_type])
		node_ids[node_id] = true
		var sanitized := _sanitize_node(node)
		if not bool(sanitized.get("ok", false)):
			return sanitized
		if node.has("display_title"):
			if not (node["display_title"] is String):
				return _failure("invalid_template_node_title", node_id)
			var title := String(node["display_title"])
			if title.is_empty() or CardContract.normalize_display_title(title) != title:
				return _failure("invalid_template_node_title", node_id)
		if node.has("size"):
			if not _valid_template_size(node_type, node["size"]):
				return _failure("invalid_template_node_size", node_id)
	for raw_edge in template.get("edges", []):
		if not (raw_edge is Dictionary):
			return _failure("invalid_template_edge", "edges")
		var edge: Dictionary = raw_edge
		if (
			not node_ids.has(_endpoint_node(edge.get("from", [])))
			or not node_ids.has(_endpoint_node(edge.get("to", [])))
		):
			return _failure("external_template_edge", JSON.stringify(edge))
	var graph_data := {
		"graph_version": 1,
		"id": "template_validation",
		"name": "Template validation",
		"nodes": template.get("nodes", []),
		"edges": template.get("edges", []),
	}
	var edge_errors: Array[Dictionary] = GraphScript.from_json(graph_data).validate_edges()
	if not edge_errors.is_empty():
		return _failure("invalid_template_edge", JSON.stringify(edge_errors[0]))
	return {"ok": true}


static func builtin_templates() -> Array[Dictionary]:
	return [
		_builtin_text_batch(),
		_builtin_reference_continue(),
		_builtin_generate_process(),
	]


static func _builtin_text_batch() -> Dictionary:
	return _builtin(
		"builtin-text-batch",
		"Text batch generation",
		"Generate selected structured prompts into a result batch.",
		[
			_node("objects", "object_list", {"items": "small tower\nwooden crate"}, [40, 80]),
			_node("size", "size_spec", {"width": 64, "height": 64, "per_subject": 1}, [360, 80]),
			_node(
				"generate",
				"ai_generate",
				{"provider_id": "mock", "model_id": "mock-image-v1", "batch_size": 1, "seed": 1},
				[660, 80]
			),
			_node("batch", "batch", {"label": "Candidates"}, [1000, 80]),
		],
		[
			_edge("objects", "items", "generate", "items"),
			_edge("size", "spec", "generate", "spec"),
			_edge("generate", "images", "batch", "in"),
		]
	)


static func _builtin_reference_continue() -> Dictionary:
	return _builtin(
		"builtin-reference-continue",
		"Reference continuation",
		"Fill a reference slot and continue generation.",
		[
			_node("prompt", "text_prompt", {"text": "continue this character"}, [40, 80]),
			_node("reference", "image_input", {"asset_id": ""}, [40, 300]),
			_node("size", "size_spec", {"width": 64, "height": 64, "per_subject": 1}, [360, 80]),
			_node(
				"generate",
				"ai_generate",
				{"provider_id": "mock", "model_id": "mock-image-v1", "batch_size": 1, "seed": 2},
				[660, 80]
			),
			_node("batch", "batch", {"label": "Continuation"}, [1000, 80]),
		],
		[
			_edge("prompt", "text", "generate", "text"),
			_edge("reference", "image", "generate", "image"),
			_edge("size", "spec", "generate", "spec"),
			_edge("generate", "images", "batch", "in"),
		]
	)


static func _builtin_generate_process() -> Dictionary:
	var result := _builtin_text_batch()
	result["id"] = "builtin-generate-process"
	result["name"] = "Generate and process"
	result["description"] = "Generate a batch ready for cleanup and export."
	result["nodes"][3]["params"]["label"] = "Process and export"
	return result


static func _builtin(
	id: String, name: String, description: String, nodes: Array, edges: Array
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"version": VERSION,
		"id": id,
		"name": name,
		"description": description,
		"created_at": "builtin",
		"nodes": nodes,
		"edges": edges,
		"frame": {"label": name, "position": [0, 0], "size": [1320, 540], "color": "4f6f8fff"},
		"requirements": _requirements(nodes),
		"builtin": true,
	}


static func _node(id: String, type: String, params: Dictionary, position: Array) -> Dictionary:
	return {
		"id": id,
		"type": type,
		"params": params,
		"position": position,
		"size": CardContract.size_array(CardContract.default_size_for_type(type)),
		"collapsed": false,
	}


static func _valid_template_size(node_type: String, value: Variant) -> bool:
	if not (value is Array) or Array(value).size() != 2:
		return false
	var raw: Array = value
	if typeof(raw[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(raw[1]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var normalized := CardContract.normalize_requested_size(node_type, raw)
	return (
		is_equal_approx(float(raw[0]), float(normalized.x))
		and is_equal_approx(float(raw[1]), float(normalized.y))
	)


static func _edge(from_id: String, from_port: String, to_id: String, to_port: String) -> Dictionary:
	return {"from": [from_id, from_port], "to": [to_id, to_port]}


static func _sanitize_node(node: Dictionary) -> Dictionary:
	var unsafe_path := _first_unsafe_path(node)
	if not unsafe_path.is_empty():
		return _failure("unsafe_template_value", unsafe_path)
	var node_type := String(node.get("type", ""))
	if not PARAM_WHITELIST.has(node_type):
		return _failure("unsupported_template_node", node_type)
	var params: Dictionary = node.get("params", {})
	var sanitized := {}
	for raw_key in params:
		var key := String(raw_key)
		if key in PARAM_WHITELIST[node_type]:
			sanitized[key] = params[raw_key]
		elif key not in TRANSIENT_PARAMS.get(node_type, []):
			return _failure("unknown_template_param", "%s.%s" % [node_type, key])
	if node_type == "image_input":
		sanitized["asset_id"] = ""
	elif node_type == "reference_set":
		sanitized["asset_ids"] = []
	elif node_type == "batch":
		sanitized = {"label": String(params.get("label", "Results"))}
	elif node_type == "style_preset":
		var style_issue := _validate_style_params(sanitized)
		if not style_issue.is_empty():
			return _failure("invalid_style_preset", style_issue)
	return {"ok": true, "params": sanitized}


static func _validate_style_params(params: Dictionary) -> String:
	if String(params.get("preset_ref", "embedded")) != "embedded":
		return "preset_ref"
	var value: Variant = params.get("preset", null)
	if not (value is Dictionary):
		return "preset"
	var preset: Dictionary = value
	for key in ["style_version", "id", "name", "resolution_tier", "base_size", "palette"]:
		if not preset.has(key):
			return String(key)
	if int(preset.get("style_version", 0)) != 1 or int(preset.get("base_size", 0)) <= 0:
		return "version_or_size"
	var palette_value: Variant = preset.get("palette", null)
	if not (palette_value is Dictionary):
		return "palette"
	var palette: Dictionary = palette_value
	var colors_value: Variant = palette.get("colors", [])
	if not (colors_value is Array):
		return "palette.colors"
	if String(palette.get("ref", "")).is_empty() and colors_value.size() < 2:
		return "palette.ref_or_colors"
	if colors_value.size() > 256:
		return "palette.colors"
	for color in colors_value:
		var text := String(color).trim_prefix("#")
		if text.length() not in [6, 8] or not text.is_valid_hex_number():
			return "palette.colors"
	return ""


static func _requirements(nodes: Array) -> Dictionary:
	var model_ids: Array[String] = []
	var reference_slots := 0
	for raw_node in nodes:
		var node: Dictionary = raw_node
		var type := String(node.get("type", ""))
		if type == "ai_generate":
			var model_id := String(Dictionary(node.get("params", {})).get("model_id", ""))
			if not model_id.is_empty() and not model_ids.has(model_id):
				model_ids.append(model_id)
		elif type in ["image_input", "reference_set"]:
			reference_slots += 1
	return {"model_ids": model_ids, "reference_slots": reference_slots}


static func _first_unsafe_path(value: Variant, path: String = "root") -> String:
	if value is Dictionary:
		for raw_key in value:
			var key := String(raw_key)
			var normalized := key.to_lower()
			for fragment in SENSITIVE_FRAGMENTS:
				if fragment in normalized:
					return "%s.%s" % [path, key]
			var nested := _first_unsafe_path(value[raw_key], "%s.%s" % [path, key])
			if not nested.is_empty():
				return nested
	elif value is Array:
		for index in range(value.size()):
			var nested := _first_unsafe_path(value[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
	elif value is String:
		var text := String(value)
		if text.begins_with("/") or text.contains(":\\"):
			return path
	return ""


static func _canvas_item(canvas_data: Dictionary, item_id: String) -> Dictionary:
	for raw_item in canvas_data.get("items", []):
		if raw_item is Dictionary and String(raw_item.get("id", "")) == item_id:
			return Dictionary(raw_item).duplicate(true)
	return {}


static func _graph_nodes_by_id(graph_data: Dictionary) -> Dictionary:
	var result := {}
	for raw_node in graph_data.get("nodes", []):
		if raw_node is Dictionary:
			result[String(raw_node.get("id", ""))] = raw_node
	return result


static func _endpoint_node(value: Variant) -> String:
	return String(value[0]) if value is Array and value.size() >= 1 else ""


static func _remap_endpoint(value: Variant, id_map: Dictionary) -> Array:
	if not (value is Array) or value.size() < 2:
		return ["", ""]
	return [String(id_map.get(String(value[0]), "")), String(value[1])]


static func _vector2(value: Variant) -> Vector2:
	return (
		Vector2(float(value[0]), float(value[1]))
		if value is Array and value.size() >= 2
		else Vector2.ZERO
	)


static func _position(value: Vector2) -> Array:
	return [int(round(value.x)), int(round(value.y))]


static func _template_path(template_id: String) -> String:
	return "%s/%s.json" % [STORAGE_DIR, template_id]


static func _failure(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
