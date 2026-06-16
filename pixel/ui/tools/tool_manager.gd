class_name PFToolManager
extends RefCounted

## 画布工具状态机。
## 管理当前工具、共享像素选区和撤销；具体像素算法仍在 core/pixel/selection.gd。

signal tool_changed(tool_id: String)
signal selection_changed(selection: PFSelection)

const BaseTool := preload("res://ui/tools/base_tool.gd")

var _tools := {}
var _tool_order: Array[String] = []
var _current_tool: PFTool = null
var _current_tool_id := ""
var _current_selection: PFSelection = null
var _last_target_item_id := ""


func register_tool(tool_id: String, tool: PFTool) -> void:
	_tools[tool_id] = tool
	if not _tool_order.has(tool_id):
		_tool_order.append(tool_id)
	tool.selection_committed.connect(_on_tool_selection_committed)


func set_active_tool(tool_id: String) -> void:
	if not _tools.has(tool_id):
		return
	if _current_tool != null:
		_current_tool.on_deactivate()
	_current_tool_id = tool_id
	_current_tool = _tools[tool_id]
	_current_tool.set_current_selection(_current_selection)
	_current_tool.on_activate()
	tool_changed.emit(tool_id)


func get_active_tool_id() -> String:
	return _current_tool_id


func get_current_tool() -> PFTool:
	return _current_tool


func get_tool_ids() -> Array:
	return _tool_order.duplicate()


func handle_shortcut(keycode: Key) -> bool:
	for tool_id in _tool_order:
		var tool: PFTool = _tools[tool_id]
		if tool.wants_keyboard_shortcut(keycode):
			set_active_tool(tool_id)
			return true
	return false


func clear_selection(record_undo: bool = true) -> void:
	if _current_selection == null:
		return
	_commit_selection_state(null, record_undo)


func handle_canvas_input(event: InputEvent, canvas: Control, target: Dictionary) -> bool:
	if _current_tool == null:
		return false
	if target.is_empty():
		return false
	if event is InputEventMouseButton:
		return _handle_mouse_button(event, canvas, target)
	if event is InputEventMouseMotion:
		_sync_target(target)
		_current_tool.on_mouse_move(_image_pos_from_screen(canvas, target, event.position))
		return _current_tool.needs_redraw()
	return false


func draw_overlay(canvas: Control, target: Dictionary) -> void:
	if _current_tool == null or target.is_empty():
		return
	_sync_target(target)
	_current_tool.draw_overlay(canvas, target)


func needs_redraw() -> bool:
	return _current_tool != null and _current_tool.needs_redraw()


func _handle_mouse_button(
	event: InputEventMouseButton, canvas: Control, target: Dictionary
) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		return true
	_sync_target(target)
	var image_pos := _image_pos_from_screen(canvas, target, event.position)
	var modifiers := _modifiers_from_event(event)
	if event.pressed:
		_current_tool.on_mouse_press(image_pos, event.button_index, modifiers)
	else:
		_current_tool.on_mouse_release(image_pos, event.button_index, modifiers)
	return true


func _sync_target(target: Dictionary) -> void:
	var target_item_id := String(target.get("item_id", ""))
	var image: Image = target.get("image", null)
	if target_item_id != _last_target_item_id:
		_last_target_item_id = target_item_id
		_commit_selection_state(null, false)
	_current_tool.set_source_image(image)


func _image_pos_from_screen(canvas: Control, target: Dictionary, screen_pos: Vector2) -> Vector2i:
	var world_pos: Vector2 = canvas.screen_to_world(screen_pos)
	var world_origin := Vector2(target.get("world_position", Vector2.ZERO))
	var scale_factor := maxf(1.0, float(target.get("scale_factor", 1)))
	var image_pos := ((world_pos - world_origin) / scale_factor).floor()
	var image_size := Vector2i(target.get("image_size", Vector2i.ZERO))
	if image_size.x <= 0 or image_size.y <= 0:
		return Vector2i.ZERO
	return Vector2i(
		clampi(int(image_pos.x), 0, image_size.x - 1), clampi(int(image_pos.y), 0, image_size.y - 1)
	)


func _on_tool_selection_committed(selection: PFSelection) -> void:
	_commit_selection_state(selection, true)


func _commit_selection_state(selection: PFSelection, record_undo: bool) -> void:
	var before := _current_selection.duplicate_selection() if _current_selection != null else null
	var after := selection.duplicate_selection() if selection != null else null
	if _same_selection(before, after):
		return

	var do_set := func() -> void: _apply_selection_state(after)
	var undo_set := func() -> void: _apply_selection_state(before)

	if record_undo:
		UndoService.perform_action("Tool selection", do_set, undo_set)
	else:
		do_set.call()


func _apply_selection_state(selection: PFSelection) -> void:
	_current_selection = selection.duplicate_selection() if selection != null else null
	for tool in _tools.values():
		tool.set_current_selection(_current_selection)
	selection_changed.emit(_current_selection)


func _same_selection(left: PFSelection, right: PFSelection) -> bool:
	if left == null or right == null:
		return left == right
	if (
		left.image_size != right.image_size
		or left.get_selected_count() != right.get_selected_count()
	):
		return false
	return left.mask == right.mask


func _modifiers_from_event(event: InputEventWithModifiers) -> int:
	var modifiers := 0
	if event.shift_pressed:
		modifiers |= BaseTool.MOD_SHIFT
	if event.alt_pressed:
		modifiers |= BaseTool.MOD_ALT
	return modifiers
