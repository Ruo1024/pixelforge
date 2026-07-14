extends "res://addons/gut/test.gd"

const FileIOScript := preload("res://infra/file_io.gd")
const GraphContextScript := preload("res://core/graph/pf_graph_context.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")


func before_each() -> void:
	AssetLibrary.clear()


func test_reference_set_resolves_ordered_images_ids_and_content_hashes() -> void:
	var red_id := _register_image(Color.RED, "red")
	var blue_id := _register_image(Color.BLUE, "blue")
	var node := ReferenceSetNodeScript.new()
	var params := {"asset_ids": [blue_id, red_id], "future_field": {"keep": true}}
	var original := params.duplicate(true)

	var result: Dictionary = node.execute(
		{}, node.validate_params(params), GraphContextScript.new(AssetLibrary)
	)

	assert_eq(params, original)
	assert_eq(result["__reference_asset_ids"], [blue_id, red_id])
	assert_eq(result["assets"], [blue_id, red_id])
	assert_eq(result["__reference_images"].size(), 2)
	assert_eq(result["__reference_images"][0].get_pixel(0, 0), Color.BLUE)
	assert_eq(result["__reference_images"][1].get_pixel(0, 0), Color.RED)
	assert_eq(
		result["__reference_content_sha256s"],
		[
			GraphContextScript.image_content_sha256(result["__reference_images"][0]),
			GraphContextScript.image_content_sha256(result["__reference_images"][1]),
		]
	)


func test_reference_set_preserves_empty_missing_and_damaged_entries_on_error() -> void:
	var node := ReferenceSetNodeScript.new()
	var context := GraphContextScript.new(AssetLibrary)
	var empty_params := {"asset_ids": ["first", "", "last"]}
	var missing_params := {"asset_ids": ["not-registered", "later"]}

	var empty_result: Dictionary = node.execute({}, empty_params, context)
	var missing_result: Dictionary = node.execute({}, missing_params, context)

	assert_eq(empty_result["__error"]["code"], "asset_not_found")
	assert_eq(empty_result["__error"]["args"]["index"], 0)
	assert_eq(missing_result["__error"]["code"], "asset_not_found")
	assert_eq(missing_result["__error"]["args"]["asset_id"], "not-registered")
	assert_eq(empty_params["asset_ids"], ["first", "", "last"])
	assert_eq(missing_params["asset_ids"], ["not-registered", "later"])

	var broken_meta := {"id": "broken", "name": "broken", "provenance": {}}
	assert_eq(
		(
			AssetLibrary
			. load_from_zip_files(
				{
					"assets/broken.meta.json": FileIOScript.json_to_bytes(broken_meta),
					"assets/broken.png": PackedByteArray([1, 2, 3, 4]),
				}
			)
		),
		OK
	)
	var damaged_params := {"asset_ids": ["broken", "later"]}
	var damaged_result: Dictionary = node.execute({}, damaged_params, context)
	assert_eq(damaged_result["__error"]["code"], "asset_decode_failed")
	assert_eq(damaged_result["__error"]["args"]["index"], 0)
	assert_eq(damaged_result["__error"]["args"]["asset_id"], "broken")
	assert_eq(damaged_params["asset_ids"], ["broken", "later"])


func test_reference_set_empty_slot_reports_its_original_index_and_value() -> void:
	var valid_id := _register_image(Color.WHITE, "valid")
	var params := {"asset_ids": [valid_id, "  ", "later"]}
	var no_references: Dictionary = ReferenceSetNodeScript.new().execute(
		{}, {"asset_ids": []}, GraphContextScript.new(AssetLibrary)
	)
	var result: Dictionary = ReferenceSetNodeScript.new().execute(
		{}, params, GraphContextScript.new(AssetLibrary)
	)

	assert_eq(no_references["__error"]["code"], "missing_asset_reference")
	assert_eq(no_references["__error"]["args"]["index"], -1)
	assert_eq(result["__error"]["code"], "missing_asset_reference")
	assert_eq(result["__error"]["args"]["index"], 1)
	assert_eq(result["__error"]["args"]["asset_id"], "  ")
	assert_eq(params["asset_ids"], [valid_id, "  ", "later"])


func test_reference_set_is_registered_and_roundtrips_exact_v2_params() -> void:
	var source := {
		"graph_version": 2,
		"id": "reference_graph",
		"name": "Reference Graph",
		"nodes":
		[
			{
				"id": "references",
				"type": "reference_set",
				"params": {"asset_ids": ["b", "a"]},
			}
		],
		"edges": [],
	}
	var parsed := GraphScript.parse_v2(source, NodeRegistryScript.new())
	assert_true(parsed["ok"])
	var graph: PFGraph = parsed["graph"]

	assert_false(graph.get_node("references").is_ghost())
	assert_eq(
		graph.get_node("references").get_output_ports(), [{"name": "assets", "type": "asset_list"}]
	)
	assert_eq(graph.get_node_params("references")["asset_ids"], ["b", "a"])
	assert_eq(graph.to_json(), source)


func _register_image(color: Color, name: String) -> String:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return AssetLibrary.register_image(image, name)
