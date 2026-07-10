class_name PFCleanupInspector
extends PanelContainer

## 像素清洗检查器。
## UI 只收集参数并展示报告；实际算法由 core/pixel/pipeline.gd 执行。

signal apply_requested(params: Dictionary)
signal preview_requested(params: Dictionary)
signal cancel_requested
signal manual_grid_changed(active: bool, scale: float, offset: Vector2)
signal custom_palettes_changed

const Pipeline := preload("res://core/pixel/pipeline.gd")
const Resampler := preload("res://core/pixel/resampler.gd")
const Quantizer := preload("res://core/pixel/quantizer.gd")
const Ditherer := preload("res://core/pixel/ditherer.gd")
const PaletteRegistry := preload("res://core/pixel/palette_registry.gd")
const Strings := preload("res://ui/shell/strings.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")

const PANEL_WIDTH := 420
const CONTROL_HEIGHT := 30
const PREVIEW_DEBOUNCE_SECONDS := 0.3
const RESAMPLE_LABELS := ["Mode", "Center", "Median", "Edge Aware"]
const RESAMPLE_VALUES := [
	Resampler.MODE_MODE,
	Resampler.MODE_CENTER,
	Resampler.MODE_MEDIAN,
	Resampler.MODE_EDGE_AWARE,
]
const QUANTIZE_LABELS := ["Auto K", "Fixed Palette", "None"]
const QUANTIZE_VALUES := [Quantizer.MODE_AUTO_K, Quantizer.MODE_FIXED_PALETTE, Quantizer.MODE_NONE]
const AUTO_K_STRATEGY_LABELS := ["Median Cut", "K-means"]
const AUTO_K_STRATEGY_VALUES := [
	Quantizer.AUTO_K_STRATEGY_MEDIAN_CUT,
	Quantizer.AUTO_K_STRATEGY_KMEANS,
]
const DITHER_LABELS := ["None", "Bayer 2", "Bayer 4", "Bayer 8", "Chromatic", "Error Diffusion"]
const DITHER_VALUES := [
	Ditherer.MODE_NONE,
	Ditherer.MODE_BAYER2,
	Ditherer.MODE_BAYER4,
	Ditherer.MODE_BAYER8,
	Ditherer.MODE_CHROMATIC,
	Ditherer.MODE_ERROR_DIFFUSION,
]
const IMPORT_PALETTE_ID := "__import_custom_palette__"
const PALETTE_PREVIEW_WIDTH := 192
const PALETTE_PREVIEW_HEIGHT := 18
const TITLE_FONT_SIZE := 16
const LABEL_FONT_SIZE := 13
const PRIOR_FONT_SIZE := 12
const ROOT_SEPARATION := 8
const ROW_SEPARATION := 2
const FLEXIBLE_WIDTH := 0

var _selection_label: Label = null
var _auto_detect_check: CheckBox = null
var _resample_check: CheckBox = null
var _quantize_check: CheckBox = null
var _scale_spin: SpinBox = null
var _offset_x_spin: SpinBox = null
var _offset_y_spin: SpinBox = null
var _resample_options: OptionButton = null
var _quantize_options: OptionButton = null
var _auto_k_strategy_options: OptionButton = null
var _auto_k_strategy_row: Control = null
var _palette_options: OptionButton = null
var _palette_preview: TextureRect = null
var _delete_palette_button: Button = null
var _k_spin: SpinBox = null
var _dither_options: OptionButton = null
var _strength_slider: HSlider = null
var _chroma_slider: HSlider = null
var _density_slider: HSlider = null
var _report_label: Label = null
var _apply_button: Button = null
var _cancel_button: Button = null
var _preview_timer: Timer = null
var _palette_import_dialog: FileDialog = null
var _palette_error_dialog: AcceptDialog = null
var _style_prior_label: Label = null
var _palette_ids := []
var _last_palette_id := "db32"
var _suppress_param_signal := false


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_build_ui()
	set_selection_count(0)


func get_params() -> Dictionary:
	var offset := Vector2(_offset_x_spin.value, _offset_y_spin.value)
	return {
		Pipeline.STEP_DETECT_GRID:
		{
			"enabled": true,
			"mode":
			Pipeline.DETECT_AUTO if _auto_detect_check.button_pressed else Pipeline.DETECT_MANUAL,
			"scale": _scale_spin.value,
			"offset": offset,
		},
		Pipeline.STEP_RESAMPLE:
		{
			"enabled": _resample_check.button_pressed,
			"mode": _selected_value(_resample_options, RESAMPLE_VALUES),
			"scale": _scale_spin.value,
			"offset": offset,
		},
		Pipeline.STEP_QUANTIZE:
		{
			"enabled": _quantize_check.button_pressed,
			"mode": _selected_value(_quantize_options, QUANTIZE_VALUES),
			"palette_id": _selected_palette_id(),
			"auto_k_strategy": _selected_value(_auto_k_strategy_options, AUTO_K_STRATEGY_VALUES),
			"k": int(_k_spin.value),
			"dither": _selected_value(_dither_options, DITHER_VALUES),
			"dither_strength": _strength_slider.value,
			"dither_contrast": _strength_slider.value,
			"dither_chroma": _chroma_slider.value,
			"dither_density": _density_slider.value,
		},
	}


func set_selection_count(count: int) -> void:
	if _selection_label == null:
		return
	_selection_label.text = Strings.CLEANUP_SELECTED_FORMAT % count
	_apply_button.disabled = count <= 0
	_schedule_preview()
	_emit_manual_grid_changed()


func set_cleanup_running(running: bool) -> void:
	if _apply_button != null:
		_apply_button.disabled = running
	if _cancel_button != null:
		_cancel_button.disabled = not running


func cancel_pending_preview() -> void:
	if _preview_timer != null:
		_preview_timer.stop()


func set_manual_grid_from_overlay(scale: float, offset: Vector2) -> void:
	_suppress_param_signal = true
	_scale_spin.value = scale
	_offset_x_spin.value = offset.x
	_offset_y_spin.value = offset.y
	_suppress_param_signal = false
	_schedule_preview()


func set_style_preset(style_preset: Dictionary) -> void:
	if _style_prior_label == null:
		return

	var base_size := int(style_preset.get("base_size", 0))
	_style_prior_label.visible = base_size > 0
	_style_prior_label.text = Strings.CLEANUP_PRESET_PRIOR_FORMAT % base_size

	var quantize: Dictionary = get_params().get(Pipeline.STEP_QUANTIZE, {})
	var palette_data: Variant = style_preset.get("palette", {})
	if palette_data is Dictionary:
		var palette_ref := String(Dictionary(palette_data).get("ref", ""))
		if not palette_ref.is_empty():
			refresh_palette_options(palette_ref)
	if style_preset.has("max_colors_per_sprite"):
		_k_spin.value = int(style_preset["max_colors_per_sprite"])
	if style_preset.has("auto_k_strategy"):
		_select_option_value(
			_auto_k_strategy_options,
			AUTO_K_STRATEGY_VALUES,
			Quantizer.normalize_auto_k_strategy(style_preset["auto_k_strategy"])
		)
	_update_quantize_visibility()
	if not quantize.is_empty():
		_schedule_preview()


func refresh_palette_options(preferred_id: String = "") -> void:
	if _palette_options == null:
		return

	var selected_id := preferred_id
	if selected_id.is_empty():
		selected_id = _selected_palette_id()

	_palette_options.clear()
	_palette_ids.clear()
	for palette_id in PaletteRegistry.get_builtin_ids():
		_palette_options.add_item(PaletteRegistry.get_palette_name(String(palette_id)))
		_palette_ids.append(String(palette_id))

	for palette_id in PaletteRegistry.get_custom_ids():
		_palette_options.add_item(
			(
				Strings.CLEANUP_CUSTOM_PALETTE_PREFIX
				% PaletteRegistry.get_palette_name(String(palette_id))
			)
		)
		_palette_ids.append(String(palette_id))

	_palette_options.add_item(Strings.CLEANUP_IMPORT_PALETTE_ITEM)
	_palette_ids.append(IMPORT_PALETTE_ID)

	var selected_index := _palette_ids.find(selected_id)
	if selected_index < 0:
		selected_index = max(0, _palette_ids.find("db32"))
	_palette_options.select(selected_index)
	_last_palette_id = _selected_palette_id()
	_update_palette_controls()


func show_report(report: Dictionary) -> void:
	if _report_label == null or report.is_empty():
		return
	var detect: Dictionary = report.get("detect", {})
	var quantize: Dictionary = report.get("quantize", {})
	var warning := (
		Strings.CLEANUP_NON_SQUARE_WARNING if bool(detect.get("non_square_warning", false)) else ""
	)
	_report_label.text = (
		Strings.CLEANUP_REPORT_FORMAT
		% [
			float(detect.get("scale", 0.0)),
			float(detect.get("confidence", 0.0)),
			int(quantize.get("color_count", 0)),
			str(report.get("output_size", [])),
			warning,
		]
	)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "InspectorRoot"
	root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(root)

	var title := Label.new()
	title.text = Strings.CLEANUP_TITLE
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	root.add_child(title)

	_selection_label = Label.new()
	root.add_child(_selection_label)

	var scroll := ScrollContainer.new()
	scroll.name = "CleanupScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var controls := VBoxContainer.new()
	controls.name = "CleanupControls"
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", ROOT_SEPARATION)
	scroll.add_child(controls)

	_auto_detect_check = _make_check(Strings.CLEANUP_AUTO_DETECT, true)
	controls.add_child(_auto_detect_check)

	_style_prior_label = Label.new()
	_style_prior_label.add_theme_font_size_override("font_size", PRIOR_FONT_SIZE)
	_style_prior_label.visible = false
	controls.add_child(_style_prior_label)

	_resample_check = _make_check(Strings.CLEANUP_RUN_RESAMPLE, true)
	controls.add_child(_resample_check)

	_quantize_check = _make_check(Strings.CLEANUP_RUN_QUANTIZE, true)
	controls.add_child(_quantize_check)

	_scale_spin = _make_spin(1.0, 64.0, 0.1, 4.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_SCALE, _scale_spin)

	_offset_x_spin = _make_spin(0.0, 64.0, 0.25, 0.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_OFFSET_X, _offset_x_spin)

	_offset_y_spin = _make_spin(0.0, 64.0, 0.25, 0.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_OFFSET_Y, _offset_y_spin)

	_resample_options = _make_options(RESAMPLE_LABELS)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_RESAMPLE, _resample_options)

	_quantize_options = _make_options(QUANTIZE_LABELS)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_QUANTIZE, _quantize_options)

	_auto_k_strategy_options = _make_options(AUTO_K_STRATEGY_LABELS)
	_auto_k_strategy_options.tooltip_text = Strings.CLEANUP_AUTO_K_TOOLTIP
	_auto_k_strategy_row = _add_labeled_control(
		controls, Strings.CLEANUP_LABEL_AUTO_K_STRATEGY, _auto_k_strategy_options
	)

	_palette_options = _make_options([])
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_PALETTE, _palette_options)
	refresh_palette_options("db32")

	_palette_preview = TextureRect.new()
	_palette_preview.custom_minimum_size = Vector2(PALETTE_PREVIEW_WIDTH, PALETTE_PREVIEW_HEIGHT)
	_palette_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	controls.add_child(_palette_preview)

	_delete_palette_button = Button.new()
	_delete_palette_button.text = Strings.CLEANUP_DELETE_PALETTE
	_delete_palette_button.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	_delete_palette_button.disabled = true
	_delete_palette_button.pressed.connect(_delete_selected_custom_palette)
	controls.add_child(_delete_palette_button)
	_update_palette_controls()

	_k_spin = _make_spin(2.0, 256.0, 1.0, 16.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_MAX_COLORS, _k_spin)

	_dither_options = _make_options(DITHER_LABELS)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_DITHER, _dither_options)

	_strength_slider = _make_slider(0.0, 1.0, 0.05, 0.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_STRENGTH, _strength_slider)

	_chroma_slider = _make_slider(0.0, 0.25, 0.01, 0.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_CHROMA, _chroma_slider)

	_density_slider = _make_slider(0.0, 1.0, 0.05, 1.0)
	_add_labeled_control(controls, Strings.CLEANUP_LABEL_DENSITY, _density_slider)

	_report_label = Label.new()
	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_label.text = Strings.CLEANUP_NO_REPORT
	controls.add_child(_report_label)

	var action_row := HBoxContainer.new()
	action_row.name = "CleanupActions"
	action_row.add_theme_constant_override("separation", ROOT_SEPARATION)
	root.add_child(action_row)

	_apply_button = Button.new()
	_apply_button.name = "ApplyCleanupButton"
	_apply_button.text = Strings.CLEANUP_APPLY
	_apply_button.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_button.pressed.connect(func() -> void: apply_requested.emit(get_params()))
	action_row.add_child(_apply_button)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelCleanupButton"
	_cancel_button.text = Strings.CLEANUP_CANCEL
	_cancel_button.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.disabled = true
	_cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	action_row.add_child(_cancel_button)

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = PREVIEW_DEBOUNCE_SECONDS
	_preview_timer.timeout.connect(func() -> void: preview_requested.emit(get_params()))
	add_child(_preview_timer)
	_create_palette_dialogs()
	_connect_param_controls()
	_update_quantize_visibility()


func _add_labeled_control(parent: Control, label_text: String, control: Control) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	row.add_child(label)
	row.add_child(control)
	parent.add_child(row)
	return row


func _make_check(text: String, pressed: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	return check


func _make_spin(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	return spin


func _make_slider(minimum: float, maximum: float, step: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	return slider


func _make_options(labels: Array) -> OptionButton:
	var options := OptionButton.new()
	options.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	for label in labels:
		options.add_item(String(label))
	return options


func _create_palette_dialogs() -> void:
	_palette_import_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_palette_import_dialog)
	_palette_import_dialog.title = Strings.DIALOG_IMPORT_PALETTE
	_palette_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_palette_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_palette_import_dialog.filters = PackedStringArray(["*.json ; Palette JSON"])
	_palette_import_dialog.file_selected.connect(_on_palette_file_selected)
	add_child(_palette_import_dialog)

	_palette_error_dialog = AcceptDialog.new()
	_palette_error_dialog.title = Strings.DIALOG_PALETTE_ERROR
	add_child(_palette_error_dialog)


func _selected_value(options: OptionButton, values: Array) -> String:
	var index := clampi(options.selected, 0, values.size() - 1)
	return String(values[index])


func _select_option_value(options: OptionButton, values: Array, value: String) -> void:
	var index := values.find(value)
	if index >= 0:
		options.select(index)


func _selected_palette_id() -> String:
	if _palette_ids.is_empty():
		return _last_palette_id
	var index := clampi(_palette_options.selected, 0, _palette_ids.size() - 1)
	var palette_id := String(_palette_ids[index])
	if palette_id == IMPORT_PALETTE_ID:
		return _last_palette_id
	return palette_id


func _on_palette_file_selected(path: String) -> void:
	var result := PaletteRegistry.import_custom_from_path(path)
	if not bool(result.get("ok", false)):
		_show_palette_error(String(result.get("error", Strings.PALETTE_IMPORT_FAILED)))
		return

	var palette: PFPalette = result["palette"]
	refresh_palette_options(palette.id)
	custom_palettes_changed.emit()
	_schedule_preview()


func _delete_selected_custom_palette() -> void:
	var palette_id := _selected_palette_id()
	if not PaletteRegistry.unregister_custom_palette(palette_id):
		return
	refresh_palette_options("db32")
	custom_palettes_changed.emit()
	_schedule_preview()


func _show_palette_error(message: String) -> void:
	if _palette_error_dialog == null:
		return
	_palette_error_dialog.dialog_text = message
	_palette_error_dialog.popup_centered()


func _update_palette_controls() -> void:
	var palette_id := _selected_palette_id()
	if not palette_id.is_empty():
		_last_palette_id = palette_id
	if _delete_palette_button != null:
		_delete_palette_button.disabled = not PaletteRegistry.is_custom_palette(palette_id)
	_update_palette_preview(palette_id)


func _update_palette_preview(palette_id: String) -> void:
	if _palette_preview == null:
		return

	var palette: PFPalette = PaletteRegistry.resolve({"palette_id": palette_id})
	if palette == null or palette.colors.is_empty():
		_palette_preview.texture = null
		return

	var image := Image.create(
		PALETTE_PREVIEW_WIDTH, PALETTE_PREVIEW_HEIGHT, false, Image.FORMAT_RGBA8
	)
	for x in range(PALETTE_PREVIEW_WIDTH):
		var color_index := int(
			floor(float(x) / float(PALETTE_PREVIEW_WIDTH) * palette.colors.size())
		)
		color_index = clampi(color_index, 0, palette.colors.size() - 1)
		for y in range(PALETTE_PREVIEW_HEIGHT):
			image.set_pixel(x, y, palette.colors[color_index])
	_palette_preview.texture = ImageTexture.create_from_image(image)


func _update_quantize_visibility() -> void:
	if _auto_k_strategy_row == null:
		return
	var quantize_mode := _selected_value(_quantize_options, QUANTIZE_VALUES)
	_auto_k_strategy_row.visible = quantize_mode == Quantizer.MODE_AUTO_K


func _connect_param_controls() -> void:
	_auto_detect_check.toggled.connect(func(_pressed: bool) -> void: _on_params_changed())
	_resample_check.toggled.connect(func(_pressed: bool) -> void: _on_params_changed())
	_quantize_check.toggled.connect(func(_pressed: bool) -> void: _on_params_changed())
	_scale_spin.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_offset_x_spin.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_offset_y_spin.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_resample_options.item_selected.connect(func(_index: int) -> void: _on_params_changed())
	_quantize_options.item_selected.connect(func(_index: int) -> void: _on_params_changed())
	_auto_k_strategy_options.item_selected.connect(func(_index: int) -> void: _on_params_changed())
	_palette_options.item_selected.connect(_on_palette_option_selected)
	_k_spin.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_dither_options.item_selected.connect(func(_index: int) -> void: _on_params_changed())
	_strength_slider.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_chroma_slider.value_changed.connect(func(_value: float) -> void: _on_params_changed())
	_density_slider.value_changed.connect(func(_value: float) -> void: _on_params_changed())


func _on_params_changed() -> void:
	if _suppress_param_signal:
		return
	_update_quantize_visibility()
	_schedule_preview()
	_emit_manual_grid_changed()


func _on_palette_option_selected(index: int) -> void:
	if index >= 0 and index < _palette_ids.size() and _palette_ids[index] == IMPORT_PALETTE_ID:
		var previous_index := _palette_ids.find(_last_palette_id)
		if previous_index >= 0:
			_palette_options.select(previous_index)
		_palette_import_dialog.popup_centered_ratio(0.6)
		return

	_update_palette_controls()
	_on_params_changed()


func _schedule_preview() -> void:
	if _preview_timer == null:
		return
	_preview_timer.start()


func _emit_manual_grid_changed() -> void:
	if _auto_detect_check == null:
		return
	manual_grid_changed.emit(
		not _auto_detect_check.button_pressed,
		float(_scale_spin.value),
		Vector2(_offset_x_spin.value, _offset_y_spin.value)
	)
