class_name PFUndoService
extends Node

## 全局撤销/重做服务。
## 说明：对外提供动作级 API；图像快照按字节估算计费，超过步数或内存上限时丢弃最旧动作。
## 约定：任何 undo action 如果持有 Image 或 Image 副本，调用方必须把
## estimate_snapshot_cost(image) 的结果传入 add_memory_cost()/perform_action()。
## 这样 M1 的清洗、量化、裁切步骤才不会绕过内存上限。

signal action_committed(name: String)
signal undone(name: String)
signal redone(name: String)
signal history_changed

const DEFAULT_MAX_STEPS := 100
const DEFAULT_MAX_MEMORY_BYTES := 512 * 1024 * 1024
const ImageMath := preload("res://core/util/image_math.gd")
const Log := preload("res://core/util/log_util.gd")


class PFUndoAction:
	var name := ""
	var do_callbacks: Array = []
	var undo_callbacks: Array = []
	var memory_cost_bytes := 0

	func run_do() -> void:
		for callback in do_callbacks:
			callback.call()

	func run_undo() -> void:
		var index := undo_callbacks.size() - 1
		while index >= 0:
			undo_callbacks[index].call()
			index -= 1


var _stack: Array = []
var _cursor := 0
var _current_action: PFUndoAction = null
var _max_steps := DEFAULT_MAX_STEPS
var _max_memory_bytes := DEFAULT_MAX_MEMORY_BYTES
var _memory_bytes := 0


func configure_limits(max_steps: int, max_memory_bytes: int) -> void:
	_max_steps = maxi(1, max_steps)
	_max_memory_bytes = maxi(1, max_memory_bytes)
	_trim_limits()
	history_changed.emit()


func reset_limits() -> void:
	_max_steps = DEFAULT_MAX_STEPS
	_max_memory_bytes = DEFAULT_MAX_MEMORY_BYTES
	_trim_limits()
	history_changed.emit()


func begin_action(name: String) -> void:
	if _current_action != null:
		Log.warn(
			"Undo action was open; committing it before starting another.",
			{"name": _current_action.name}
		)
		commit()

	_current_action = PFUndoAction.new()
	_current_action.name = name


func add_do_callable(callback: Callable) -> void:
	if _current_action == null:
		Log.warn("add_do_callable ignored because no undo action is open")
		return
	_current_action.do_callbacks.append(callback)


func add_undo_callable(callback: Callable) -> void:
	if _current_action == null:
		Log.warn("add_undo_callable ignored because no undo action is open")
		return
	_current_action.undo_callbacks.append(callback)


func add_memory_cost(bytes: int) -> void:
	if _current_action == null:
		Log.warn("add_memory_cost ignored because no undo action is open")
		return
	_current_action.memory_cost_bytes += maxi(0, bytes)


func commit(execute_do: bool = true) -> void:
	if _current_action == null:
		return

	var action := _current_action
	_current_action = null
	if execute_do:
		action.run_do()

	_drop_redo_tail()
	_stack.append(action)
	_cursor = _stack.size()
	_memory_bytes += action.memory_cost_bytes
	_trim_limits()

	action_committed.emit(action.name)
	history_changed.emit()


func perform_action(
	name: String,
	do_callback: Callable,
	undo_callback: Callable,
	memory_cost_bytes: int = 0,
	execute_do: bool = true
) -> void:
	begin_action(name)
	add_do_callable(do_callback)
	add_undo_callable(undo_callback)
	add_memory_cost(memory_cost_bytes)
	commit(execute_do)


func undo() -> bool:
	if not can_undo():
		return false

	_cursor -= 1
	var action: PFUndoAction = _stack[_cursor]
	action.run_undo()
	undone.emit(action.name)
	history_changed.emit()
	return true


func redo() -> bool:
	if not can_redo():
		return false

	var action: PFUndoAction = _stack[_cursor]
	action.run_do()
	_cursor += 1
	redone.emit(action.name)
	history_changed.emit()
	return true


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _stack.size()


func clear() -> void:
	_stack.clear()
	_cursor = 0
	_current_action = null
	_memory_bytes = 0
	history_changed.emit()


func snapshot_region(image: Image, rect: Rect2i) -> Image:
	return ImageMath.snapshot_region(image, rect)


func estimate_snapshot_cost(image: Image) -> int:
	# 统一按 RGBA8 快照估算，即 width * height * 4 字节。
	# 调用方持有多个图像副本时，应逐张相加后传入 action 的 memory_cost。
	return ImageMath.estimate_rgba8_bytes(image)


func get_memory_bytes() -> int:
	return _memory_bytes


func get_undo_count() -> int:
	return _cursor


func get_redo_count() -> int:
	return _stack.size() - _cursor


func _drop_redo_tail() -> void:
	while _stack.size() > _cursor:
		var dropped: PFUndoAction = _stack.pop_back()
		_memory_bytes -= dropped.memory_cost_bytes
	_memory_bytes = maxi(0, _memory_bytes)


func _trim_limits() -> void:
	while _stack.size() > _max_steps or _memory_bytes > _max_memory_bytes:
		if _stack.is_empty():
			break
		var dropped: PFUndoAction = _stack.pop_front()
		_memory_bytes -= dropped.memory_cost_bytes
		if _cursor > 0:
			_cursor -= 1
	_memory_bytes = maxi(0, _memory_bytes)
