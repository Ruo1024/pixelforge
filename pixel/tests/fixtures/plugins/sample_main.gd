extends PFPlugin


class SampleNode:
	extends PFNode

	func get_type() -> String:
		return "sample.echo"

	func get_display_name() -> String:
		return "Sample Echo"

	func get_input_ports() -> Array[Dictionary]:
		return [{"name": "text", "type": "text", "required": false}]

	func get_output_ports() -> Array[Dictionary]:
		return [{"name": "text", "type": "text"}]

	func execute(inputs: Dictionary, _params: Dictionary, _ctx: Variant) -> Dictionary:
		return {"text": String(inputs.get("text", ""))}


func _enter_app(api: Variant) -> void:
	api.register_node_type("sample.echo", SampleNode)
	api.register_menu_item("Extensions/Sample Echo", _open_sample)


func _open_sample() -> void:
	return
