class_name PFProvider
extends RefCounted

## Provider API v2 execution boundary. Configuration lifecycle is owned by ProviderService.


func get_api_version() -> int:
	return 2


func get_config_schema() -> Array[Dictionary]:
	return []


func get_model_descriptors() -> Array[Dictionary]:
	return []


func generate(_request: Dictionary) -> PFProviderTaskV2:
	return null


func cancel(_request_id: String) -> PFCancelTaskV2:
	return null
