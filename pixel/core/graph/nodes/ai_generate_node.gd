class_name PFAiGenerateNode
extends PFNode

## Mock AI 生成节点。
## contract: 02-contracts/GRAPH-SCHEMA.md §5；M3 仅实现 provider_id=mock 的确定性占位图。

const MODEL_ID := "pixel_mock_v1"
const PROVIDER_MOCK := "mock"
const DEFAULT_PROVIDER_ID := "openai_image"
const DEFAULT_MODEL_ID := "gpt-image-2"
const DEFAULT_BATCH_SIZE := 4
const DEFAULT_SEED := -1
const DEFAULT_RESOLUTION_PRESET := "1080p"
const DEFAULT_ORIENTATION := "square"
const DEFAULT_EXTRA := {}
const DeliveryPolicy := preload("res://services/generation_delivery_policy.gd")


func get_type() -> String:
	return "ai_generate"


func get_display_name() -> String:
	return "AI Generate"


func get_category() -> String:
	return "generate"


func get_input_ports() -> Array[Dictionary]:
	return [
		{"name": "prefix", "type": "prompt_prefix", "required": false},
		{"name": "prompt", "type": "text", "required": false},
		{"name": "subjects", "type": "subject_list", "required": false},
		{"name": "references", "type": "asset_list", "required": false},
	]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "assets", "type": "asset_list"}]


func get_param_schema() -> Array[Dictionary]:
	return [
		{
			"key": "provider_id",
			"label_key": "GRAPH_PARAM_PROVIDER",
			"kind": KIND_PROVIDER,
			"default": DEFAULT_PROVIDER_ID,
		},
		{
			"key": "model_id",
			"label_key": "GRAPH_PARAM_MODEL",
			"kind": KIND_TEXT,
			"default": DEFAULT_MODEL_ID,
		},
		{
			"key": "resolution_preset",
			"label_key": "GRAPH_PARAM_RESOLUTION_PRESET",
			"kind": KIND_ENUM,
			"default": DEFAULT_RESOLUTION_PRESET,
			"options": DeliveryPolicy.RESOLUTION_PRESETS,
		},
		{
			"key": "orientation",
			"label_key": "GRAPH_PARAM_ORIENTATION",
			"kind": KIND_ENUM,
			"default": DEFAULT_ORIENTATION,
			"options": DeliveryPolicy.ORIENTATIONS,
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
			"min": -1,
			"max": -1,
		},
	]


func validate_params(params: Dictionary) -> Dictionary:
	var validated := super(params)
	validated["extra"] = (
		Dictionary(params["extra"]).duplicate(true)
		if params.has("extra") and params["extra"] is Dictionary
		else DEFAULT_EXTRA.duplicate(true)
	)
	return validated


func execute(inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	if String(params.get("provider_id", DEFAULT_PROVIDER_ID)) != PROVIDER_MOCK:
		return {
			"__error":
			{
				"code": "unsupported_provider",
				"message": "M3 mock runner only supports provider_id=mock",
			},
		}

	var delivery := DeliveryPolicy.delivery_size(
		String(params.get("resolution_preset", DEFAULT_RESOLUTION_PRESET)),
		String(params.get("orientation", DEFAULT_ORIENTATION))
	)
	if delivery.is_empty():
		return {"__error": {"code": "invalid_delivery_size"}}
	var width := int(delivery[0])
	var height := int(delivery[1])
	var batch_size := maxi(1, int(params.get("batch_size", 1)))
	var seed := int(params.get("seed", DEFAULT_SEED))
	var subjects := _subject_rows_from_inputs(inputs, batch_size)
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
		var subject_text := String(subject.get("text", "sprite"))
		for _index in range(int(subject.get("count", batch_size))):
			var item_seed := seed + images.size()
			images.append(
				_make_mock_image(subject_text, width, height, item_seed, combined_reference_hash)
			)
			(
				metadata
				. append(
					{
						"actual_seed": item_seed,
						"name": _asset_name(subject_text, item_seed),
						"generation_snapshot":
						{
							"provider_id": PROVIDER_MOCK,
							"model_id": MODEL_ID,
							"mode": "img2img" if not reference_asset_ids.is_empty() else "txt2img",
							"prompt": subject_text,
							"prompt_preset_id": "",
							"prompt_prefix": "",
							"target_width": width,
							"target_height": height,
							"provider_output_size": [width, height],
							"batch_size": int(subject.get("count", batch_size)),
							"requested_seed": -1,
							"reference_asset_ids": reference_asset_ids.duplicate(),
							"reference_content_sha256s": reference_hashes.duplicate(),
							"source_row_id": String(subject.get("id", "")),
							"source_node_id": String(subject.get("source_node_id", "")),
							"run_id": "",
							"extra": Dictionary(params.get("extra", {})).duplicate(true),
						},
					}
				)
			)

	return {"assets": images, "metadata": metadata}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			result.append(String(item))
	return result


func _subject_rows_from_inputs(inputs: Dictionary, default_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var structured: Variant = inputs.get("subjects", null)
	if structured is Array:
		for row in structured:
			if row is Dictionary:
				(
					result
					. append(
						{
							"id": String(row.get("id", "")),
							"text": String(row.get("text", "")),
							"count": maxi(1, int(row.get("count", 1))),
							"source_node_id": String(row.get("source_node_id", "")),
						}
					)
				)
		return result
	if result.is_empty() and inputs.has("prompt"):
		var prompt := String(inputs["prompt"]).strip_edges()
		if not prompt.is_empty():
			result.append({"text": prompt, "count": default_count})
	if result.is_empty():
		result.append({"text": "sprite", "count": default_count})
	return result


func _make_mock_image(
	subject: String, width: int, height: int, seed: int, reference_hash: String = ""
) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var hash_subject := "%s:%s" % [subject, reference_hash]
	var primary := _color_from_seed(hash_subject, seed, 0)
	var secondary := _color_from_seed(hash_subject, seed, 83)
	var accent := _color_from_seed(hash_subject, seed, 191)
	image.fill(primary)
	var block_width := ceili(float(width) / 4.0)
	var block_height := ceili(float(height) / 4.0)
	for row in range(4):
		for column in range(4):
			if (column + row + seed) % 2 == 0:
				continue
			image.fill_rect(
				Rect2i(
					column * block_width,
					row * block_height,
					mini(block_width, width - column * block_width),
					mini(block_height, height - row * block_height)
				),
				secondary
			)
	var stripe := maxi(1, mini(width, height) / 64)
	image.fill_rect(Rect2i(0, 0, width, stripe), accent)
	image.fill_rect(Rect2i(0, height - stripe, width, stripe), accent)
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
