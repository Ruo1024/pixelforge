extends "res://addons/gut/test.gd"

const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")


func test_object_list_outputs_trimmed_text_list() -> void:
	var node := ObjectListNodeScript.new()
	var result: Dictionary = node.execute(
		{}, node.validate_params({"items": " barrel\n\n fence \n"}), {}
	)

	assert_eq(Array(result["items"]), ["barrel", "fence"])


func test_size_spec_outputs_dimensions_and_per_subject_count() -> void:
	var node := SizeSpecNodeScript.new()
	var result: Dictionary = node.execute(
		{}, node.validate_params({"width": 16, "height": 24, "per_subject": 3}), {}
	)

	assert_eq(result["spec"], {"width": 16, "height": 24, "per_subject": 3})


func test_ai_generate_mock_is_deterministic_and_uses_incrementing_seeds() -> void:
	var node := AiGenerateNodeScript.new()
	var params := node.validate_params({"provider_id": "mock", "batch_size": 2, "seed": 100})
	var inputs := {
		"items": PackedStringArray(["barrel", "fence"]),
		"spec": {"width": 8, "height": 8, "per_subject": 1},
	}

	var first: Dictionary = node.execute(inputs, params, {})
	var second: Dictionary = node.execute(inputs, params, {})

	assert_eq(first["images"].size(), 4)
	assert_eq(
		first["metadata"].map(func(entry: Dictionary) -> int: return int(entry["seed"])),
		[100, 101, 102, 103]
	)
	assert_eq(_sample_color(first["images"][0]), _sample_color(second["images"][0]))
	assert_ne(_sample_color(first["images"][0]), _sample_color(first["images"][1]))


func test_ai_generate_mock_rejects_non_mock_provider() -> void:
	var node := AiGenerateNodeScript.new()
	var result: Dictionary = node.execute(
		{"spec": {"width": 8, "height": 8}}, {"provider_id": "real_api"}, {}
	)

	assert_true(result.has("__error"))
	assert_eq(result["__error"]["code"], "unsupported_provider")


func _sample_color(image: Image) -> String:
	return image.get_pixel(0, 0).to_html(false)
