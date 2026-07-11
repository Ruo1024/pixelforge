extends PFPlugin


func _enter_app(api: Variant) -> void:
	var node_script := load(get_script().resource_path.get_base_dir().path_join("invert_node.gd"))
	api.register_node_type("image_invert_example.invert", node_script)
