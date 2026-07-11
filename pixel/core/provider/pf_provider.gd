class_name PFProvider
extends RefCounted

## AI Provider 领域接口。
## contract: 02-contracts/PROVIDER-API.md；实现不得持久化凭据或依赖 UI。


func get_id() -> String:
	return "base"


func get_display_name() -> String:
	return "Base Provider"


func get_api_version() -> int:
	return 1


func get_capabilities() -> Dictionary:
	return {}


func get_config_schema() -> Array[Dictionary]:
	return []


func configure(_config: Dictionary) -> Variant:
	return null


func validate_credentials() -> Variant:
	return null


func generate(_request: Dictionary) -> Variant:
	return null


func estimate_cost(_request: Dictionary) -> float:
	return -1.0


func cancel(_task_id: String) -> void:
	return
