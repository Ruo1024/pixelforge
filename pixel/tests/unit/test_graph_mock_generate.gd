extends "res://addons/gut/test.gd"

const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")


func test_object_list_outputs_only_valid_enabled_subject_rows() -> void:
	var node := ObjectListNodeScript.new()
	var result: Dictionary = (
		node
		. execute(
			{},
			(
				node
				. validate_params(
					{
						"rows":
						[
							{"id": "barrel", "text": " barrel ", "count": 2, "enabled": true},
							{"id": "fence", "text": "fence", "count": 1, "enabled": false},
						]
					}
				)
			),
			{}
		)
	)

	assert_eq(Array(result["subjects"]), [{"id": "barrel", "text": "barrel", "count": 2}])


func test_generate_target_and_subject_counts_are_unique_truth() -> void:
	var node := AiGenerateNodeScript.new()
	var params := node.validate_params(
		{"provider_id": "mock", "target_width": 16, "target_height": 24, "batch_size": 3}
	)
	var result: Dictionary = node.execute(
		{"subjects": [{"id": "barrel", "text": "barrel", "count": 2}]}, params, {}
	)
	assert_eq(result["assets"].size(), 2)
	assert_eq(result["assets"][0].get_size(), Vector2i(16, 24))
	assert_false(params.has("width"))
	assert_false(params.has("height"))
	assert_false(params.has("per_subject"))


func test_ai_generate_mock_is_deterministic_and_uses_incrementing_seeds() -> void:
	var node := AiGenerateNodeScript.new()
	var params := (
		node
		. validate_params(
			{
				"provider_id": "mock",
				"target_width": 8,
				"target_height": 8,
				"batch_size": 2,
				"seed": 100,
			}
		)
	)
	var inputs := {
		"subjects":
		[
			{"id": "barrel", "text": "barrel", "count": 2},
			{"id": "fence", "text": "fence", "count": 2},
		],
	}

	var first: Dictionary = node.execute(inputs, params, {})
	var second: Dictionary = node.execute(inputs, params, {})

	assert_eq(first["assets"].size(), 4)
	assert_eq(
		first["metadata"].map(func(entry: Dictionary) -> int: return int(entry["seed"])),
		[100, 101, 102, 103]
	)
	assert_eq(_sample_color(first["assets"][0]), _sample_color(second["assets"][0]))
	assert_ne(_sample_color(first["assets"][0]), _sample_color(first["assets"][1]))


func test_ai_generate_mock_rejects_non_mock_provider() -> void:
	var node := AiGenerateNodeScript.new()
	var result: Dictionary = (
		node
		. execute(
			{},
			{
				"provider_id": "real_api",
				"target_width": 8,
				"target_height": 8,
				"batch_size": 1,
			},
			{}
		)
	)

	assert_true(result.has("__error"))
	assert_eq(result["__error"]["code"], "unsupported_provider")


func _sample_color(image: Image) -> String:
	return image.get_pixel(0, 0).to_html(false)
