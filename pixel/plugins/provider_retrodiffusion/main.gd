class_name PFRetroDiffusionProviderPlugin
extends PFPlugin

## Built-in RetroDiffusion plugin registered only through PFPluginAPI.
## contract: 02-contracts/PLUGIN-API.md。

const ProviderScript := preload("res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd")


func _enter_app(api: Variant) -> void:
	api.register_provider(ProviderScript.new())
