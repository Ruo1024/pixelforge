class_name PFBoardEditor
extends ConfirmationDialog

## Operable Board workspace: searchable assets, finite canvas, layers, terrain, playback, export.

const Strings := preload("res://ui/shell/strings.gd")
const BoardScript := preload("res://core/board/pf_board.gd")
const AnimationScript := preload("res://core/animation/pf_animation.gd")
const TerrainGroupScript := preload("res://core/board/terrain_group.gd")
const BoardCanvasScript := preload("res://ui/board/board_canvas.gd")
const ExporterScript := preload("res://services/board_exporter.gd")

const DIALOG_SIZE := Vector2i(1180, 760)

var _board: PFBoard = null
var _canvas: PFBoardCanvas = null
var _asset_search: LineEdit = null
var _asset_list: ItemList = null
var _layer_list: ItemList = null
var _opacity: HSlider = null
var _blend: OptionButton = null
var _status: Label = null
var _export_dialog: FileDialog = null


func _ready() -> void:
	title = Strings.text("DIALOG_BOARD_TITLE")
	ok_button_text = Strings.text("ACTION_CLOSE")
	min_size = DIALOG_SIZE
	_build_ui()
	_refresh_assets()
	ProjectService.project_loaded.connect(func(_project: Variant) -> void: _load_or_create_board())
	AssetLibrary.asset_added.connect(func(_asset_id: String) -> void: _refresh_assets())
	AssetLibrary.asset_removed.connect(func(_asset_id: String) -> void: _refresh_assets())


func show_editor() -> void:
	_load_or_create_board()
	_refresh_assets()
	popup_centered()


func get_board() -> PFBoard:
	return _board


func get_board_canvas() -> PFBoardCanvas:
	return _canvas


func _build_ui() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var assets_panel := VBoxContainer.new()
	assets_panel.custom_minimum_size.x = 230
	root.add_child(assets_panel)
	var assets_title := Label.new()
	assets_title.text = Strings.text("BOARD_ASSETS")
	assets_panel.add_child(assets_title)
	_asset_search = LineEdit.new()
	_asset_search.placeholder_text = Strings.text("BOARD_SEARCH_ASSETS")
	_asset_search.text_changed.connect(func(_text: String) -> void: _refresh_assets())
	assets_panel.add_child(_asset_search)
	_asset_list = ItemList.new()
	_asset_list.select_mode = ItemList.SELECT_MULTI
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_asset_list.item_selected.connect(_on_asset_selected)
	assets_panel.add_child(_asset_list)
	var terrain_button := Button.new()
	terrain_button.text = Strings.text("BOARD_DEFINE_TERRAIN_16")
	terrain_button.pressed.connect(_define_terrain_16)
	assets_panel.add_child(terrain_button)
	var terrain_47_button := Button.new()
	terrain_47_button.text = Strings.text("BOARD_DEFINE_TERRAIN_47")
	terrain_47_button.pressed.connect(_define_terrain_47)
	assets_panel.add_child(terrain_47_button)
	var animation_button := Button.new()
	animation_button.text = Strings.text("BOARD_CREATE_ANIMATION")
	animation_button.pressed.connect(_create_animation_from_selection)
	assets_panel.add_child(animation_button)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(center)
	var tools := HBoxContainer.new()
	center.add_child(tools)
	_add_button(
		tools, Strings.text("BOARD_TOOL_PAINT"), func() -> void: _canvas.set_brush_mode("paint")
	)
	_add_button(
		tools, Strings.text("BOARD_TOOL_RECT"), func() -> void: _canvas.set_brush_mode("rectangle")
	)
	_add_button(
		tools, Strings.text("BOARD_TOOL_FILL"), func() -> void: _canvas.set_brush_mode("fill")
	)
	_add_button(tools, Strings.text("BOARD_PLAY_PAUSE"), _toggle_playback)
	_add_button(tools, Strings.text("BOARD_EXPORT"), _show_export_dialog)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_status)
	_canvas = BoardCanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.fallback_warning.connect(
		func(count: int) -> void: _status.text = Strings.text("BOARD_TERRAIN_FALLBACK") % count
	)
	_canvas.palette_warning.connect(
		func(asset_palette: String, project_palette: String) -> void:
			_status.text = Strings.text("BOARD_PALETTE_WARNING") % [asset_palette, project_palette]
	)
	center.add_child(_canvas)

	var layers_panel := VBoxContainer.new()
	layers_panel.custom_minimum_size.x = 230
	root.add_child(layers_panel)
	var layers_title := Label.new()
	layers_title.text = Strings.text("BOARD_LAYERS")
	layers_panel.add_child(layers_title)
	_layer_list = ItemList.new()
	_layer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layer_list.item_selected.connect(_on_layer_selected)
	layers_panel.add_child(_layer_list)
	var add_row := HBoxContainer.new()
	layers_panel.add_child(add_row)
	_add_button(add_row, Strings.text("BOARD_ADD_TILE_LAYER"), _add_tile_layer)
	_add_button(add_row, Strings.text("BOARD_ADD_FREE_LAYER"), _add_free_layer)
	var order_row := HBoxContainer.new()
	layers_panel.add_child(order_row)
	_add_button(order_row, Strings.text("BOARD_LAYER_UP"), _move_layer_up)
	_add_button(order_row, Strings.text("BOARD_LAYER_DOWN"), _move_layer_down)
	_add_button(layers_panel, Strings.text("BOARD_LAYER_VISIBLE"), _toggle_layer_visible)
	_add_button(layers_panel, Strings.text("BOARD_DELETE_LAYER"), _delete_layer)
	var opacity_label := Label.new()
	opacity_label.text = Strings.text("BOARD_OPACITY")
	layers_panel.add_child(opacity_label)
	_opacity = HSlider.new()
	_opacity.min_value = 0.0
	_opacity.max_value = 1.0
	_opacity.step = 0.05
	_opacity.value_changed.connect(_on_layer_visual_changed)
	layers_panel.add_child(_opacity)
	_blend = OptionButton.new()
	for blend in PFBoard.BLENDS:
		_blend.add_item(String(blend).capitalize())
		_blend.set_item_metadata(_blend.item_count - 1, blend)
	_blend.item_selected.connect(
		func(_index: int) -> void: _on_layer_visual_changed(_opacity.value)
	)
	layers_panel.add_child(_blend)

	_export_dialog = FileDialog.new()
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.filters = PackedStringArray(["*.png ; PNG Image"])
	_export_dialog.file_selected.connect(_export_board)
	add_child(_export_dialog)


func _load_or_create_board() -> void:
	var boards := ProjectService.get_document_data("boards")
	if boards.is_empty():
		_board = BoardScript.new("Farm Scene", 60, 40, 16)
		_board.add_layer("Terrain", PFBoard.LAYER_TILE)
		_board.add_layer("Props", PFBoard.LAYER_FREE)
		_board.add_layer("VFX", PFBoard.LAYER_FREE)
		ProjectService.set_document_data("boards", _board.id, _board.to_json(), true)
	else:
		var board_id := String(boards.keys()[0])
		_board = BoardScript.from_json(boards[board_id])
	_canvas.set_board(_board)
	_refresh_layers()


func _refresh_assets() -> void:
	if _asset_list == null:
		return
	var query := _asset_search.text.strip_edges().to_lower() if _asset_search != null else ""
	_asset_list.clear()
	var metadata := AssetLibrary.get_all_meta()
	var ids: Array = metadata.keys()
	ids.sort()
	for asset_id in ids:
		var meta: Dictionary = metadata[asset_id]
		var searchable := "%s %s" % [String(meta.get("name", "")), " ".join(meta.get("tags", []))]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		_asset_list.add_item(String(meta.get("name", asset_id)))
		_asset_list.set_item_metadata(_asset_list.item_count - 1, {"asset_id": asset_id})
	for anim_id in ProjectService.get_document_data("animations").keys():
		var anim_data: Dictionary = ProjectService.get_document_data("animations", String(anim_id))
		_asset_list.add_item("▶ %s" % String(anim_data.get("name", anim_id)))
		_asset_list.set_item_metadata(
			_asset_list.item_count - 1,
			{"asset_id": String(Array(anim_data.get("frames", [""]))[0]), "anim_id": anim_id}
		)


func _refresh_layers() -> void:
	_layer_list.clear()
	for layer_value in _board.layers:
		var layer: Dictionary = layer_value
		var prefix := "●" if bool(layer.get("visible", true)) else "○"
		_layer_list.add_item("%s %s [%s]" % [prefix, layer["name"], layer["kind"]])
		_layer_list.set_item_metadata(_layer_list.item_count - 1, layer["id"])
	if _layer_list.item_count > 0:
		var selected := maxi(0, _board._layer_index(_canvas.selected_layer_id))
		_layer_list.select(selected)
		_on_layer_selected(selected)


func _on_asset_selected(index: int) -> void:
	var data: Dictionary = _asset_list.get_item_metadata(index)
	_canvas.set_selected_asset(String(data.get("asset_id", "")), String(data.get("anim_id", "")))


func _on_layer_selected(index: int) -> void:
	if index < 0 or index >= _layer_list.item_count:
		return
	_canvas.selected_layer_id = String(_layer_list.get_item_metadata(index))
	var layer := _board.get_layer(_canvas.selected_layer_id)
	_opacity.set_value_no_signal(float(layer.get("opacity", 1.0)))
	for blend_index in range(_blend.item_count):
		if String(_blend.get_item_metadata(blend_index)) == String(layer.get("blend", "normal")):
			_blend.select(blend_index)
			break


func _selected_asset_ids() -> Array:
	var ids := []
	for index in _asset_list.get_selected_items():
		var data: Dictionary = _asset_list.get_item_metadata(index)
		var asset_id := String(data.get("asset_id", ""))
		if not asset_id.is_empty() and String(data.get("anim_id", "")).is_empty():
			ids.append(asset_id)
	return ids


func _define_terrain_16() -> void:
	var ids := _selected_asset_ids()
	if ids.size() < 16:
		_status.text = Strings.text("BOARD_TERRAIN_NEEDS_16")
		return
	var group := TerrainGroupScript.new()
	group.id = "terrain_%s" % _board.id.left(8)
	group.name = "Board Terrain"
	group.mode = 16
	for role in range(16):
		group.roles[str(role)] = [ids[role]]
	_canvas.set_terrain_group(group)
	_status.text = Strings.text("BOARD_TERRAIN_READY")


func _define_terrain_47() -> void:
	var ids := _selected_asset_ids()
	if ids.size() < 47:
		_status.text = Strings.text("BOARD_TERRAIN_NEEDS_47")
		return
	var group := TerrainGroupScript.new()
	group.id = "terrain47_%s" % _board.id.left(8)
	group.name = "Board Terrain 47"
	group.mode = 47
	for role in range(47):
		group.roles[str(role)] = [ids[role]]
	_canvas.set_terrain_group(group)
	_status.text = Strings.text("BOARD_TERRAIN_47_READY")


func _create_animation_from_selection() -> void:
	var ids := _selected_asset_ids()
	if ids.size() < 2:
		_status.text = Strings.text("BOARD_ANIMATION_NEEDS_FRAMES")
		return
	var animation := AnimationScript.new(
		"Animation %d" % (ProjectService.get_document_data("animations").size() + 1)
	)
	var durations := []
	for _id in ids:
		durations.append(100)
	animation.configure(ids, durations, true)
	ProjectService.set_document_data("animations", animation.id, animation.to_json(), true)
	_canvas.set_selected_asset(String(ids[0]), animation.id)
	_refresh_assets()
	_status.text = Strings.text("BOARD_ANIMATION_READY") % ids.size()


func _add_tile_layer() -> void:
	_canvas.selected_layer_id = _board.add_layer(
		"Tile %d" % (_board.layers.size() + 1), PFBoard.LAYER_TILE
	)
	_commit_board()


func _add_free_layer() -> void:
	_canvas.selected_layer_id = _board.add_layer(
		"Free %d" % (_board.layers.size() + 1), PFBoard.LAYER_FREE
	)
	_commit_board()


func _delete_layer() -> void:
	if _board.layers.size() <= 1:
		return
	_board.remove_layer(_canvas.selected_layer_id)
	_canvas.selected_layer_id = String(_board.layers[0]["id"])
	_commit_board()


func _move_layer_up() -> void:
	var index := _board._layer_index(_canvas.selected_layer_id)
	_board.move_layer(_canvas.selected_layer_id, index + 1)
	_commit_board()


func _move_layer_down() -> void:
	var index := _board._layer_index(_canvas.selected_layer_id)
	_board.move_layer(_canvas.selected_layer_id, index - 1)
	_commit_board()


func _toggle_layer_visible() -> void:
	var layer := _board.get_layer(_canvas.selected_layer_id)
	_board.set_layer_visuals(
		_canvas.selected_layer_id,
		not bool(layer.get("visible", true)),
		float(layer.get("opacity", 1.0)),
		String(layer.get("blend", "normal"))
	)
	_commit_board()


func _on_layer_visual_changed(_value: float) -> void:
	if _board == null or _canvas.selected_layer_id.is_empty():
		return
	var layer := _board.get_layer(_canvas.selected_layer_id)
	_board.set_layer_visuals(
		_canvas.selected_layer_id,
		bool(layer.get("visible", true)),
		_opacity.value,
		String(_blend.get_item_metadata(_blend.selected))
	)
	_commit_board()


func _toggle_playback() -> void:
	_canvas.set_playing(not _canvas.playing)


func _show_export_dialog() -> void:
	_export_dialog.current_file = "%s.png" % _board.name.to_snake_case()
	_export_dialog.popup_centered_ratio(0.7)


func _export_board(path: String) -> void:
	var exporter := ExporterScript.new()
	var error := exporter.export_flat(
		_board, path, AssetLibrary, ProjectService.get_document_data("animations"), 0
	)
	if error == OK:
		exporter.export_layers(
			_board,
			path.get_basename() + "_layers",
			AssetLibrary,
			ProjectService.get_document_data("animations")
		)
	_status.text = (
		Strings.text("BOARD_EXPORT_DONE") if error == OK else Strings.text("BOARD_EXPORT_FAILED")
	)


func _commit_board() -> void:
	ProjectService.set_document_data("boards", _board.id, _board.to_json(), true)
	_refresh_layers()
	_canvas.queue_redraw()


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
