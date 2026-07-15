extends "res://addons/gut/test.gd"

const Clipboard := preload("res://core/graph/canvas_graph_clipboard.gd")


class SequenceIds:
	extends RefCounted

	var values: Array[String]

	func _init(source: Array[String]) -> void:
		values = source.duplicate()

	func next() -> String:
		return values.pop_front()


func test_origin_project_identity_gate() -> void:
	var payload := Clipboard.capture(_graph(), _items(), _selected_ids(), "project-a")
	assert_true(payload.get("ok", false), JSON.stringify(payload))
	assert_eq(payload["version"], 2)
	assert_eq(payload["origin_project_id"], "project-a")
	assert_eq(
		Clipboard.capture(_graph(), _items(), _selected_ids())["error"]["code"],
		"missing_origin_project_id"
	)
	assert_eq(
		Clipboard.instantiate(payload, Vector2.ZERO, Callable(), "project-b")["error"]["code"],
		"clipboard_project_mismatch"
	)
	assert_eq(
		Clipboard.instantiate(payload, Vector2.ZERO, Callable(), "")["error"]["code"],
		"missing_origin_project_id"
	)
	var ids := SequenceIds.new(
		[
			"new-prompt",
			"new-generate",
			"new-cleanup",
			"new-item-prompt",
			"new-item-generate",
			"new-item-cleanup"
		]
	)
	var result := Clipboard.instantiate(
		payload, Vector2(900, 400), Callable(ids, "next"), "project-a"
	)
	assert_true(result.get("ok", false), JSON.stringify(result))


func test_config_only_node_payloads() -> void:
	var payload := Clipboard.capture(_graph(), _items(), _selected_ids(), "project-a")
	assert_true(payload.get("ok", false), JSON.stringify(payload))
	assert_eq(
		_node(payload, "prompt")["params"],
		{
			"preset":
			{
				"prompt_preset_version": 1,
				"id": "prompt-hibit",
				"name_key": "PROMPT_PRESET_HIBIT",
				"prefix": "pixel art,",
			}
		}
	)
	assert_eq(
		_node(payload, "generate")["params"],
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"resolution_preset": "1080p",
			"orientation": "square",
			"batch_size": 2,
			"seed": -1,
			"extra": {},
		}
	)
	assert_eq(
		_node(payload, "cleanup")["params"],
		{"preset_id": "cleanup-16bit-db32", "settings": _cleanup_settings()}
	)
	var text := JSON.stringify(payload)
	for forbidden in [
		"run_id",
		"source_run_id",
		"request_records",
		"result_slots",
		"target_size",
		"effective_target_size",
		"last_error",
	]:
		assert_false(text.contains(forbidden), "clipboard retained %s" % forbidden)


func test_forbids_task_request_progress_raw_headers_response() -> void:
	var graph := _graph()
	_node(graph, "generate")["params"]["credential_shadow"] = {
		"Authorization": "Bearer secret",
		"response_body": {"raw": "private"},
		"progress_detail": "uploading private prompt",
	}
	_node(graph, "cleanup")["params"]["settings"]["quantize"]["header_override"] = "secret"
	var payload := Clipboard.capture(graph, _items(), _selected_ids(), "project-a")
	assert_true(payload.get("ok", false), JSON.stringify(payload))
	var violations: Array[String] = []
	_collect_forbidden_paths(payload, "root", violations)
	assert_eq(violations, [])
	assert_false(JSON.stringify(payload).contains("Bearer secret"))
	assert_false(JSON.stringify(payload).contains("private"))


func test_capture_v2_layout_edges_and_safe_refs() -> void:
	var payload := Clipboard.capture(_graph(), _items(), _selected_ids(), "project-a")
	assert_true(payload.get("ok", false), JSON.stringify(payload))
	assert_eq(payload["anchor"], [100, 80])
	assert_eq(_item(payload, "item-prompt")["position"], [0, 40])
	assert_eq(_item(payload, "item-generate")["position"], [300, 0])
	assert_eq(_item(payload, "item-cleanup")["position"], [700, 240])
	assert_eq(payload["edges"], [{"from": ["prompt", "prefix"], "to": ["generate", "prefix"]}])
	assert_eq(_node(payload, "prompt")["params"]["preset"]["id"], "prompt-hibit")
	for item in payload["items"]:
		assert_null(item["frame_id"])


func _graph() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"nodes":
		[
			{
				"id": "prompt",
				"type": "prompt_preset",
				"params":
				{
					"preset":
					{
						"prompt_preset_version": 1,
						"id": "prompt-hibit",
						"name_key": "PROMPT_PRESET_HIBIT",
						"prefix": "pixel art,",
					},
					"run_id": "run-prompt",
				},
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "openai_image",
					"model_id": "gpt-image-2",
					"resolution_preset": "1080p",
					"orientation": "square",
					"batch_size": 2,
					"seed": -1,
					"extra": {},
					"source_run_id": "run-generate",
					"request_records": [{"request_id": "request-private"}],
					"result_slots": [{"slot_id": "slot-private"}],
				},
				"last_error": {"raw_detail": "private"},
			},
			{
				"id": "cleanup",
				"type": "pixel_cleanup",
				"params":
				{
					"preset_id": "cleanup-16bit-db32",
					"settings": _cleanup_settings(),
					"target_size": [32, 32],
					"effective_target_size": [32, 32],
					"run_id": "run-cleanup",
				},
			},
			{"id": "outside", "type": "text_prompt", "params": {"text": "outside"}},
		],
		"edges":
		[
			{"from": ["prompt", "prefix"], "to": ["generate", "prefix"]},
			{"from": ["outside", "prompt"], "to": ["generate", "prompt"]},
		],
	}


func _items() -> Array:
	return [
		{
			"id": "item-prompt",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "prompt",
			"position": [100, 120],
			"frame_id": "old-frame"
		},
		{
			"id": "item-generate",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "generate",
			"position": [400, 80],
			"frame_id": "old-frame"
		},
		{
			"id": "item-cleanup",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "cleanup",
			"position": [800, 320],
			"frame_id": "old-frame"
		},
		{
			"id": "item-outside",
			"type": "node",
			"graph_id": "graph-main",
			"node_id": "outside",
			"position": [0, 0]
		},
	]


func _selected_ids() -> Array:
	return ["item-prompt", "item-generate", "item-cleanup"]


func _cleanup_settings() -> Dictionary:
	return {
		"detect_grid":
		{"enabled": true, "mode": "auto", "scale": 4.0, "offset": [0.0, 0.0], "base_size": 32},
		"resample": {"enabled": true, "mode": "mode", "scale": 4.0, "offset": [0.0, 0.0]},
		"quantize":
		{
			"enabled": true,
			"mode": "fixed_palette",
			"palette_id": "db32",
			"auto_k_strategy": "median_cut",
			"k": 16,
			"dither": "none",
			"dither_strength": 0.0,
			"dither_contrast": 0.0,
			"dither_chroma": 0.0,
			"dither_density": 1.0
		},
	}


func _node(container: Dictionary, id: String) -> Dictionary:
	for value in container.get("nodes", []):
		if value is Dictionary and String(value.get("id", "")) == id:
			return value
	return {}


func _item(container: Dictionary, id: String) -> Dictionary:
	for value in container.get("items", []):
		if value is Dictionary and String(value.get("id", "")) == id:
			return value
	return {}


func _collect_forbidden_paths(value: Variant, path: String, result: Array[String]) -> void:
	if value is Dictionary:
		for raw_key in value:
			var key := String(raw_key)
			var normalized := key.to_lower()
			for fragment in [
				"task",
				"request",
				"progress",
				"raw",
				"header",
				"response",
				"authorization",
				"last_error"
			]:
				if fragment in normalized:
					result.append("%s.%s" % [path, key])
			_collect_forbidden_paths(value[raw_key], "%s.%s" % [path, key], result)
	elif value is Array:
		for index in range(value.size()):
			_collect_forbidden_paths(value[index], "%s[%d]" % [path, index], result)
