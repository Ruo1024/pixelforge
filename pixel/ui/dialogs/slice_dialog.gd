class_name PFSliceDialog
extends ConfirmationDialog

## 切分参数对话框。
## 预览只画组件 bbox，不修改素材；真正切分仍由 M2ActionController 异步执行。

signal params_confirmed(params: Dictionary)

const Matting := preload("res://core/pixel/matting.gd")
const Segmenter := preload("res://core/pixel/segmenter.gd")
const Strings := preload("res://ui/shell/strings.gd")
const ImageMath := preload("res://core/util/image_math.gd")

const CONTROL_HEIGHT := 30
const DIALOG_WIDTH := 420
const DIALOG_HEIGHT := 500
const PREVIEW_SIZE := 220
const PREVIEW_DEBOUNCE_SECONDS := 0.18
const ROOT_SEPARATION := 8
const ROW_SEPARATION := 2
const FLEXIBLE_WIDTH := 0

var _source_image: Image = null
var _auto_matte_check: CheckBox = null
var _matte_tolerance_spin: SpinBox = null
var _merge_spin: SpinBox = null
var _min_area_spin: SpinBox = null
var _preview_texture: TextureRect = null
var _count_label: Label = null
var _preview_timer: Timer = null
var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	title = Strings.text("DIALOG_SLICE_TITLE")
	ok_button_text = Strings.text("DIALOG_APPLY")
	cancel_button_text = Strings.text("DIALOG_CANCEL")
	min_size = Vector2i(DIALOG_WIDTH, DIALOG_HEIGHT)
	_build_ui()
	confirmed.connect(func() -> void: params_confirmed.emit(get_params()))


func set_source_image(image: Image) -> void:
	_source_image = ImageMath.duplicate_rgba8(image) if image != null else null
	_schedule_preview()


func get_params() -> Dictionary:
	return {
		"matte_first": _auto_matte_check.button_pressed,
		"matte_params":
		{
			"mode": Matting.MODE_FLOOD,
			"tolerance": float(_matte_tolerance_spin.value),
			"feather": 0,
		},
		"segment_params":
		{
			"merge_distance": int(_merge_spin.value),
			"min_area": int(_min_area_spin.value),
		},
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(root)

	_auto_matte_check = CheckBox.new()
	_auto_matte_check.text = Strings.text("SLICE_AUTO_MATTE")
	_auto_matte_check.button_pressed = true
	root.add_child(_auto_matte_check)

	_matte_tolerance_spin = _make_spin(0.0, 100.0, 1.0, 12.0)
	_add_labeled_control(root, Strings.text("MATTE_LABEL_TOLERANCE"), _matte_tolerance_spin)

	_merge_spin = _make_spin(0.0, 32.0, 1.0, Segmenter.DEFAULT_MERGE_DISTANCE)
	_add_labeled_control(root, Strings.text("SLICE_LABEL_MERGE_DISTANCE"), _merge_spin)

	_min_area_spin = _make_spin(1.0, 4096.0, 1.0, Segmenter.DEFAULT_MIN_AREA)
	_add_labeled_control(root, Strings.text("SLICE_LABEL_MIN_AREA"), _min_area_spin)

	_preview_texture = TextureRect.new()
	_preview_texture.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_preview_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(_preview_texture)

	_count_label = Label.new()
	root.add_child(_count_label)

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = PREVIEW_DEBOUNCE_SECONDS
	_preview_timer.timeout.connect(_update_preview)
	add_child(_preview_timer)

	_auto_matte_check.toggled.connect(func(_pressed: bool) -> void: _schedule_preview())
	_matte_tolerance_spin.value_changed.connect(func(_value: float) -> void: _schedule_preview())
	_merge_spin.value_changed.connect(func(_value: float) -> void: _schedule_preview())
	_min_area_spin.value_changed.connect(func(_value: float) -> void: _schedule_preview())


func _add_labeled_control(parent: Control, label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
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
	var params := get_params()
	var segment_source := preview_source
	if bool(params.get("matte_first", true)):
		var matte_result: Dictionary = Matting.matte(preview_source, params["matte_params"])
		if bool(matte_result.get("is_flat_bg", false)):
			segment_source = matte_result["image"]
	var segments: Array = Segmenter.segment(segment_source, params["segment_params"])
	var preview := ImageMath.duplicate_rgba8(segment_source)
	for segment in segments:
		_draw_rect_outline(preview, segment["rect"], Color(1.0, 0.82, 0.16, 1.0))
	_preview_texture.texture = ImageTexture.create_from_image(preview)
	_count_label.text = Strings.text("SLICE_PREVIEW_COUNT_FORMAT") % segments.size()


func _draw_rect_outline(image: Image, rect: Rect2i, color: Color) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var x0 := clampi(rect.position.x, 0, image.get_width() - 1)
	var y0 := clampi(rect.position.y, 0, image.get_height() - 1)
	var x1 := clampi(rect.position.x + rect.size.x - 1, 0, image.get_width() - 1)
	var y1 := clampi(rect.position.y + rect.size.y - 1, 0, image.get_height() - 1)
	for x in range(x0, x1 + 1):
		image.set_pixel(x, y0, color)
		image.set_pixel(x, y1, color)
	for y in range(y0, y1 + 1):
		image.set_pixel(x0, y, color)
		image.set_pixel(x1, y, color)


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
