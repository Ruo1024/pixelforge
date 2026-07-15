extends "res://addons/gut/test.gd"

const POLICY_PATH := "res://services/generation_model_policy.gd"


func test_new_generate_writes_descriptor_defaults() -> void:
	var policy: Script = load(POLICY_PATH)
	assert_not_null(policy)
	if policy == null:
		return
	var params: Dictionary = policy.default_params(ProviderService.get_model_descriptors())
	assert_eq(params["provider_id"], "openai_image")
	assert_eq(params["model_id"], "gpt-image-2")
	assert_eq(params["seed"], -1)
	assert_eq(params["extra"], {})
	assert_eq(params["resolution_preset"], "1080p")
	assert_eq(params["orientation"], "square")
	assert_eq(params["batch_size"], 4)


func test_model_switch_freezes_extra_seed_and_preserves_delivery_fields() -> void:
	var policy: Script = load(POLICY_PATH)
	assert_not_null(policy)
	if policy == null:
		return
	var current := {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"resolution_preset": "4K",
		"orientation": "landscape",
		"batch_size": 3,
		"seed": 17,
		"extra": {"quality": "high", "unknown": "must not survive"},
	}
	var changed: Dictionary = (
		policy
		. transition(
			current,
			"openai_image",
			"gpt-image-2",
			ProviderService.get_model_descriptors(),
		)
	)
	assert_true(changed["ok"])
	assert_eq(changed["params"]["extra"], {})
	assert_eq(changed["params"]["seed"], -1)
	for field in ["resolution_preset", "orientation", "batch_size"]:
		assert_eq(changed["params"][field], current[field], field)
	assert_eq(changed["undo_units"], 1)
