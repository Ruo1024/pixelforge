extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")


class LegacyProvider:
	extends PFProvider
	var side_effect_calls := 0

	func get_api_version() -> int:
		return 1

	func get_config_schema() -> Array[Dictionary]:
		side_effect_calls += 1
		return []

	func get_model_descriptors() -> Array[Dictionary]:
		side_effect_calls += 1
		return []

	func estimate_cost(_request: Dictionary) -> Variant:
		side_effect_calls += 1
		return null

	func generate(_request: Dictionary) -> PFProviderTaskV2:
		side_effect_calls += 1
		return null

	func cancel(_request_id: String) -> PFCancelTaskV2:
		side_effect_calls += 1
		return null


func test_provider_v1_isolated_before_registration() -> void:
	var service := ProviderServiceScript.new()
	service.load_builtin_plugins = false
	add_child_autofree(service)
	await wait_process_frames(1)
	var legacy := LegacyProvider.new()
	var result: Dictionary = service.register_provider(legacy)
	assert_false(result["ok"])
	assert_eq(result["error"]["code"], "unsupported_provider_api_version")
	assert_eq(legacy.side_effect_calls, 0)
	assert_eq(service.get_provider_ids(), [])


func test_provider_base_and_service_gate_are_v2() -> void:
	assert_eq(PFProvider.new().get_api_version(), 2)
	assert_eq(ProviderServiceScript.API_VERSION, 2)
	assert_eq(
		ProviderServiceScript.BUILTIN_PROVIDER_PLUGINS,
		[
			"res://plugins/provider_openai/main.gd",
			"res://plugins/provider_retrodiffusion/main.gd",
		]
	)
