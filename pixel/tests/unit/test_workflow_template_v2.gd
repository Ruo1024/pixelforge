extends "res://addons/gut/test.gd"

const Service := preload("res://services/workflow_template_service.gd")
const PixelCleanupNode := preload("res://core/graph/nodes/pixel_cleanup_node.gd")

const EXPECTED_WHITELIST := {
	"text_prompt": ["text"],
	"object_list": ["rows"],
	"prompt_preset": ["preset"],
	"image_input": ["asset_id"],
	"reference_set": ["asset_ids"],
	"ai_generate":
	["provider_id", "model_id", "target_width", "target_height", "batch_size", "seed", "extra"],
	"pixel_cleanup": ["preset_id", "settings"],
	"batch": ["label"],
}


func test_exact_whitelist_and_empty_batch() -> void:
	assert_eq(Service.PARAM_WHITELIST, EXPECTED_WHITELIST)
	for retired in ["size_spec", "style_preset", "output", "plugin.custom"]:
		var template := Service.builtin_templates()[0].duplicate(true)
		template["nodes"][0]["type"] = retired
		assert_eq(Service.validate_template(template).get("code", ""), "unsupported_template_node")
	for legacy_param in [
		"asset_ids", "expected_count", "review_states", "focus_asset_id", "compare_asset_ids"
	]:
		var legacy_graph := _batch_graph()
		legacy_graph["nodes"][0]["params"][legacy_param] = "legacy"
		var rejected := Service.build_from_frame(
			"Legacy Output", legacy_graph, _batch_canvas(), "frame"
		)
		assert_false(rejected.get("ok", false), legacy_param)
		assert_eq(rejected.get("code", ""), "unknown_template_param")

	var result := Service.build_from_frame("Output shell", _batch_graph(), _batch_canvas(), "frame")
	assert_true(result.get("ok", false), JSON.stringify(result))
	if not result.get("ok", false):
		return
	var params: Dictionary = result["template"]["nodes"][0]["params"]
	assert_eq(
		params,
		{
			"label": "Preserved label",
			"role": "standalone",
			"source_node_id": "",
			"source_run_id": "",
			"input_snapshots": {},
			"request_records": [],
			"result_slots": [],
		}
	)
	for forbidden in [
		"asset_ids", "expected_count", "review_states", "focus_asset_id", "compare_asset_ids"
	]:
		assert_false(params.has(forbidden), forbidden)

	var unknown_top_level: Dictionary = result["template"].duplicate(true)
	unknown_top_level["future_value"] = 1
	assert_false(Service.validate_template(unknown_top_level).get("ok", false))


func test_palette_requirements_are_sorted_unique_and_required() -> void:
	var graph := _cleanup_graph()
	var result := Service.build_from_frame("Palette cleanup", graph, _cleanup_canvas(), "frame")
	assert_true(result.get("ok", false), JSON.stringify(result))
	if not result.get("ok", false):
		return
	var requirements: Array = result["template"].get("palette_requirements", [])
	assert_eq(requirements.size(), 2)
	if requirements.size() != 2:
		return
	assert_eq(requirements[0].get("palette_id", ""), "db16")
	assert_eq(requirements[1].get("palette_id", ""), "db32")
	for requirement in requirements:
		assert_true(_matches("^[0-9a-f]{64}$", String(requirement.get("content_sha256", ""))))
		assert_eq(_sorted_keys(requirement), ["content_sha256", "palette_id"])

	var empty_requirements := Service.build_from_frame(
		"Prompt only", _prompt_graph(), _prompt_canvas(), "frame"
	)
	assert_true(empty_requirements.get("ok", false), JSON.stringify(empty_requirements))
	assert_true(empty_requirements["template"].has("palette_requirements"))
	assert_eq(empty_requirements["template"]["palette_requirements"], [])

	graph["nodes"][0]["params"]["settings"]["quantize"]["palette_id"] = "does-not-exist"
	var missing := Service.build_from_frame("Missing palette", graph, _cleanup_canvas(), "frame")
	assert_false(missing.get("ok", false))
	assert_eq(missing.get("code", ""), "missing_template_palette")


func test_palette_hash_mismatch_rejects_insertion_atomically() -> void:
	var built := Service.build_from_frame(
		"Palette cleanup", _cleanup_graph(), _cleanup_canvas(), "frame"
	)
	assert_true(built.get("ok", false), JSON.stringify(built))
	var template: Dictionary = built["template"].duplicate(true)
	template["palette_requirements"][0]["content_sha256"] = "0".repeat(64)
	var graph := _prompt_graph()
	var canvas := _prompt_canvas()
	var graph_before := graph.duplicate(true)
	var canvas_before := canvas.duplicate(true)
	var result := Service.instantiate(template, graph, canvas, Vector2(500, 300))
	assert_false(result.get("ok", false))
	assert_eq(result.get("code", ""), "invalid_palette_requirements")
	assert_eq(graph, graph_before)
	assert_eq(canvas, canvas_before)


func test_extra_only_template_safe() -> void:
	var graph := _generate_graph()
	var params: Dictionary = graph["nodes"][1]["params"]
	params["extra"] = {
		"quality": "low",
		"private_debug": true,
		"provider_internal": "not template safe",
	}
	var result := Service.build_from_frame("Safe generate", graph, _generate_canvas(), "frame")
	assert_true(result.get("ok", false), JSON.stringify(result))
	if not result.get("ok", false):
		return
	var generate: Dictionary = _node(result["template"], "generate")
	assert_eq(generate["params"]["extra"], {"quality": "low"})
	assert_false(JSON.stringify(result["template"]).contains("private_debug"))
	assert_false(JSON.stringify(result["template"]).contains("provider_internal"))


func test_four_builtins_remap() -> void:
	var builtins := Service.builtin_templates()
	assert_eq(builtins.size(), 4)
	assert_eq(
		builtins.map(func(template: Dictionary) -> String: return String(template["id"])),
		[
			"builtin-basic-generation",
			"builtin-object-batch",
			"builtin-reference-continue",
			"builtin-generate-process"
		]
	)
	var expected_types := [
		["text_prompt", "ai_generate"],
		["object_list", "ai_generate"],
		["text_prompt", "image_input", "ai_generate"],
		["text_prompt", "ai_generate", "pixel_cleanup"],
	]
	for index in range(builtins.size()):
		var template: Dictionary = builtins[index]
		assert_true(Service.validate_template(template).get("ok", false), JSON.stringify(template))
		assert_eq(_node_types(template), expected_types[index])
		assert_eq(template.get("palette_requirements", null), [])
		assert_false(_node_types(template).has("batch"))
		var instance := Service.instantiate(
			template,
			{"graph_version": 2, "id": "graph-main", "name": "Main", "nodes": [], "edges": []},
			{"camera": {"center": [0, 0], "zoom": 1.0}, "items": []},
			Vector2(500, 300)
		)
		assert_true(instance.get("ok", false), JSON.stringify(instance))
		assert_eq(instance["node_id_map"].size(), template["nodes"].size())
		assert_eq(instance["graph"]["nodes"].size(), template["nodes"].size())
		for old_id in instance["node_id_map"]:
			assert_ne(String(instance["node_id_map"][old_id]), String(old_id))

	var cleanup_template: Dictionary = builtins[3]
	assert_false(_cleanup_connected(cleanup_template))


func _batch_graph() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Batch",
		"nodes":
		[
			{
				"id": "output",
				"type": "batch",
				"params":
				{
					"label": "Preserved label",
					"role": "current",
					"source_node_id": "generate",
					"source_run_id": "run-1",
					"input_snapshots": {"snapshot": {"kind": "generation"}},
					"request_records": [{"request_id": "request-1"}],
					"result_slots": [{"slot_id": "slot-1"}]
				}
			}
		],
		"edges": [],
	}


func _batch_canvas() -> Dictionary:
	return _canvas_for_nodes([{"id": "output", "position": [100, 100]}])


func _cleanup_graph() -> Dictionary:
	var settings_a: Dictionary = PixelCleanupNode.DEFAULT_SETTINGS.duplicate(true)
	settings_a["quantize"]["palette_id"] = "db32"
	var settings_b: Dictionary = PixelCleanupNode.DEFAULT_SETTINGS.duplicate(true)
	settings_b["quantize"]["palette_id"] = "db16"
	var settings_c: Dictionary = PixelCleanupNode.DEFAULT_SETTINGS.duplicate(true)
	settings_c["quantize"]["palette_id"] = "db32"
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Cleanup",
		"nodes":
		[
			{
				"id": "cleanup-a",
				"type": "pixel_cleanup",
				"params": {"preset_id": "", "settings": settings_a}
			},
			{
				"id": "cleanup-b",
				"type": "pixel_cleanup",
				"params": {"preset_id": "", "settings": settings_b}
			},
			{
				"id": "cleanup-c",
				"type": "pixel_cleanup",
				"params": {"preset_id": "", "settings": settings_c}
			},
		],
		"edges": [],
	}


func _cleanup_canvas() -> Dictionary:
	return _canvas_for_nodes(
		[
			{"id": "cleanup-a", "position": [100, 100]},
			{"id": "cleanup-b", "position": [440, 100]},
			{"id": "cleanup-c", "position": [780, 100]},
		]
	)


func _prompt_graph() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Prompt",
		"nodes": [{"id": "prompt", "type": "text_prompt", "params": {"text": "tree"}}],
		"edges": []
	}


func _prompt_canvas() -> Dictionary:
	return _canvas_for_nodes([{"id": "prompt", "position": [100, 100]}])


func _generate_graph() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Generate",
		"nodes":
		[
			{"id": "prompt", "type": "text_prompt", "params": {"text": "tree"}},
			{
				"id": "generate",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "openai_image",
					"model_id": "gpt-image-2",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 1,
					"seed": -1,
					"extra": {"quality": "low"}
				}
			},
		],
		"edges": [{"from": ["prompt", "prompt"], "to": ["generate", "prompt"]}],
	}


func _generate_canvas() -> Dictionary:
	return _canvas_for_nodes(
		[
			{"id": "prompt", "position": [100, 100]},
			{"id": "generate", "position": [460, 100]},
		]
	)


func _canvas_for_nodes(nodes: Array) -> Dictionary:
	var items: Array = [
		{
			"id": "frame",
			"type": "frame",
			"graph_id": "graph-main",
			"title": "Stage",
			"position": [80, 80],
			"size": [1200, 700],
			"z_index": -1
		}
	]
	for node in nodes:
		items.append(
			{
				"id": "item-%s" % node["id"],
				"type": "node",
				"graph_id": "graph-main",
				"node_id": node["id"],
				"position": node["position"],
				"z_index": items.size(),
				"frame_id": "frame"
			}
		)
	return {"camera": {"center": [0, 0], "zoom": 1.0}, "items": items}


func _node(template: Dictionary, id: String) -> Dictionary:
	for raw_node in template.get("nodes", []):
		if raw_node is Dictionary and String(raw_node.get("id", "")) == id:
			return raw_node
	return {}


func _node_types(template: Dictionary) -> Array:
	return template.get("nodes", []).map(
		func(node: Dictionary) -> String: return String(node.get("type", ""))
	)


func _cleanup_connected(template: Dictionary) -> bool:
	for edge in template.get("edges", []):
		if String(edge["from"][0]) == "cleanup" or String(edge["to"][0]) == "cleanup":
			return true
	return false


func _sorted_keys(value: Dictionary) -> Array:
	var keys := value.keys()
	keys.sort()
	return keys


func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null
