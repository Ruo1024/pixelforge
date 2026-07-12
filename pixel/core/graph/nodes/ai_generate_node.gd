class_name PFAiGenerateNode
extends PFNode

## Mock AI 生成节点。
## contract: 02-contracts/GRAPH-SCHEMA.md §5；M3 仅实现 provider_id=mock 的确定性占位图。

const MODEL_ID := "pixel_mock_v1"
const PROVIDER_MOCK := "mock"
const DEFAULT_BATCH_SIZE := 1
const DEFAULT_SEED := 1
const DEFAULT_SIZE := 32


func get_type() -> String:
	return "ai_generate"


func get_display_name() -> String:
	return "AI Generate"


func get_category() -> String:
	return "generate"


func get_input_ports() -> Array[Dictionary]:
	return [
		{"name": "style", "type": "style", "required": false},
		{"name": "text", "type": "text", "required": false},
		{"name": "items", "type": "text_list", "required": false},
		{"name": "spec", "type": "spec", "required": true},
		{"name": "image", "type": "image_list", "required": false},
	]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "images", "type": "image_list"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "provider_id",
			"label_key": "GRAPH_PARAM_PROVIDER",
			"kind": KIND_PROVIDER,
			"default": PROVIDER_MOCK,
		},
		{
			"key": "model_id",
			"label_key": "GRAPH_PARAM_MODEL",
			"kind": KIND_TEXT,
			"default": "",
		},
		{
			"key": "batch_size",
			"label_key": "GRAPH_PARAM_BATCH_SIZE",
			"kind": KIND_INT,
			"default": DEFAULT_BATCH_SIZE,
			"min": 1,
			"max": 16,
		},
		{
			"key": "seed",
			"label_key": "GRAPH_PARAM_SEED",
			"kind": KIND_SEED,
			"default": DEFAULT_SEED,
			"min": 0,
			"max": 2147483647,
		},
	]


func execute(inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	if String(params.get("provider_id", PROVIDER_MOCK)) != PROVIDER_MOCK:
		return {
			"__error":
			{
				"code": "unsupported_provider",
				"message": "M3 mock runner only supports provider_id=mock",
			},
		}

	var spec: Dictionary = inputs.get("spec", {})
	var width := maxi(1, int(spec.get("width", DEFAULT_SIZE)))
	var height := maxi(1, int(spec.get("height", DEFAULT_SIZE)))
	var batch_size := maxi(1, int(params.get("batch_size", spec.get("per_subject", 1))))
	var seed := int(params.get("seed", DEFAULT_SEED))
	var subjects := _subjects_from_inputs(inputs)
	var reference_hash := String(inputs.get("__reference_content_sha256", ""))
	var reference_asset_id := String(inputs.get("__reference_asset_id", ""))
	var reference_hashes := _string_array(inputs.get("__reference_content_sha256s", []))
	var reference_asset_ids := _string_array(inputs.get("__reference_asset_ids", []))
	if reference_hashes.is_empty() and not reference_hash.is_empty():
		reference_hashes.append(reference_hash)
	if reference_asset_ids.is_empty() and not reference_asset_id.is_empty():
		reference_asset_ids.append(reference_asset_id)
	var combined_reference_hash := ":".join(reference_hashes)
	var images := []
	var metadata := []

	for subject in subjects:
		for _index in range(batch_size):
			var item_seed := seed + images.size()
			images.append(
				_make_mock_image(String(subject), width, height, item_seed, combined_reference_hash)
			)
			(
				metadata
				. append(
					{
						"provider": PROVIDER_MOCK,
						"model": MODEL_ID,
						"prompt": String(subject),
						"seed": item_seed,
						"name": _asset_name(String(subject), item_seed),
						"reference_asset_id":
						reference_asset_id if not reference_asset_id.is_empty() else null,
						"reference_content_sha256":
						reference_hash if not reference_hash.is_empty() else null,
						"reference_asset_ids": reference_asset_ids.duplicate(),
						"reference_content_sha256s": reference_hashes.duplicate(),
					}
				)
			)

	return {"images": images, "metadata": metadata}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			result.append(String(item))
	return result


func _subjects_from_inputs(inputs: Dictionary) -> Array:
	var result := []
	if inputs.has("items"):
		for item in inputs["items"]:
			var text := String(item).strip_edges()
			if not text.is_empty():
				result.append(text)
	if result.is_empty() and inputs.has("text"):
		var prompt := String(inputs["text"]).strip_edges()
		if not prompt.is_empty():
			result.append(prompt)
	if result.is_empty():
		result.append("sprite")
	return result


func _make_mock_image(
	subject: String, width: int, height: int, seed: int, reference_hash: String = ""
) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var hash_subject := "%s:%s" % [subject, reference_hash]
	var primary := _color_from_seed(hash_subject, seed, 0)
	var secondary := _color_from_seed(hash_subject, seed, 83)
	var accent := _color_from_seed(hash_subject, seed, 191)
	var block := maxi(1, mini(width, height) / 4)

	for y in range(height):
		for x in range(width):
			var checker := (int(x / block) + int(y / block) + seed) % 2
			var color := primary if checker == 0 else secondary
			if x == y or x == width - y - 1:
				color = accent
			image.set_pixel(x, y, color)
	return image


func _color_from_seed(subject: String, seed: int, salt: int) -> Color:
	var value := _stable_hash("%s:%d:%d" % [subject, seed, salt])
	var red := 48 + value % 176
	var green := 48 + int(value / 17) % 176
	var blue := 48 + int(value / 29) % 176
	return Color8(red, green, blue, 255)


func _stable_hash(text: String) -> int:
	var value := 2166136261
	for index in range(text.length()):
		value = int((value ^ text.unicode_at(index)) * 16777619) & 0x7fffffff
	return value


func _asset_name(subject: String, seed: int) -> String:
	var normalized := subject.to_snake_case()
	if normalized.is_empty():
		normalized = "mock_sprite"
	return "%s_%d" % [normalized.left(32), seed]
