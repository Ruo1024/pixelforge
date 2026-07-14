extends PFProvider

const TaskScript := preload("res://services/pf_task.gd")

var configured_key := ""
var configured_endpoint := ""
var safe_validation := true


func get_id() -> String:
	return "fixture_provider"


func get_display_name() -> String:
	return "Fixture Provider"


func get_capabilities() -> Dictionary:
	return {
		"txt2img": true,
		"img2img": false,
		"transparent_bg": false,
		"native_pixel": false,
		"max_batch": 2,
		"safe_validation": safe_validation,
	}


func get_config_schema() -> Array[Dictionary]:
	return [
		{"key": "api_key", "label": "Fixture key", "kind": "password"},
		{
			"key": "endpoint",
			"label": "Endpoint",
			"kind": "text",
			"default": "https://fixture.invalid",
		},
	]


func configure(config: Dictionary) -> Variant:
	configured_key = String(config.get("api_key", ""))
	configured_endpoint = String(config.get("endpoint", ""))
	if configured_key.is_empty():
		return {"code": "auth_failed", "message": "Fixture key is required"}
	return null


func validate_credentials() -> Variant:
	var task := TaskScript.new("fixture_validate", {"provider_id": get_id()})
	task.configure_external(
		func(task_ref: Variant) -> void:
			if configured_key == "fixture-good-key":
				task_ref.resolve({"ok": true})
			else:
				task_ref.reject({"code": "auth_failed", "message": "Fixture key rejected"})
	)
	return task


func generate(_request: Dictionary) -> Variant:
	var task := TaskScript.new("fixture_generate", {"provider_id": get_id()})
	task.configure_external(
		func(task_ref: Variant) -> void:
			if configured_key == "fixture-good-key":
				task_ref.resolve({"ok": true})
			else:
				task_ref.reject({"code": "auth_failed", "message": "Fixture key rejected"})
	)
	return task


func estimate_cost(request: Dictionary) -> float:
	return 0.25 * maxi(1, int(request.get("batch", 1)))


func clear_session_config() -> void:
	configured_key = ""
	configured_endpoint = ""
