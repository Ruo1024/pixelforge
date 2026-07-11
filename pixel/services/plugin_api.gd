class_name PFPluginAPI
extends RefCounted

## 内置插件最小注册门面。
## contract: 02-contracts/PLUGIN-API.md；其余注册面保持到 M7 再激活。

var _provider_service: Node = null


func _init(provider_service: Node) -> void:
	_provider_service = provider_service


func register_provider(provider: PFProvider) -> bool:
	return _provider_service.register_provider(provider)
