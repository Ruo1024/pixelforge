extends "res://addons/gut/test.gd"

const ClipboardScript := preload("res://core/graph/canvas_graph_clipboard.gd")


class SequenceIds:
	extends RefCounted

	var values: Array[String] = []

	func _init(source: Array[String]) -> void:
		values = source.duplicate()

	func next() -> String:
		return values.pop_front()


func test_capture_keeps_relative_layout_internal_edges_and_safe_asset_references() -> void:
	var graph := _graph_fixture()
	var canvas_items := _canvas_fixture()

	var payload: Dictionary = ClipboardScript.capture(
		graph, canvas_items, ["item_prompt", "item_generate", "item_reference", "sprite_ignored"]
	)

	assert_true(payload["ok"])
	assert_eq(payload["anchor"], [100, 80])
	assert_eq(payload["items"].size(), 3)
	assert_eq(_by_id(payload["items"], "item_prompt")["position"], [0, 40])
	assert_eq(_by_id(payload["items"], "item_generate")["position"], [240, 0])
	assert_eq(_by_id(payload["items"], "item_reference")["position"], [0, 220])
	assert_eq(payload["edges"], [{"from": ["prompt", "text"], "to": ["generate", "text"]}])
	assert_eq(_by_id(payload["nodes"], "reference")["params"]["asset_id"], "asset-safe")
	assert_eq(_by_id(payload["nodes"], "generate")["params"]["asset_ids"], ["a", "b"])
	assert_eq(_by_id(payload["nodes"], "generate")["custom"], "preserved")
	assert_false(_by_id(payload["nodes"], "generate").has("execution_status"))
	assert_false(_by_id(payload["nodes"], "generate")["params"].has("task_id"))
	assert_false(_by_id(payload["items"], "item_generate").has("progress"))
	assert_null(_by_id(payload["items"], "item_generate")["frame_id"])
	assert_eq(_by_id(payload["items"], "item_prompt")["display_title"], "Castle ideas")
	assert_eq(_by_id(payload["items"], "item_prompt")["size"], [420, 320])

	_by_id(payload["nodes"], "reference")["params"]["asset_id"] = "changed"
	assert_eq(_by_id(graph["nodes"], "reference")["params"]["asset_id"], "asset-safe")


func test_instantiate_remaps_ids_edges_and_places_selection_at_target() -> void:
	var payload: Dictionary = ClipboardScript.capture(
		_graph_fixture(), _canvas_fixture(), ["item_prompt", "item_generate", "item_reference"]
	)
	var ids := SequenceIds.new(
		[
			"node-prompt-new",
			"node-generate-new",
			"node-reference-new",
			"item-prompt-new",
			"item-generate-new",
			"item-reference-new"
		]
	)

	var result: Dictionary = ClipboardScript.instantiate(
		payload, Vector2(1000, 500), Callable(ids, "next")
	)

	assert_true(result["ok"])
	assert_eq(
		result["node_id_map"],
		{
			"prompt": "node-prompt-new",
			"generate": "node-generate-new",
			"reference": "node-reference-new",
		}
	)
	assert_eq(
		result["item_id_map"],
		{
			"item_prompt": "item-prompt-new",
			"item_generate": "item-generate-new",
			"item_reference": "item-reference-new",
		}
	)
	assert_eq(_by_id(result["items"], "item-prompt-new")["position"], [1000, 540])
	assert_eq(_by_id(result["items"], "item-generate-new")["position"], [1240, 500])
	assert_eq(_by_id(result["items"], "item-reference-new")["position"], [1000, 720])
	assert_eq(_by_id(result["nodes"], "node-generate-new")["position"], [1240, 500])
	assert_eq(
		result["edges"],
		[
			{
				"from": ["node-prompt-new", "text"],
				"to": ["node-generate-new", "text"],
			}
		]
	)
	assert_eq(_by_id(result["nodes"], "node-reference-new")["params"]["asset_id"], "asset-safe")
	assert_null(_by_id(result["items"], "item-generate-new")["frame_id"])
	assert_eq(_by_id(result["items"], "item-prompt-new")["display_title"], "Castle ideas")
	assert_eq(_by_id(result["items"], "item-prompt-new")["size"], [420, 320])


func test_capture_rejects_empty_or_mismatched_selection() -> void:
	var graph := _graph_fixture()
	var items := _canvas_fixture()

	assert_eq(
		ClipboardScript.capture(graph, items, ["missing"])["error"]["code"], "empty_selection"
	)
	items[0]["graph_id"] = "another_graph"
	assert_eq(
		ClipboardScript.capture(graph, items, ["item_prompt"])["error"]["code"], "empty_selection"
	)


func test_instantiate_does_not_mutate_reusable_payload() -> void:
	var payload: Dictionary = ClipboardScript.capture(
		_graph_fixture(), _canvas_fixture(), ["item_prompt", "item_generate"]
	)
	var original := payload.duplicate(true)
	var ids := SequenceIds.new(["n1", "n2", "i1", "i2"])

	var result: Dictionary = ClipboardScript.instantiate(
		payload, Vector2(10, 20), Callable(ids, "next")
	)

	assert_true(result["ok"])
	assert_eq(payload, original)


func _graph_fixture() -> Dictionary:
	return {
		"graph_version": 1,
		"id": "graph_main",
		"nodes":
		[
			{
				"id": "prompt",
				"type": "text_prompt",
				"position": [100, 120],
				"params": {"text": "castle"}
			},
			{
				"id": "generate",
				"type": "ai_generate",
				"position": [340, 80],
				"params": {"provider_id": "mock", "asset_ids": ["a", "b"], "task_id": "live-task"},
				"execution_status": "running",
				"custom": "preserved",
			},
			{
				"id": "reference",
				"type": "image_input",
				"position": [100, 300],
				"params": {"asset_id": "asset-safe"},
			},
			{"id": "external", "type": "size_spec", "position": [600, 80], "params": {}},
		],
		"edges":
		[
			{"from": ["prompt", "text"], "to": ["generate", "text"]},
			{"from": ["external", "spec"], "to": ["generate", "spec"]},
			{"from": ["generate", "images"], "to": ["external", "in"]},
		],
	}


func _canvas_fixture() -> Array:
	return [
		{
			"id": "item_prompt",
			"type": "node",
			"graph_id": "graph_main",
			"node_id": "prompt",
			"position": [100, 120],
			"z_index": 0,
			"display_title": "Castle ideas",
			"size": [420, 320],
		},
		{
			"id": "item_generate",
			"type": "node",
			"graph_id": "graph_main",
			"node_id": "generate",
			"position": [340, 80],
			"z_index": 0,
			"frame_id": "frame-old",
			"progress": 0.7,
		},
		{
			"id": "item_reference",
			"type": "node",
			"graph_id": "graph_main",
			"node_id": "reference",
			"position": [100, 300],
			"z_index": 0,
		},
		{
			"id": "sprite_ignored",
			"type": "sprite",
			"asset_id": "asset-sprite",
			"position": [20, 20],
		},
	]


func _by_id(values: Array, expected_id: String) -> Dictionary:
	for value in values:
		if value is Dictionary and String(value.get("id", "")) == expected_id:
			return value
	return {}
