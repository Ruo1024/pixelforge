class_name PFBoardExporter
extends RefCounted

## Board compositor/exporter with bounded output size and deterministic animation sampling.

const AnimationScript := preload("res://core/animation/pf_animation.gd")

const MAX_OUTPUT_SIDE := 8000


func compose(
	board: PFBoard,
	asset_library: Node,
	animations: Dictionary = {},
	time_ms: int = 0,
	only_layer_id: String = ""
) -> Image:
	var tile_size := int(board.grid["tile_size"])
	var width := int(board.grid["cols"]) * tile_size
	var height := int(board.grid["rows"]) * tile_size
	if width <= 0 or height <= 0 or width > MAX_OUTPUT_SIDE or height > MAX_OUTPUT_SIDE:
		return null
	var output := Image.create(width, height, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for layer_value in board.layers:
		var layer: Dictionary = layer_value
		if not bool(layer.get("visible", true)):
			continue
		if not only_layer_id.is_empty() and String(layer.get("id", "")) != only_layer_id:
			continue
		_render_layer(output, board, layer, asset_library, animations, time_ms)
	return output


func export_flat(
	board: PFBoard, path: String, asset_library: Node, animations: Dictionary = {}, time_ms: int = 0
) -> Error:
	var image := compose(board, asset_library, animations, time_ms)
	return ERR_OUT_OF_MEMORY if image == null else image.save_png(path)


func export_layers(
	board: PFBoard, directory: String, asset_library: Node, animations: Dictionary = {}
) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	var layer_entries := []
	for layer_value in board.layers:
		var layer: Dictionary = layer_value
		var layer_id := String(layer.get("id", ""))
		var file_name := (
			"%02d_%s.png" % [layer_entries.size(), _safe_name(String(layer.get("name", "layer")))]
		)
		var image := compose(board, asset_library, animations, 0, layer_id)
		if image == null or image.save_png(directory.path_join(file_name)) != OK:
			return {"ok": false, "error": ERR_CANT_CREATE, "files": []}
		(
			layer_entries
			. append(
				{
					"id": layer_id,
					"file": file_name,
					"visible": bool(layer.get("visible", true)),
					"opacity": float(layer.get("opacity", 1.0)),
					"blend": String(layer.get("blend", "normal")),
				}
			)
		)
	var manifest_path := directory.path_join("layers.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error(), "files": []}
	file.store_string(JSON.stringify({"board_id": board.id, "layers": layer_entries}, "  "))
	var files := [manifest_path]
	for entry in layer_entries:
		files.append(directory.path_join(String(entry["file"])))
	return {"ok": true, "error": OK, "files": files}


func export_animation_frames(
	board: PFBoard,
	directory: String,
	asset_library: Node,
	animations: Dictionary,
	frame_times_ms: Array
) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	var files := []
	for index in range(frame_times_ms.size()):
		var path := directory.path_join("frame_%04d.png" % index)
		var error := export_flat(board, path, asset_library, animations, int(frame_times_ms[index]))
		if error != OK:
			return {"ok": false, "error": error, "files": files}
		files.append(path)
	return {"ok": true, "error": OK, "files": files}


func export_godot_guide(board: PFBoard, directory: String, flat_image: Image) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(directory)
	var texture_path := directory.path_join("tileset.png")
	var error := flat_image.save_png(texture_path)
	if error != OK:
		return {"ok": false, "error": error}
	var tres_path := directory.path_join("board.tres")
	var file := FileAccess.open(tres_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error()}
	file.store_string(
		(
			'[gd_resource type="Resource" format=3]\n\n'
			+ "[resource]\n"
			+ 'resource_name = "%s"\n' % board.name.replace('"', "")
			+ 'metadata/board_id = "%s"\n' % board.id
			+ "metadata/tile_size = %d\n" % int(board.grid["tile_size"])
			+ 'metadata/texture = "tileset.png"\n'
		)
	)
	return {"ok": true, "error": OK, "files": [texture_path, tres_path]}


func _render_layer(
	output: Image,
	board: PFBoard,
	layer: Dictionary,
	asset_library: Node,
	animations: Dictionary,
	time_ms: int
) -> void:
	var opacity := clampf(float(layer.get("opacity", 1.0)), 0.0, 1.0)
	var blend := String(layer.get("blend", "normal"))
	if String(layer.get("kind", "")) == PFBoard.LAYER_TILE:
		var tile_size := int(board.grid["tile_size"])
		for key in Dictionary(layer.get("cells", {})).keys():
			var cell := PFBoard.parse_cell_key(String(key))
			var cell_data: Dictionary = layer["cells"][key]
			var image: Image = asset_library.get_image(String(cell_data.get("asset_id", "")))
			if image != null:
				_blend_image(output, image, cell * tile_size, opacity, blend, false)
	else:
		var items: Array = layer.get("items", [])
		items.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("z", 0)) < int(b.get("z", 0))
		)
		for item_value in items:
			var item: Dictionary = item_value
			var asset_id := _item_asset_id(item, animations, time_ms)
			var image: Image = asset_library.get_image(asset_id)
			if image == null:
				continue
			var raw_pos: Array = item.get("pos", [0, 0])
			_blend_image(
				output,
				image,
				Vector2i(int(raw_pos[0]), int(raw_pos[1])),
				opacity,
				blend,
				bool(item.get("flip_h", false))
			)


func _item_asset_id(item: Dictionary, animations: Dictionary, time_ms: int) -> String:
	var raw_anim_id: Variant = item.get("anim_id", "")
	var anim_id := "" if raw_anim_id == null else String(raw_anim_id)
	if not anim_id.is_empty() and animations.has(anim_id):
		var animation := AnimationScript.from_json(Dictionary(animations[anim_id]))
		return animation.get_frame_asset_id(time_ms, int(item.get("anim_offset_ms", 0)))
	return String(item.get("asset_id", ""))


func _blend_image(
	destination: Image,
	source: Image,
	position: Vector2i,
	opacity: float,
	blend: String,
	flip_h: bool
) -> void:
	for source_y in range(source.get_height()):
		var target_y := position.y + source_y
		if target_y < 0 or target_y >= destination.get_height():
			continue
		for source_x in range(source.get_width()):
			var target_x := position.x + source_x
			if target_x < 0 or target_x >= destination.get_width():
				continue
			var read_x := source.get_width() - source_x - 1 if flip_h else source_x
			var src := source.get_pixel(read_x, source_y)
			src.a *= opacity
			if src.a <= 0.0:
				continue
			var dst := destination.get_pixel(target_x, target_y)
			destination.set_pixel(target_x, target_y, _blend_color(dst, src, blend))


func _blend_color(dst: Color, src: Color, blend: String) -> Color:
	var alpha := src.a + dst.a * (1.0 - src.a)
	if blend == "add":
		return Color(
			minf(1.0, dst.r + src.r * src.a),
			minf(1.0, dst.g + src.g * src.a),
			minf(1.0, dst.b + src.b * src.a),
			alpha
		)
	if blend == "multiply":
		return Color(
			dst.r * lerpf(1.0, src.r, src.a),
			dst.g * lerpf(1.0, src.g, src.a),
			dst.b * lerpf(1.0, src.b, src.a),
			alpha
		)
	if alpha <= 0.0:
		return Color.TRANSPARENT
	return Color(
		(src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / alpha,
		(src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / alpha,
		(src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / alpha,
		alpha
	)


func _safe_name(value: String) -> String:
	var safe := value.strip_edges().to_lower().replace(" ", "_")
	return safe.validate_filename() if not safe.is_empty() else "layer"
