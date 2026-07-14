class_name PFGraphGenerationPlanBuilder
extends RefCounted

## Builds one validated generation plan from Graph inputs without writing product state.

const GenerationRequestPlannerScript := preload("res://services/generation_request_planner.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const IdUtil := preload("res://core/util/id_util.gd")


static func build(
	graph: PFGraph,
	generate_node_id: String,
	provider_id: String,
	descriptors: Array,
	asset_source: Variant,
	run_id: String = ""
) -> Dictionary:
	if graph == null or graph.get_node(generate_node_id) == null:
		return _failure("missing_generation_source")
	var base := _request_input(
		graph, generate_node_id, provider_id, run_id if not run_id.is_empty() else IdUtil.uuid_v4()
	)
	var reference_result := _resolve_reference_inputs(base, graph, generate_node_id, asset_source)
	if not bool(reference_result.get("ok", false)):
		return reference_result
	var provenance_inputs := {
		"source_node_id": String(base.get("source_node_id", "")),
		"prompt_preset_id": String(base.get("prompt_preset_id", "")),
		"prompt_prefix": String(base.get("prefix", "")),
		"reference_asset_ids": Array(base.get("reference_asset_ids", [])).duplicate(),
		"reference_content_sha256s": Array(base.get("reference_content_sha256s", [])).duplicate(),
	}
	var planned: Dictionary = GenerationRequestPlannerScript.plan(base, descriptors)
	if not bool(planned.get("ok", false)):
		return {
			"ok": false,
			"issue": Dictionary(planned.get("issue", {})).duplicate(true),
			"requests": [],
			"slots": [],
		}
	planned["result_count"] = int(planned["total_slots"])
	planned["provenance_inputs"] = provenance_inputs
	return planned


static func mock_descriptor() -> Dictionary:
	return {
		"provider_id": "mock",
		"model_id": AiGenerateNodeScript.MODEL_ID,
		"display_name": "Mock",
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"seed": true,
			"native_pixel": true,
			"max_batch": 999,
			"max_reference_images": 999,
			"target_size_constraints":
			{
				"min_width": 1,
				"max_width": 16384,
				"width_step": 1,
				"min_height": 1,
				"max_height": 16384,
				"height_step": 1,
				"allowed_sizes": [],
			},
			"provider_output_sizes": [],
		},
		"dynamic_params": [],
	}


static func _request_input(
	graph: PFGraph, generate_node_id: String, provider_id: String, run_id: String
) -> Dictionary:
	var generate_params := graph.get_node_params(generate_node_id)
	var model_id := String(generate_params.get("model_id", "")).strip_edges()
	if provider_id == "mock":
		model_id = AiGenerateNodeScript.MODEL_ID
	var input := {
		"run_id": run_id,
		"provider_id": provider_id,
		"model_id": model_id,
		"graph_id": graph.id,
		"source_node_id": generate_node_id,
		"prompt": "",
		"prefix": "",
		"prompt_preset_id": "",
		"rows": [],
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"ref_images": [],
		"target_width": int(generate_params.get("target_width", 32)),
		"target_height": int(generate_params.get("target_height", 32)),
		"batch_size": int(generate_params.get("batch_size", 1)),
		"seed": int(generate_params.get("seed", -1)),
		"extra": Dictionary(generate_params.get("extra", {})).duplicate(true),
	}
	if provider_id == "mock":
		input["extra"] = {}
	for node_id in _direct_source_node_ids(graph, generate_node_id):
		var node: PFNode = graph.get_node(node_id)
		if node == null:
			continue
		var params := graph.get_node_params(node_id)
		match node.get_type():
			"object_list":
				input["rows"] = Array(params.get("rows", [])).duplicate(true)
			"text_prompt":
				input["prompt"] = String(params.get("text", input["prompt"]))
			"prompt_preset":
				var preset: Dictionary = params.get("preset", {})
				input["prefix"] = String(preset.get("prefix", ""))
				input["prompt_preset_id"] = String(preset.get("id", ""))
	return input


static func _resolve_reference_inputs(
	request: Dictionary, graph: PFGraph, generate_node_id: String, asset_source: Variant
) -> Dictionary:
	var asset_ids: Array[String] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		if String(to_data[0]) != generate_node_id or String(to_data[1]) != "references":
			continue
		var source: PFNode = graph.get_node(String(from_data[0]))
		if source == null:
			continue
		var params := graph.get_node_params(String(from_data[0]))
		if source.get_type() == "image_input":
			asset_ids.append(String(params.get("asset_id", "")))
		elif source.get_type() == "reference_set":
			for raw_id in params.get("asset_ids", []):
				asset_ids.append(String(raw_id))
	if asset_ids.is_empty():
		return {"ok": true}
	var resolved: Dictionary = GenerationRequestPlannerScript.resolve_reference_assets(
		asset_ids, asset_source
	)
	if not bool(resolved.get("ok", false)):
		return {
			"ok": false,
			"issue": Dictionary(resolved.get("issue", {})).duplicate(true),
			"requests": [],
			"slots": [],
		}
	request["reference_asset_ids"] = resolved["reference_asset_ids"]
	request["reference_content_sha256s"] = resolved["reference_content_sha256s"]
	request["ref_images"] = resolved["ref_images"]
	return {"ok": true}


static func _direct_source_node_ids(graph: PFGraph, target_node_id: String) -> Array[String]:
	var result: Array[String] = []
	for edge in graph.edges:
		var from_data: Array = edge.get("from", ["", ""])
		var to_data: Array = edge.get("to", ["", ""])
		var source_id := String(from_data[0])
		if String(to_data[0]) == target_node_id and not result.has(source_id):
			result.append(source_id)
	return result


static func _failure(code: String) -> Dictionary:
	return {
		"ok": false,
		"issue": {"code": code, "field": "", "args": {}},
		"requests": [],
		"slots": [],
	}
