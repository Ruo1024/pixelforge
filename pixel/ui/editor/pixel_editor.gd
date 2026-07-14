class_name PFPixelEditor
extends ConfirmationDialog

## Aseprite-lite repair workspace for the final 30% of generated-asset cleanup.

signal asset_saved(old_asset_id: String, new_asset_id: String, source_batch_id: String)

const Strings := preload("res://ui/shell/strings.gd")
const EditDocScript := preload("res://core/editor/pf_edit_doc.gd")
const HistoryScript := preload("res://core/editor/edit_history.gd")
const AnimationScript := preload("res://core/animation/pf_animation.gd")
const Drawing := preload("res://core/editor/pixel_drawing.gd")
const Repair := preload("res://core/editor/repair_analysis.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const CanvasScript := preload("res://ui/editor/pixel_editor_canvas.gd")
const TransitionScript := preload("res://ui/editor/editor_transition.gd")

var document: PFEditDoc = null
var source_batch_id := ""
var _canvas: PFPixelEditorCanvas = null
var _history: PFEditHistory = HistoryScript.new()
var _layers: ItemList = null
var _timeline: ItemList = null
var _palette_grid: GridContainer = null
var _status: Label = null
var _duration: SpinBox = null
var _playing := false
var _playback_elapsed := 0.0
var _discard_dialog: ConfirmationDialog = null
var _overwrite_dialog: ConfirmationDialog = null
var _palette_index := -1
var _preview_window: Window = null
var _preview_texture: TextureRect = null
var _tag_name: LineEdit = null
var _tag_from: SpinBox = null
var _tag_to: SpinBox = null
var _preview_scale := 4
var _layer_asset_options: OptionButton = null


func _ready() -> void:
	title = Strings.text("DIALOG_PIXEL_EDITOR")
	ok_button_text = Strings.text("ACTION_CLOSE")
	min_size = Vector2i(1240, 800)
	_build_ui()
	confirmed.connect(_request_close)
	set_process(true)


func open_asset(asset_id: String, batch_id: String = "") -> bool:
	var image: Image = AssetLibrary.get_image(asset_id)
	if image == null:
		return false
	source_batch_id = batch_id
	document = EditDocScript.from_asset(image, asset_id, _project_palette())
	var saved_palette: Variant = AssetLibrary.get_asset_meta(asset_id).get("editor_palette", null)
	if saved_palette is Array and not saved_palette.is_empty():
		document.palette.clear()
		for hex_color in saved_palette:
			document.palette.append(Color.html(String(hex_color)))
	_canvas.set_document(document)
	_rebuild_layers()
	_rebuild_timeline()
	_rebuild_palette()
	_status.text = (
		Strings.text("EDITOR_OPENED") % AssetLibrary.get_asset_meta(asset_id).get("name", asset_id)
	)
	popup_centered()
	var veil := TransitionScript.new()
	add_child(veil)
	veil.play_in(ImageTexture.create_from_image(image))
	return true


func open_animation(animation_id: String, batch_id: String = "") -> bool:
	var data := ProjectService.get_document_data("animations", animation_id)
	if data.is_empty():
		return false
	var animation := AnimationScript.from_json(data)
	document = EditDocScript.from_animation(animation, AssetLibrary, _project_palette())
	if document == null:
		return false
	source_batch_id = batch_id
	document.tags = animation.tags.duplicate(true)
	_canvas.set_document(document)
	_rebuild_layers()
	_rebuild_timeline()
	_rebuild_palette()
	popup_centered()
	return true


func import_as_layer(asset_id: String) -> bool:
	if document == null or document.layers.size() >= 32:
		return false
	var image: Image = AssetLibrary.get_image(asset_id)
	if image == null or image.get_size() != document.size:
		return false
	_history.capture(document)
	document.add_layer(
		String(AssetLibrary.get_asset_meta(asset_id).get("name", "Reference")), image
	)
	_rebuild_layers()
	_canvas.set_layer(document.layers.size() - 1)
	return true


func _process(delta: float) -> void:
	if not _playing or document == null or document.frame_count() <= 1:
		return
	_playback_elapsed += delta * 1000.0
	var duration := float(document.frame_durations[_canvas.frame_index])
	if _playback_elapsed >= duration:
		_playback_elapsed = 0.0
		_canvas.set_frame((_canvas.frame_index + 1) % document.frame_count())
		_sync_timeline_selection()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var toolbar := HFlowContainer.new()
	root.add_child(toolbar)
	for spec in [
		[Strings.text("EDITOR_PENCIL"), "pencil"],
		[Strings.text("EDITOR_ERASER"), "eraser"],
		[Strings.text("EDITOR_PICKER"), "picker"],
		[Strings.text("EDITOR_FILL"), "fill"],
		[Strings.text("EDITOR_LINE"), "line"],
		[Strings.text("EDITOR_RECTANGLE"), "rectangle"],
		[Strings.text("EDITOR_ELLIPSE"), "ellipse"],
		[Strings.text("EDITOR_MOVE"), "move"]
	]:
		_add_tool_button(toolbar, String(spec[0]), String(spec[1]))
	var brush_size := SpinBox.new()
	brush_size.min_value = 1
	brush_size.max_value = 8
	brush_size.value = 1
	brush_size.value_changed.connect(func(value: float) -> void: _canvas.brush_size = int(value))
	toolbar.add_child(brush_size)
	_add_button(toolbar, Strings.text("EDITOR_UNDO"), _undo)
	_add_button(toolbar, Strings.text("EDITOR_REDO"), _redo)
	_add_button(
		toolbar,
		Strings.text("EDITOR_MIRROR_H"),
		func() -> void: _canvas.mirror_h = not _canvas.mirror_h
	)
	_add_button(
		toolbar,
		Strings.text("EDITOR_MIRROR_V"),
		func() -> void: _canvas.mirror_v = not _canvas.mirror_v
	)
	_add_button(
		toolbar,
		Strings.text("EDITOR_CONSTRAIN"),
		func() -> void: _canvas.constrain_palette = not _canvas.constrain_palette
	)
	_add_button(
		toolbar,
		Strings.text("EDITOR_GLOBAL_FILL"),
		func() -> void: _canvas.global_fill = not _canvas.global_fill
	)
	_add_button(toolbar, Strings.text("EDITOR_NOISE_CLEAN"), _clean_noise)
	_add_button(toolbar, Strings.text("EDITOR_GAP_SCAN"), _scan_gaps)
	_add_button(toolbar, Strings.text("EDITOR_QUANTIZE"), _quantize_to_palette)
	_add_button(toolbar, Strings.text("EDITOR_SAVE_AS"), func() -> void: _save(false))
	_add_button(
		toolbar,
		Strings.text("EDITOR_OVERWRITE"),
		func() -> void: _overwrite_dialog.popup_centered()
	)
	_add_button(toolbar, Strings.text("EDITOR_PREVIEW"), _show_preview)
	var inpaint := Button.new()
	inpaint.text = Strings.text("EDITOR_INPAINT")
	inpaint.disabled = true
	inpaint.tooltip_text = Strings.text("EDITOR_INPAINT_DISABLED")
	toolbar.add_child(inpaint)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_status)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 220
	body.add_child(left)
	var palette_title := Label.new()
	palette_title.text = Strings.text("EDITOR_PALETTE")
	left.add_child(palette_title)
	_palette_grid = GridContainer.new()
	_palette_grid.columns = 6
	left.add_child(_palette_grid)
	var foreground_picker := ColorPickerButton.new()
	foreground_picker.color = Color.WHITE
	foreground_picker.color_changed.connect(
		func(color: Color) -> void: _canvas.foreground = _constrained(color)
	)
	left.add_child(foreground_picker)
	_add_button(left, Strings.text("EDITOR_SWAP_COLORS"), _swap_colors)
	_add_button(left, Strings.text("EDITOR_PALETTE_ADD"), _add_palette_color)
	_add_button(left, Strings.text("EDITOR_PALETTE_DELETE"), _delete_palette_color)
	_add_button(left, Strings.text("EDITOR_PALETTE_UP"), func() -> void: _move_palette_color(-1))
	_add_button(left, Strings.text("EDITOR_PALETTE_DOWN"), func() -> void: _move_palette_color(1))
	_add_button(left, Strings.text("EDITOR_PALETTE_REMAP"), _remap_palette_color)

	_canvas = CanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.document_changed.connect(
		func(_rect: Rect2i) -> void:
			_status.text = Strings.text("EDITOR_MODIFIED")
			_update_preview()
	)
	_canvas.stroke_started.connect(func() -> void: _history.capture(document))
	_canvas.color_picked.connect(func(color: Color) -> void: _canvas.foreground = color)
	body.add_child(_canvas)

	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 230
	body.add_child(right)
	var layers_title := Label.new()
	layers_title.text = Strings.text("EDITOR_LAYERS")
	right.add_child(layers_title)
	_layers = ItemList.new()
	_layers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_layers.item_selected.connect(func(index: int) -> void: _canvas.set_layer(index))
	right.add_child(_layers)
	_add_button(right, Strings.text("EDITOR_ADD_LAYER"), _add_layer)
	_layer_asset_options = OptionButton.new()
	right.add_child(_layer_asset_options)
	_add_button(right, Strings.text("EDITOR_IMPORT_LAYER"), _import_selected_layer)
	_add_button(right, Strings.text("EDITOR_TOGGLE_LAYER"), _toggle_layer)
	_add_button(right, Strings.text("EDITOR_LOCK_LAYER"), _toggle_lock)
	var opacity := HSlider.new()
	opacity.min_value = 0.0
	opacity.max_value = 1.0
	opacity.step = 0.05
	opacity.value = 1.0
	opacity.value_changed.connect(_set_layer_opacity)
	right.add_child(opacity)

	var timeline_row := HBoxContainer.new()
	root.add_child(timeline_row)
	_add_button(timeline_row, Strings.text("EDITOR_PLAY"), func() -> void: _playing = not _playing)
	_add_button(timeline_row, Strings.text("EDITOR_ADD_FRAME"), _add_frame)
	_add_button(timeline_row, Strings.text("EDITOR_DUP_FRAME"), _duplicate_frame)
	_add_button(timeline_row, Strings.text("EDITOR_DELETE_FRAME"), _delete_frame)
	_add_button(timeline_row, Strings.text("EDITOR_FRAME_LEFT"), func() -> void: _move_frame(-1))
	_add_button(timeline_row, Strings.text("EDITOR_FRAME_RIGHT"), func() -> void: _move_frame(1))
	var onion := CheckButton.new()
	onion.text = Strings.text("EDITOR_ONION")
	onion.button_pressed = true
	onion.toggled.connect(
		func(value: bool) -> void:
			_canvas.onion_skin = value
			_canvas.queue_redraw()
	)
	timeline_row.add_child(onion)
	_duration = SpinBox.new()
	_duration.min_value = 1
	_duration.max_value = 5000
	_duration.value = 100
	_duration.value_changed.connect(_set_duration)
	timeline_row.add_child(_duration)
	_tag_name = LineEdit.new()
	_tag_name.placeholder_text = Strings.text("EDITOR_TAG_NAME")
	_tag_name.custom_minimum_size.x = 100
	timeline_row.add_child(_tag_name)
	_tag_from = SpinBox.new()
	_tag_from.min_value = 1
	_tag_from.max_value = 64
	timeline_row.add_child(_tag_from)
	_tag_to = SpinBox.new()
	_tag_to.min_value = 1
	_tag_to.max_value = 64
	timeline_row.add_child(_tag_to)
	_add_button(timeline_row, Strings.text("EDITOR_ADD_TAG"), _add_tag)
	_timeline = ItemList.new()
	_timeline.layout_mode = 1
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.item_selected.connect(
		func(index: int) -> void:
			_canvas.set_frame(index)
			_sync_timeline_selection()
	)
	timeline_row.add_child(_timeline)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = Strings.text("EDITOR_DISCARD_TITLE")
	_discard_dialog.dialog_text = Strings.text("EDITOR_DISCARD_BODY")
	_discard_dialog.confirmed.connect(
		func() -> void:
			document.dirty = false
			hide()
	)
	add_child(_discard_dialog)
	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.title = Strings.text("EDITOR_OVERWRITE_TITLE")
	_overwrite_dialog.dialog_text = Strings.text("EDITOR_OVERWRITE_BODY")
	_overwrite_dialog.confirmed.connect(func() -> void: _save(true))
	add_child(_overwrite_dialog)
	_preview_window = Window.new()
	_preview_window.title = Strings.text("EDITOR_PREVIEW_TITLE")
	_preview_window.size = Vector2i(320, 320)
	_preview_window.visible = false
	var preview_root := VBoxContainer.new()
	preview_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var preview_scale := OptionButton.new()
	for scale in [1, 2, 4]:
		preview_scale.add_item("%dx" % scale)
		preview_scale.set_item_metadata(preview_scale.item_count - 1, scale)
	preview_scale.select(2)
	preview_scale.item_selected.connect(
		func(index: int) -> void:
			_preview_scale = int(preview_scale.get_item_metadata(index))
			_resize_preview()
	)
	preview_root.add_child(preview_scale)
	_preview_texture = TextureRect.new()
	_preview_texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_root.add_child(_preview_texture)
	_preview_window.add_child(preview_root)
	add_child(_preview_window)


func _rebuild_palette() -> void:
	for child in _palette_grid.get_children():
		child.queue_free()
	for color_index in range(document.palette.size()):
		var color: Color = document.palette[color_index]
		var swatch := Button.new()
		swatch.text = "  "
		var style := StyleBoxFlat.new()
		style.bg_color = color
		swatch.add_theme_stylebox_override("normal", style)
		swatch.pressed.connect(
			func() -> void:
				_palette_index = color_index
				_canvas.foreground = color
		)
		_palette_grid.add_child(swatch)


func _rebuild_layers() -> void:
	_layers.clear()
	for layer_value in document.layers:
		var layer: Dictionary = layer_value
		_layers.add_item(
			(
				"%s%s%s"
				% [
					"● " if layer.get("visible", true) else "○ ",
					"🔒 " if layer.get("locked", false) else "",
					layer.get("name", "Layer")
				]
			)
		)
	if _layers.item_count > 0:
		_layers.select(clampi(_canvas.layer_index, 0, _layers.item_count - 1))
	_rebuild_layer_asset_options()


func _rebuild_layer_asset_options() -> void:
	if _layer_asset_options == null:
		return
	_layer_asset_options.clear()
	var metadata := AssetLibrary.get_all_meta()
	var ids: Array = metadata.keys()
	ids.sort()
	for asset_id in ids:
		if String(asset_id) == document.source_asset_id:
			continue
		_layer_asset_options.add_item(String(metadata[asset_id].get("name", asset_id)))
		_layer_asset_options.set_item_metadata(_layer_asset_options.item_count - 1, asset_id)


func _import_selected_layer() -> void:
	if _layer_asset_options.item_count <= 0:
		return
	var asset_id := String(_layer_asset_options.get_item_metadata(_layer_asset_options.selected))
	if not import_as_layer(asset_id):
		_status.text = Strings.text("EDITOR_IMPORT_LAYER_FAILED")


func _rebuild_timeline() -> void:
	_timeline.clear()
	for index in range(document.frame_count()):
		_timeline.add_item("%d\n%dms" % [index + 1, document.frame_durations[index]])
	_sync_timeline_selection()


func _sync_timeline_selection() -> void:
	if _timeline.item_count > 0:
		_timeline.select(_canvas.frame_index)
		_duration.set_value_no_signal(document.frame_durations[_canvas.frame_index])
		_tag_from.max_value = document.frame_count()
		_tag_to.max_value = document.frame_count()


func _add_layer() -> void:
	if document.layers.size() >= 32:
		_status.text = Strings.text("EDITOR_LAYER_LIMIT")
		return
	_history.capture(document)
	_canvas.set_layer(document.add_layer("Layer %d" % (document.layers.size() + 1)))
	_rebuild_layers()


func _toggle_layer() -> void:
	_history.capture(document)
	var layer: Dictionary = document.layers[_canvas.layer_index]
	layer["visible"] = not bool(layer.get("visible", true))
	document.dirty = true
	_rebuild_layers()
	_canvas.refresh()


func _toggle_lock() -> void:
	var layer: Dictionary = document.layers[_canvas.layer_index]
	layer["locked"] = not bool(layer.get("locked", false))
	_rebuild_layers()


func _set_layer_opacity(value: float) -> void:
	if document == null:
		return
	Dictionary(document.layers[_canvas.layer_index])["opacity"] = clampf(value, 0.0, 1.0)
	document.dirty = true
	_canvas.refresh()


func _add_frame() -> void:
	if document.frame_count() >= 64:
		_status.text = Strings.text("EDITOR_FRAME_LIMIT")
		return
	_history.capture(document)
	_canvas.set_frame(document.add_frame())
	_rebuild_timeline()


func _duplicate_frame() -> void:
	if document.frame_count() >= 64:
		_status.text = Strings.text("EDITOR_FRAME_LIMIT")
		return
	_history.capture(document)
	_canvas.set_frame(
		document.add_frame(_canvas.frame_index, document.frame_durations[_canvas.frame_index])
	)
	_rebuild_timeline()


func _delete_frame() -> void:
	_history.capture(document)
	if document.remove_frame(_canvas.frame_index):
		_canvas.set_frame(mini(_canvas.frame_index, document.frame_count() - 1))
		_rebuild_timeline()


func _move_frame(direction: int) -> void:
	var target := clampi(_canvas.frame_index + direction, 0, document.frame_count() - 1)
	if target == _canvas.frame_index:
		return
	_history.capture(document)
	document.move_frame(_canvas.frame_index, target)
	_canvas.set_frame(target)
	_rebuild_timeline()


func _set_duration(value: float) -> void:
	if document == null:
		return
	document.frame_durations[_canvas.frame_index] = maxi(1, int(value))
	document.dirty = true
	_rebuild_timeline()


func _undo() -> void:
	if _history.undo(document):
		_rebuild_layers()
		_rebuild_timeline()
		_canvas.refresh()


func _redo() -> void:
	if _history.redo(document):
		_rebuild_layers()
		_rebuild_timeline()
		_canvas.refresh()


func _clean_noise() -> void:
	_history.capture(document)
	var changed := Repair.clean_noise(document.get_frame(_canvas.layer_index, _canvas.frame_index))
	document.dirty = not changed.is_empty() or document.dirty
	_canvas.refresh()
	_status.text = Strings.text("EDITOR_NOISE_RESULT") % changed.size()


func _scan_gaps() -> void:
	var endpoints := Repair.outline_endpoints(document.flatten(_canvas.frame_index))
	_canvas.set_highlights(endpoints)
	_status.text = Strings.text("EDITOR_GAP_RESULT") % endpoints.size()


func _quantize_to_palette() -> void:
	_history.capture(document)
	var image := document.get_frame(_canvas.layer_index, _canvas.frame_index)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a > 0.0:
				image.set_pixel(x, y, Drawing.nearest_palette_color(color, document.palette))
	document.dirty = true
	_canvas.refresh()


func _save(overwrite: bool) -> void:
	var old_id := document.source_asset_id
	var new_ids := []
	for frame_index in range(document.frame_count()):
		var metadata := AssetLibrary.get_asset_meta(old_id)
		var name := String(metadata.get("name", "Edited"))
		var id := old_id if overwrite and frame_index == 0 and document.frame_count() == 1 else ""
		var provenance: Dictionary = metadata.get("provenance", {})
		provenance = provenance.duplicate(true)
		provenance["parent_asset"] = old_id
		var extra := {
			"origin": "edited",
			"provenance": provenance,
			"palette_ref": _project_palette_id(),
			"editor_palette": _palette_hex_values(),
		}
		if not id.is_empty():
			extra["id"] = id
		new_ids.append(
			AssetLibrary.register_image(
				document.flatten(frame_index), "%s Edit %d" % [name, frame_index + 1], extra
			)
		)
	var new_id := String(new_ids[0])
	if document.frame_count() > 1:
		var animation := AnimationScript.new("Edited Animation")
		animation.configure(new_ids, document.frame_durations, true)
		animation.tags = document.tags.duplicate(true)
		if not document.source_animation_id.is_empty():
			animation.id = document.source_animation_id
		ProjectService.set_document_data("animations", animation.id, animation.to_json(), true)
	document.source_asset_id = new_id
	document.dirty = false
	asset_saved.emit(old_id, new_id, source_batch_id)
	_status.text = Strings.text("EDITOR_SAVED")


func _request_close() -> void:
	if document != null and document.dirty:
		_discard_dialog.popup_centered()
	else:
		hide()


func _swap_colors() -> void:
	var color := _canvas.foreground
	_canvas.foreground = _canvas.background
	_canvas.background = color


func _add_palette_color() -> void:
	if document.palette.size() >= 256:
		return
	var color := _canvas.foreground
	if not document.palette.has(color):
		document.palette.append(color)
		document.dirty = true
	_rebuild_palette()


func _delete_palette_color() -> void:
	if _palette_index < 0 or document.palette.size() <= 2:
		return
	document.palette.remove_at(_palette_index)
	_palette_index = -1
	document.dirty = true
	_rebuild_palette()


func _move_palette_color(direction: int) -> void:
	if _palette_index < 0:
		return
	var target := clampi(_palette_index + direction, 0, document.palette.size() - 1)
	if target == _palette_index:
		return
	var color: Color = document.palette.pop_at(_palette_index)
	document.palette.insert(target, color)
	_palette_index = target
	document.dirty = true
	_rebuild_palette()


func _remap_palette_color() -> void:
	if _palette_index < 0:
		return
	var source: Color = document.palette[_palette_index]
	var replacement := _canvas.foreground
	var started := Time.get_ticks_msec()
	_history.capture(document)
	for layer_value in document.layers:
		for frame in Dictionary(layer_value).get("frames", []):
			var image: Image = frame
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					if image.get_pixel(x, y).is_equal_approx(source):
						image.set_pixel(x, y, replacement)
	document.palette[_palette_index] = replacement
	document.dirty = true
	_canvas.refresh()
	_rebuild_palette()
	_status.text = Strings.text("EDITOR_REMAP_RESULT") % (Time.get_ticks_msec() - started)


func _add_tag() -> void:
	var tag_name := _tag_name.text.strip_edges()
	if tag_name.is_empty():
		return
	var from_index := clampi(int(_tag_from.value) - 1, 0, document.frame_count() - 1)
	var to_index := clampi(int(_tag_to.value) - 1, from_index, document.frame_count() - 1)
	document.tags.append({"name": tag_name, "from": from_index, "to": to_index})
	document.dirty = true
	_status.text = Strings.text("EDITOR_TAG_ADDED") % tag_name


func _show_preview() -> void:
	_update_preview()
	_resize_preview()
	_preview_window.popup_centered()


func _update_preview() -> void:
	if document != null and _preview_texture != null:
		_preview_texture.texture = ImageTexture.create_from_image(
			document.flatten(_canvas.frame_index)
		)


func _resize_preview() -> void:
	if document != null:
		_preview_window.size = Vector2i(
			maxi(180, document.size.x * _preview_scale),
			maxi(180, document.size.y * _preview_scale + 40)
		)


func _constrained(color: Color) -> Color:
	return (
		Drawing.nearest_palette_color(color, document.palette)
		if _canvas.constrain_palette
		else color
	)


func _project_palette() -> Array[Color]:
	var palette := PaletteRegistry.resolve({"palette_id": _project_palette_id()})
	var colors: Array[Color] = []
	if palette != null:
		for color in palette.colors:
			colors.append(color)
	return colors


func _project_palette_id() -> String:
	return "db32"


func _palette_hex_values() -> Array:
	var values := []
	for color in document.palette:
		values.append(Color(color).to_html(false).to_upper())
	return values


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_tool_button(parent: Control, text: String, tool_id: String) -> void:
	_add_button(parent, text, func() -> void: _canvas.tool = tool_id)
