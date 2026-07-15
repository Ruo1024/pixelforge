class_name PFResponsiveTopBar
extends HBoxContainer

## One shell breakpoint controls title width and low-priority toolbar labels together.

signal layout_mode_changed(mode: String)

const COMPACT_BREAKPOINT := 1180.0
const TITLE_COMPACT_WIDTH := 120.0
const TITLE_STANDARD_WIDTH := 280.0

var _title: Label = null
var _adaptive_buttons: Array[Button] = []
var _compact_controls: Array[Dictionary] = []
var _layout_mode := "standard"
var _applying := false
var _layout_initialized := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		refresh_layout()


func setup_title(title: Label) -> void:
	_title = title
	refresh_layout()


func register_adaptive_button(button: Button) -> void:
	if button == null or _adaptive_buttons.has(button):
		return
	_adaptive_buttons.append(button)
	refresh_layout()


func register_compact_control(
	control: Control, standard_width: float, compact_width: float
) -> void:
	if control == null:
		return
	for spec in _compact_controls:
		if spec["control"] == control:
			return
	_compact_controls.append(
		{"control": control, "standard_width": standard_width, "compact_width": compact_width}
	)
	refresh_layout()


func refresh_layout() -> void:
	if _applying:
		return
	_applying = true
	var next_mode := "compact" if size.x <= COMPACT_BREAKPOINT else "standard"
	var compact := next_mode == "compact"
	var layout_changed := not _layout_initialized or next_mode != _layout_mode
	var title_width := TITLE_COMPACT_WIDTH if compact else TITLE_STANDARD_WIDTH
	if _title != null:
		if not is_equal_approx(_title.custom_minimum_size.x, title_width):
			_title.custom_minimum_size.x = title_width
			layout_changed = true
	for button in _adaptive_buttons:
		if is_instance_valid(button):
			if bool(button.get("compact")) != compact:
				button.call("set_compact", compact)
				layout_changed = true
	for spec in _compact_controls:
		var control: Control = spec["control"]
		if not is_instance_valid(control):
			continue
		var requested_width := float(spec["compact_width"] if compact else spec["standard_width"])
		if not is_equal_approx(control.custom_minimum_size.x, requested_width):
			control.custom_minimum_size.x = requested_width
			layout_changed = true
	set_meta("layout_mode", next_mode)
	if next_mode != _layout_mode:
		_layout_mode = next_mode
		layout_mode_changed.emit(_layout_mode)
	_layout_initialized = true
	_applying = false
	if layout_changed:
		queue_sort()


func get_layout_mode() -> String:
	return _layout_mode
