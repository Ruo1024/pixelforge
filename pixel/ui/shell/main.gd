class_name PFMain
extends Control

## 应用主窗口。
## UI 只负责命令分发和状态展示；项目状态由 ProjectService 管，画布状态由 PFInfiniteCanvas 管。

const Strings := preload("res://ui/shell/strings.gd")
const InfiniteCanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const FileIOScript := preload("res://infra/file_io.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")

const DEFAULT_WINDOW_WIDTH := 1440
const DEFAULT_WINDOW_HEIGHT := 900
const MIN_WINDOW_WIDTH := 1280
const MIN_WINDOW_HEIGHT := 800
const WINDOW_SCREEN_MARGIN := 80
const UI_FONT_SIZE := 16
const UI_SMALL_FONT_SIZE := 14
const MIN_INTERFACE_SCALE := 1.0
const MAX_INTERFACE_SCALE := 2.0
const RETINA_WIDTH_THRESHOLD := 4800
const RETINA_HEIGHT_THRESHOLD := 2800
const LARGE_DISPLAY_WIDTH_THRESHOLD := 3200
const LARGE_DISPLAY_HEIGHT_THRESHOLD := 1800
const TOP_BAR_HEIGHT := 48
const BOTTOM_BAR_HEIGHT := 32
const TOOLBAR_BUTTON_WIDTH := 84
const TOOLBAR_BUTTON_HEIGHT := 34

var _project_filters := PackedStringArray(["*.pxproj ; PixelForge Project"])
var _ui_scale := 1.0
var _canvas: Control = null
var _title_label: Label = null
var _status_label: Label = null
var _save_dialog: FileDialog = null
var _open_dialog: FileDialog = null
var _recovery_dialog: ConfirmationDialog = null
var _pending_recovery_path := ""


func _ready() -> void:
	_ui_scale = _resolve_interface_scale()
	_apply_viewport_scale_policy()
	_apply_runtime_theme()
	_apply_window_defaults()
	_build_ui()
	_connect_services()
	_update_window_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ProjectService.mark_clean_shutdown()
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.ctrl_pressed and event.keycode == KEY_S:
		_save_current_project()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_O:
		_open_dialog.popup_centered_ratio(0.7)
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_N:
		_create_new_project()
		get_viewport().set_input_as_handled()


static func compute_auto_interface_scale(reported_scale: float, usable_size: Vector2i) -> float:
	var scale := maxf(reported_scale, MIN_INTERFACE_SCALE)
	if scale < 1.25:
		if usable_size.x >= RETINA_WIDTH_THRESHOLD or usable_size.y >= RETINA_HEIGHT_THRESHOLD:
			scale = 2.0
		elif (
			usable_size.x >= LARGE_DISPLAY_WIDTH_THRESHOLD
			or usable_size.y >= LARGE_DISPLAY_HEIGHT_THRESHOLD
		):
			scale = 1.5
	return clampf(scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)


func _resolve_interface_scale() -> float:
	var configured_scale := float(SettingsService.get_setting("ui", "interface_scale", 0.0))
	if configured_scale >= MIN_INTERFACE_SCALE:
		return clampf(configured_scale, MIN_INTERFACE_SCALE, MAX_INTERFACE_SCALE)

	if DisplayServer.get_name() == "headless":
		return MIN_INTERFACE_SCALE

	var screen := DisplayServer.window_get_current_screen()
	var reported_scale := DisplayServer.screen_get_scale(screen)
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	return compute_auto_interface_scale(reported_scale, usable_rect.size)


func _apply_viewport_scale_policy() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = 1.0
	root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _apply_runtime_theme() -> void:
	theme = _build_app_theme()


func _build_app_theme() -> Theme:
	var app_theme := Theme.new()
	app_theme.default_font_size = _scaled_int(UI_FONT_SIZE)

	for type_name in [
		"Button",
		"CheckBox",
		"ConfirmationDialog",
		"FileDialog",
		"ItemList",
		"Label",
		"LineEdit",
		"MenuButton",
		"OptionButton",
		"PopupMenu",
		"TabBar",
		"Tree",
		"Window",
	]:
		app_theme.set_font_size("font_size", type_name, _scaled_int(UI_FONT_SIZE))

	app_theme.set_font_size("font_size", "Button", _scaled_int(UI_SMALL_FONT_SIZE))
	app_theme.set_font_size("font_size", "PopupMenu", _scaled_int(UI_SMALL_FONT_SIZE))
	app_theme.set_constant("h_separation", "HBoxContainer", _scaled_int(8))
	app_theme.set_constant("v_separation", "VBoxContainer", 0)
	return app_theme


func _apply_window_defaults() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return

	window.min_size = _scaled_vec2i(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)
	var target_size := _scaled_vec2i(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT)
	var usable_rect := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable_rect.size.x > 0 and usable_rect.size.y > 0:
		var margin := _scaled_int(WINDOW_SCREEN_MARGIN)
		var max_width := maxi(_scaled_int(960), usable_rect.size.x - margin)
		var max_height := maxi(_scaled_int(640), usable_rect.size.y - margin)
		target_size.x = mini(target_size.x, max_width)
		target_size.y = mini(target_size.y, max_height)
		target_size.x = maxi(target_size.x, mini(window.min_size.x, max_width))
		target_size.y = maxi(target_size.y, mini(window.min_size.y, max_height))

		window.size = target_size
		window.position = usable_rect.position + (usable_rect.size - target_size) / 2
	else:
		window.size = target_size


func _build_ui() -> void:
	custom_minimum_size = _scaled_vec2(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0, _scaled_int(TOP_BAR_HEIGHT))
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(top_bar)

	_title_label = Label.new()
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", _scaled_int(UI_FONT_SIZE))
	top_bar.add_child(_title_label)

	_add_toolbar_button(top_bar, Strings.ACTION_NEW, _create_new_project)
	_add_toolbar_button(
		top_bar, Strings.ACTION_OPEN, func() -> void: _open_dialog.popup_centered_ratio(0.7)
	)
	_add_toolbar_button(top_bar, Strings.ACTION_SAVE, _save_current_project)
	_add_toolbar_button(
		top_bar, Strings.ACTION_SAVE_AS, func() -> void: _save_dialog.popup_centered_ratio(0.7)
	)

	_canvas = InfiniteCanvasScript.new()
	_canvas.name = "InfiniteCanvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_canvas)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.custom_minimum_size = Vector2(0, _scaled_int(BOTTOM_BAR_HEIGHT))
	root.add_child(bottom_bar)

	_status_label = Label.new()
	_status_label.text = Strings.STATUS_READY
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", _scaled_int(UI_SMALL_FONT_SIZE))
	bottom_bar.add_child(_status_label)

	_create_file_dialogs()


func _add_toolbar_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = _scaled_vec2(TOOLBAR_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", _scaled_int(UI_SMALL_FONT_SIZE))
	button.pressed.connect(callback)
	parent.add_child(button)


func _scaled_int(value: int) -> int:
	return maxi(1, int(round(float(value) * _ui_scale)))


func _scaled_vec2(width: int, height: int) -> Vector2:
	return Vector2(_scaled_int(width), _scaled_int(height))


func _scaled_vec2i(width: int, height: int) -> Vector2i:
	return Vector2i(_scaled_int(width), _scaled_int(height))


func _create_file_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.title = Strings.DIALOG_OPEN_PROJECT
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = _project_filters
	_open_dialog.file_selected.connect(_open_project_path)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.title = Strings.DIALOG_SAVE_PROJECT
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = _project_filters
	_save_dialog.file_selected.connect(_save_project_path)
	add_child(_save_dialog)

	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.title = Strings.DIALOG_RECOVERY
	_recovery_dialog.confirmed.connect(_recover_pending_autosave)
	add_child(_recovery_dialog)


func _connect_services() -> void:
	_canvas.canvas_changed.connect(_on_canvas_changed)
	ProjectService.project_loaded.connect(_on_project_loaded)
	ProjectService.project_saved.connect(_on_project_saved)
	ProjectService.dirty_changed.connect(_on_dirty_changed)
	ProjectService.recovery_available.connect(_on_recovery_available)

	var window := get_window()
	if window != null:
		window.files_dropped.connect(_on_files_dropped)


func _create_new_project() -> void:
	ProjectService.new_project("Untitled")
	_canvas.clear_canvas()
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _save_current_project() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	if ProjectService.current_project.project_path.is_empty():
		_save_dialog.current_file = "%s.pxproj" % ProjectService.current_project.get_name()
		_save_dialog.popup_centered_ratio(0.7)
		return

	var error := ProjectService.save_project()
	if error != OK:
		Log.warn("Project save failed", {"error": error})


func _save_project_path(path: String) -> void:
	var target_path := path
	if not target_path.ends_with(".pxproj"):
		target_path += ".pxproj"

	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	var error := ProjectService.save_project(target_path)
	if error != OK:
		Log.warn("Project save failed", {"path": target_path, "error": error})


func _open_project_path(path: String) -> void:
	var error := ProjectService.open_project(path)
	if error != OK:
		Log.warn("Project open failed", {"path": path, "error": error})


func _on_project_loaded(project: Variant) -> void:
	_canvas.load_canvas_data(project.canvas)
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _on_project_saved(_path: String) -> void:
	_status_label.text = Strings.STATUS_SAVED
	_update_window_title()


func _on_dirty_changed(is_dirty: bool) -> void:
	_status_label.text = Strings.STATUS_DIRTY if is_dirty else Strings.STATUS_READY
	_update_window_title()


func _on_canvas_changed() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), true)


func _on_files_dropped(files: PackedStringArray) -> void:
	var drop_position: Vector2 = _canvas.get_mouse_world_position()
	for file_path in files:
		if not String(file_path).to_lower().ends_with(".png"):
			continue

		var image: Image = FileIOScript.load_png(file_path)
		if image == null:
			Log.warn("Dropped PNG could not be loaded", {"path": file_path})
			continue

		if image.get_width() * image.get_height() > 1024 * 1024:
			(
				Log
				. warn(
					"Large PNG imported without M1 cleanup",
					{
						"path": file_path,
						"size": [image.get_width(), image.get_height()],
					}
				)
			)

		var asset_name := String(file_path).get_file().get_basename()
		var asset_id := AssetLibrary.register_image(image, asset_name, {"origin": "imported"})
		_canvas.add_sprite_item(image, asset_id, drop_position)
		drop_position += Vector2(image.get_width() + 8, 0)


func _on_recovery_available(autosaves: Array) -> void:
	if autosaves.is_empty():
		return

	_pending_recovery_path = String(autosaves.back())
	_recovery_dialog.dialog_text = "Autosave found:\n%s" % _pending_recovery_path
	_recovery_dialog.popup_centered()


func _recover_pending_autosave() -> void:
	if _pending_recovery_path.is_empty():
		return
	_open_project_path(_pending_recovery_path)
	_pending_recovery_path = ""


func _update_window_title() -> void:
	var dirty_marker := "*" if ProjectService.current_project.dirty else ""
	var project_name: String = ProjectService.current_project.get_name()
	var title := "%s%s - %s" % [dirty_marker, project_name, AppInfo.APP_NAME]
	_title_label.text = "%s  %s" % [AppInfo.APP_NAME, dirty_marker]

	var window := get_window()
	if window != null:
		window.title = title
