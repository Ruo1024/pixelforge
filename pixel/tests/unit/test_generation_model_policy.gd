extends "res://addons/gut/test.gd"

const POLICY_PATH := "res://services/generation_model_policy.gd"


func test_new_generate_writes_descriptor_defaults() -> void:
	var policy: Script = load(POLICY_PATH)
	assert_not_null(policy)
	if policy == null:
		return
	var params: Dictionary = policy.default_params(
		ProviderService.get_model_descriptors(), "retrodiffusion"
	)
	assert_eq(params["provider_id"], "retrodiffusion")
	assert_eq(params["model_id"], "rd_plus")
	assert_eq(params["seed"], -1)
	assert_eq(params["extra"], {"remove_bg": true, "strength": 0.8})
	assert_eq(params["target_width"], 32)
	assert_eq(params["target_height"], 32)
	assert_eq(params["batch_size"], 4)


func test_model_switch_rebuilds_extra_and_preserves_generation_fields() -> void:
	var policy: Script = load(POLICY_PATH)
	assert_not_null(policy)
	if policy == null:
		return
	var current := {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"target_width": 48,
		"target_height": 24,
		"batch_size": 3,
		"seed": 17,
		"extra": {"quality": "high", "unknown": "must not survive"},
	}
	var changed: Dictionary = (
		policy
		. transition(
			current,
			"retrodiffusion",
			"rd_pro",
			ProviderService.get_model_descriptors(),
		)
	)
	assert_true(changed["ok"])
	assert_eq(changed["params"]["provider_id"], "retrodiffusion")
	assert_eq(changed["params"]["model_id"], "rd_pro")
	assert_eq(changed["params"]["extra"], {"remove_bg": true, "strength": 0.8})
	for field in ["target_width", "target_height", "batch_size", "seed"]:
		assert_eq(changed["params"][field], current[field], field)
	assert_eq(changed["undo_units"], 1)
