class_name PFMatteDialog
extends ConfirmationDialog

## 抠图参数对话框。
## 输入：一张待预览 Image；输出：Matting.matte 可直接消费的参数 Dictionary。

signal params_confirmed(params: Dictionary)

const Matting := preload("res://core/pixel/matting.gd")
const Strings := preload("res://ui/shell/strings.gd")
const ImageMath := preload("res://core/util/image_math.gd")

const CONTROL_HEIGHT := 30
const PREVIEW_SIZE := 220
const PREVIEW_DEBOUNCE_SECONDS := 0.18

var ui_scale := 1.0

var _source_image: Image = null
var _mode_options: OptionButton = null
var _tolerance_spin: SpinBox = null
var _feather_spin: SpinBox = null
var _preview_texture: TextureRect = null
var _warning_label: Label = null
var _preview_timer: Timer = null
var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	title = Strings.DIALOG_MATTE_TITLE
	ok_button_text = Strings.DIALOG_APPLY
	cancel_button_text = Strings.DIALOG_CANCEL
	min_size = _scaled_vec2i(420, 460)
	_build_ui()
	confirmed.connect(func() -> void: params_confirmed.emit(get_params()))


func set_source_image(image: Image) -> void:
	_source_image = ImageMath.duplicate_rgba8(image) if image != null else null
	_schedule_preview()


func get_params() -> Dictionary:
	return {
		"mode": Matting.MODE_GLOBAL if _mode_options.selected == 1 else Matting.MODE_FLOOD,
		"tolerance": float(_tolerance_spin.value),
		"feather": int(_feather_spin.value),
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", _scaled_int(8))
	add_child(root)

	_mode_options = OptionButton.new()
	_mode_options.add_item(Strings.MATTE_MODE_FLOOD)
	_mode_options.add_item(Strings.MATTE_MODE_GLOBAL)
	_add_labeled_control(root, Strings.MATTE_LABEL_MODE, _mode_options)

	_tolerance_spin = _make_spin(0.0, 100.0, 1.0, Matting.DEFAULT_TOLERANCE)
	_add_labeled_control(root, Strings.MATTE_LABEL_TOLERANCE, _tolerance_spin)

	_feather_spin = _make_spin(0.0, 8.0, 1.0, Matting.DEFAULT_FEATHER)
	_add_labeled_control(root, Strings.MATTE_LABEL_FEATHER, _feather_spin)

	_preview_texture = TextureRect.new()
	_preview_texture.custom_minimum_size = _scaled_vec2(PREVIEW_SIZE, PREVIEW_SIZE)
	_preview_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(_preview_texture)

	_warning_label = Label.new()
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25, 1.0))
	root.add_child(_warning_label)

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = PREVIEW_DEBOUNCE_SECONDS
	_preview_timer.timeout.connect(_update_preview)
	add_child(_preview_timer)

	_mode_options.item_selected.connect(func(_index: int) -> void: _schedule_preview())
	_tolerance_spin.value_changed.connect(func(_value: float) -> void: _schedule_preview())
	_feather_spin.value_changed.connect(func(_value: float) -> void: _schedule_preview())


func _add_labeled_control(parent: Control, label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", _scaled_int(2))
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.custom_minimum_size = Vector2(0, _scaled_int(CONTROL_HEIGHT))
	row.add_child(control)
	parent.add_child(row)


func _make_spin(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	return spin


func _schedule_preview() -> void:
	if _preview_timer != null:
		_preview_timer.start()


func _update_preview() -> void:
	if _source_image == null or _preview_texture == null:
		return
	var preview_source := _make_preview_source(_source_image)
	var result: Dictionary = Matting.matte(preview_source, get_params())
	var image: Image = result.get("image", preview_source)
	_preview_texture.texture = ImageTexture.create_from_image(image)
	var warning := String(result.get("warning", ""))
	_warning_label.text = (
		Strings.MATTE_WARNING_NON_FLAT_BACKGROUND if warning == "non_flat_background" else ""
	)


func _make_preview_source(image: Image) -> Image:
	var preview := ImageMath.duplicate_rgba8(image)
	var longest := maxi(preview.get_width(), preview.get_height())
	if longest > PREVIEW_SIZE:
		var ratio := float(PREVIEW_SIZE) / float(longest)
		preview.resize(
			maxi(1, int(round(preview.get_width() * ratio))),
			maxi(1, int(round(preview.get_height() * ratio))),
			Image.INTERPOLATE_NEAREST
		)
	return preview


func _scaled_int(value: int) -> int:
	return maxi(1, int(round(float(value) * maxf(ui_scale, 1.0))))


func _scaled_vec2(width: int, height: int) -> Vector2:
	return Vector2(_scaled_int(width), _scaled_int(height))


func _scaled_vec2i(width: int, height: int) -> Vector2i:
	return Vector2i(_scaled_int(width), _scaled_int(height))
