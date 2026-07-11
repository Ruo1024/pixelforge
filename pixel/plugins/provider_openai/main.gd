class_name PFOpenAIProviderPlugin
extends PFPlugin

## 内置 OpenAI Provider 插件入口。
## contract: 02-contracts/PLUGIN-API.md；只经 PFPluginAPI 注册能力。

const ProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")


func _enter_app(api: Variant) -> void:
	api.register_provider(ProviderScript.new())
