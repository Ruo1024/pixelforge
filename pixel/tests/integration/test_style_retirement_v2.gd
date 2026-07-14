extends "res://addons/gut/test.gd"

const BoardEditor := preload("res://ui/board/board_editor.gd")
const CleanupPipeline := preload("res://core/pixel/pipeline.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Outliner := preload("res://core/pixel/outliner.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const PixelEditor := preload("res://ui/editor/pixel_editor.gd")
const ProjectModel := preload("res://services/pf_project.gd")
const ResourceCatalog := preload("res://services/project_resource_catalog.gd")
const Segmenter := preload("res://core/pixel/segmenter.gd")

const PRODUCTION_ROOTS := [
	"res://assets", "res://core", "res://plugins", "res://services", "res://templates", "res://ui"
]
const FORBIDDEN_TERMS := [
	"style_preset", "size_spec", "prompt_template", "provider_hints", "register_style_preset"
]


func test_all_consumers_replaced() -> void:
	var project := ProjectModel.new()
	project.reset("No global style")
	assert_false(project.manifest.has("style_preset"))
	assert_false(project.manifest.has("style"))
	assert_false(project.manifest.has("prompt_preset"))
	assert_false(project.manifest.has("cleanup_preset"))

	var defaults: Dictionary = CleanupPipeline.default_params()
	assert_eq(defaults["detect_grid"]["base_size"], 32)
	assert_eq(defaults["quantize"]["palette_id"], "db32")
	var editor := PixelEditor.new()
	assert_eq(editor._project_palette_id(), "db32")
	editor.free()
	assert_eq(ResourceCatalog.search_prompt_presets().size(), 6)
	assert_eq(ResourceCatalog.search_cleanup_presets().size(), 6)

	var residuals: Array[String] = []
	for root in PRODUCTION_ROOTS:
		for path in _files_recursive(root):
			if not (path.ends_with(".gd") or path.ends_with(".json")):
				continue
			var normalized_path := path.to_lower()
			var source := FileAccess.get_file_as_string(path).to_lower()
			if path == "res://core/graph/pf_graph.gd":
				source = source.replace('["size_spec", "style_preset"]', "[]")
			for term in FORBIDDEN_TERMS:
				if term in normalized_path or term in source:
					residuals.append("%s -> %s" % [path, term])
	residuals.sort()
	assert_eq(residuals, [], "retired global Style/Size production residuals: %s" % str(residuals))


func test_independent_tools_keep_existing_behaviors() -> void:
	ProjectService.new_project("Independent tools")
	var editor := PixelEditor.new()
	assert_eq(editor._project_palette_id(), "db32")
	assert_gte(editor._project_palette().size(), 2)
	editor.free()

	var board_editor := BoardEditor.new()
	add_child_autofree(board_editor)
	await wait_process_frames(1)
	board_editor._load_or_create_board()
	assert_eq(board_editor.get_board().grid["tile_size"], 16)

	var white_bg := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	white_bg.fill(Color.WHITE)
	white_bg.set_pixel(2, 2, Color.RED)
	var matted: Image = Matting.matte(
		white_bg, {"mode": Matting.MODE_FLOOD, "tolerance": 0.0, "feather": 0}
	)["image"]
	assert_eq(matted.get_pixel(0, 0).a, 0.0)
	assert_eq(matted.get_pixel(2, 2).to_html(false), Color.RED.to_html(false))

	var segmented := Segmenter.segment(matted, {"merge_distance": 0, "min_area": 1})
	assert_eq(segmented.size(), 1)
	assert_eq(segmented[0]["rect"], Rect2i(2, 2, 1, 1))

	var outlined: Image = Outliner.add_outline(
		segmented[0]["image"],
		{"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
	)
	assert_eq(outlined.get_size(), Vector2i(3, 3))
	assert_eq(outlined.get_pixel(1, 0).to_html(false), Color.BLACK.to_html(false))

	var palette := PaletteRegistry.resolve({"palette_id": "db32"})
	assert_not_null(palette)
	assert_eq(palette.id, "db32")
	assert_gte(palette.get_color_count(), 2)


func _files_recursive(root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	for file_name in directory.get_files():
		result.append(root.path_join(String(file_name)))
	for child_name in directory.get_directories():
		result.append_array(_files_recursive(root.path_join(String(child_name))))
	return result
