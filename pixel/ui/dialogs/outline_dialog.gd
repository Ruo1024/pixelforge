class_name PFOutlineDialog
extends ConfirmationDialog

## 描边参数对话框。
## 输出 Outliner.add_outline 可直接消费的参数 Dictionary。

signal params_confirmed(params: Dictionary)

const Outliner := preload("res://core/pixel/outliner.gd")
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
var _type_options: OptionButton = null
var _corner_options: OptionButton = null
var _colored_check: CheckBox = null
var _color_picker: ColorPickerButton = null
var _preview_texture: TextureRect = null
var _preview_timer: Timer = null
var _built := false


func _ready() -> void:
	if _built:
		return
	_built = true
	title = Strings.text("DIALOG_OUTLINE_TITLE")
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
		"type": Outliner.TYPE_INNER if _type_options.selected == 1 else Outliner.TYPE_OUTER,
		"corner":
		Outliner.CORNER_SQUARE if _corner_options.selected == 1 else Outliner.CORNER_CROSS,
		"colored": _colored_check.button_pressed,
		"color": _color_picker.color,
	}


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(root)

	_type_options = OptionButton.new()
	_type_options.add_item(Strings.text("OUTLINE_TYPE_OUTER"))
	_type_options.add_item(Strings.text("OUTLINE_TYPE_INNER"))
	_add_labeled_control(root, Strings.text("OUTLINE_LABEL_TYPE"), _type_options)

	_corner_options = OptionButton.new()
	_corner_options.add_item(Strings.text("OUTLINE_CORNER_CROSS"))
	_corner_options.add_item(Strings.text("OUTLINE_CORNER_SQUARE"))
	_add_labeled_control(root, Strings.text("OUTLINE_LABEL_CORNER"), _corner_options)

	_colored_check = CheckBox.new()
	_colored_check.text = Strings.text("OUTLINE_COLORED")
	root.add_child(_colored_check)

	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color.BLACK
	_add_labeled_control(root, Strings.text("OUTLINE_LABEL_COLOR"), _color_picker)

	_preview_texture = TextureRect.new()
	_preview_texture.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	_preview_texture.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(_preview_texture)

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = PREVIEW_DEBOUNCE_SECONDS
	_preview_timer.timeout.connect(_update_preview)
	add_child(_preview_timer)

	_type_options.item_selected.connect(func(_index: int) -> void: _schedule_preview())
	_corner_options.item_selected.connect(func(_index: int) -> void: _schedule_preview())
	_colored_check.toggled.connect(func(_pressed: bool) -> void: _schedule_preview())
	_color_picker.color_changed.connect(func(_color: Color) -> void: _schedule_preview())


func _add_labeled_control(parent: Control, label_text: String, control: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	control.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, CONTROL_HEIGHT)
	row.add_child(control)
	parent.add_child(row)


func _schedule_preview() -> void:
	if _preview_timer != null:
		_preview_timer.start()


func _update_preview() -> void:
	if _source_image == null or _preview_texture == null:
		return
	var preview_source := _make_preview_source(_source_image)
	var preview := Outliner.add_outline(preview_source, get_params())
	_preview_texture.texture = ImageTexture.create_from_image(preview)


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
