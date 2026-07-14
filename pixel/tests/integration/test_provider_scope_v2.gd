extends "res://addons/gut/test.gd"

const ProviderServiceScript := preload("res://services/provider_service.gd")


func test_only_mock_openai_retro_no_paid_endpoint() -> void:
	assert_eq(
		ProviderServiceScript.BUILTIN_PROVIDER_PLUGINS,
		[
			"res://plugins/provider_openai/main.gd",
			"res://plugins/provider_retrodiffusion/main.gd",
		]
	)
	assert_eq(ProviderService.get_provider_ids(), ["openai_image", "retrodiffusion"])
	assert_false(ProviderService.get_provider_ids().has("comfyui"))
	assert_false(OS.get_environment("PF_HTTP_MOCK_URL").is_empty())
	for path in [
		"res://tests/integration/test_openai_provider_contract.gd",
		"res://tests/integration/test_retrodiffusion_provider_contract.gd",
		"res://tests/integration/test_provider_descriptors_v2.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_true(source.contains("PF_HTTP_MOCK_URL"), path)
		assert_false(source.contains("Computer Use"), path)
