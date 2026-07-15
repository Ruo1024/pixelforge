class_name PFGenerationModelPolicy
extends RefCounted

## Produces one complete ai_generate params snapshot for create/switch operations.


static func default_params(descriptors: Array, preferred_provider_id: String = "") -> Dictionary:
	var descriptor := _default_descriptor(descriptors, preferred_provider_id)
	if descriptor.is_empty():
		return {}
	return {
		"provider_id": String(descriptor["provider_id"]),
		"model_id": String(descriptor["model_id"]),
		"resolution_preset": "1080p",
		"orientation": "square",
		"batch_size": 4,
		"seed": -1,
		"extra": {},
	}


static func transition(
	current: Dictionary, provider_id: String, model_id: String, descriptors: Array
) -> Dictionary:
	var descriptor := _find_descriptor(descriptors, provider_id, model_id)
	if descriptor.is_empty():
		return {
			"ok": false,
			"issue": {"code": "invalid_provider_model", "field": "model_id", "args": {}},
			"params": current.duplicate(true),
			"undo_units": 0,
		}
	var result := current.duplicate(true)
	var model_changed := (
		String(current.get("provider_id", "")) != provider_id
		or String(current.get("model_id", "")) != model_id
	)
	result["provider_id"] = provider_id
	result["model_id"] = model_id
	if model_changed:
		result["extra"] = {}
	elif not (result.get("extra", {}) is Dictionary):
		result["extra"] = {}
	for field in ["resolution_preset", "orientation", "batch_size", "seed"]:
		if not result.has(field):
			return {
				"ok": false,
				"issue": {"code": "invalid_generation_param", "field": field, "args": {}},
				"params": current.duplicate(true),
				"undo_units": 0,
			}
	result["seed"] = -1
	result["extra"] = {}
	return {"ok": true, "issue": null, "params": result, "undo_units": 1}


static func _default_descriptor(descriptors: Array, preferred_provider_id: String) -> Dictionary:
	for value in descriptors:
		if not (value is Dictionary):
			continue
		var descriptor: Dictionary = value
		if (
			String(descriptor.get("provider_id", "")) == preferred_provider_id
			and bool(descriptor.get("is_default", false))
		):
			return descriptor.duplicate(true)
	for value in descriptors:
		if value is Dictionary and bool(value.get("is_default", false)):
			return Dictionary(value).duplicate(true)
	return {}


static func _find_descriptor(
	descriptors: Array, provider_id: String, model_id: String
) -> Dictionary:
	for value in descriptors:
		if not (value is Dictionary):
			continue
		var descriptor: Dictionary = value
		if (
			String(descriptor.get("provider_id", "")) == provider_id
			and String(descriptor.get("model_id", "")) == model_id
		):
			return descriptor.duplicate(true)
	return {}
