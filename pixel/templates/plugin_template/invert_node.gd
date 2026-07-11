extends PFNode


func get_type() -> String:
	return "image_invert_example.invert"


func get_display_name() -> String:
	return "Invert Image"


func get_category() -> String:
	return "process"


func get_input_ports() -> Array[Dictionary]:
	return [{"name": "image", "type": "image", "required": true}]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "image", "type": "image"}]


func execute(inputs: Dictionary, _params: Dictionary, _ctx: Variant) -> Dictionary:
	var image: Image = inputs["image"].duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a))
	return {"image": image}
