class_name PFResultBranchBuilder
extends RefCounted

## Builds graph-local input branches from results without mutating the source branch.

const IdUtil := preload("res://core/util/id_util.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")
const PromptPresetNodeScript := preload("res://core/graph/nodes/prompt_preset_node.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const DeliveryPolicy := preload("res://services/generation_delivery_policy.gd")


static func build(
	graph: PFGraph, action_id: String, asset_ids: Array, snapshot: Dictionary, anchor: Vector2
) -> Dictionary:
	var references := _normalized_asset_ids(asset_ids)
	if graph == null or references.is_empty():
		return {"ok": false, "error": "missing_result_asset"}
	if action_id == "as_reference":
		return _build_reference_only(graph, references, anchor)
	if action_id != "continue_branch":
		return {"ok": false, "error": "unsupported_result_action"}
	return _build_continue_branch(graph, references, snapshot, anchor)


static func _build_reference_only(
	graph: PFGraph, asset_ids: Array[String], anchor: Vector2
) -> Dictionary:
	var reference := _add_reference_node(graph, asset_ids, anchor)
	return {
		"ok": not reference.is_empty(),
		"created_node_ids": [reference] if not reference.is_empty() else [],
		"focus_node_id": reference,
		"positions_by_node":
		{reference: _position_array(anchor)} if not reference.is_empty() else {},
	}


static func _build_continue_branch(
	graph: PFGraph, asset_ids: Array[String], snapshot: Dictionary, anchor: Vector2
) -> Dictionary:
	var reference_id := _add_reference_node(graph, asset_ids, anchor + Vector2(0, 210))
	var prompt_id := _add_node(
		graph,
		TextPromptNodeScript.new(),
		"prompt",
		{"text": String(snapshot.get("prompt", ""))},
		anchor
	)
	var prompt_preset := PromptPresetNodeScript.DEFAULT_PRESET.duplicate(true)
	prompt_preset["id"] = String(snapshot.get("prompt_preset_id", prompt_preset["id"]))
	prompt_preset["prefix"] = String(snapshot.get("prompt_prefix", prompt_preset["prefix"]))
	var preset_id := _add_node(
		graph,
		PromptPresetNodeScript.new(),
		"prompt_preset",
		{"preset": prompt_preset},
		anchor + Vector2(0, 420)
	)
	var generate_id := _add_node(
		graph,
		AiGenerateNodeScript.new(),
		"generate",
		_generation_params(snapshot),
		anchor + Vector2(580, 180)
	)
	var batch_id := _add_node(
		graph,
		BatchNodeScript.new(),
		"batch",
		{
			"label": "Batch",
			"source_node_id": generate_id,
			"source_run_id": "",
			"role": "standalone",
			"input_snapshots": {},
			"request_records": [],
			"result_slots": [],
		},
		anchor + Vector2(940, 180)
	)
	for edge in [
		[prompt_id, "prompt", generate_id, "prompt"],
		[preset_id, "prefix", generate_id, "prefix"],
		[reference_id, "assets", generate_id, "references"],
		[generate_id, "assets", batch_id, "in"],
	]:
		var result := graph.add_edge(edge[0], edge[1], edge[2], edge[3])
		if not bool(result.get("ok", false)):
			return {"ok": false, "error": String(result.get("reason", "invalid_edge"))}
	return {
		"ok": true,
		"created_node_ids": [reference_id, prompt_id, preset_id, generate_id, batch_id],
		"focus_node_id": generate_id,
		"batch_node_id": batch_id,
		"positions_by_node":
		{
			reference_id: _position_array(anchor + Vector2(0, 210)),
			prompt_id: _position_array(anchor),
			preset_id: _position_array(anchor + Vector2(0, 420)),
			generate_id: _position_array(anchor + Vector2(580, 180)),
			batch_id: _position_array(anchor + Vector2(940, 180)),
		},
	}


static func _generation_params(snapshot: Dictionary) -> Dictionary:
	var delivery := DeliveryPolicy.preset_for_delivery(
		int(snapshot.get("target_width", 0)), int(snapshot.get("target_height", 0))
	)
	return {
		"provider_id": String(snapshot.get("provider_id", "mock")),
		"model_id": String(snapshot.get("model_id", "")),
		"resolution_preset": String(delivery["resolution_preset"]),
		"orientation": String(delivery["orientation"]),
		"batch_size": 1,
		"seed": -1,
		"extra": {},
	}


static func _add_reference_node(
	graph: PFGraph, asset_ids: Array[String], position: Vector2
) -> String:
	if asset_ids.size() == 1:
		return _add_node(
			graph, ImageInputNodeScript.new(), "reference", {"asset_id": asset_ids[0]}, position
		)
	return _add_node(
		graph, ReferenceSetNodeScript.new(), "references", {"asset_ids": asset_ids}, position
	)


static func _add_node(
	graph: PFGraph, node: PFNode, prefix: String, params: Dictionary, position: Vector2
) -> String:
	var node_id := "%s_%s" % [prefix, IdUtil.uuid_v4().left(8)]
	return graph.add_node(node, node_id, params, position)


static func _normalized_asset_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_id in value:
		var asset_id := String(raw_id)
		if not asset_id.is_empty() and not result.has(asset_id):
			result.append(asset_id)
	return result


static func _position_array(value: Vector2) -> Array[int]:
	return [int(round(value.x)), int(round(value.y))]
