extends SceneTree

const Catalog := preload("res://infra/localization_catalog.gd")


func _init() -> void:
	var errors := Catalog.load_and_validate()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(1)
		return
	quit()
