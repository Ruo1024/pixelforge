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
