class_name PFTask
extends RefCounted

## 任务队列的任务对象。
## contract: 01-architecture/ARCHITECTURE.md §4.2；工作线程只运行 work_callable，信号由 TaskQueue 回主线程转发。

signal progress_reported(task_id: String, ratio: float, message: String)
signal finished(result: Variant)
signal failed(error: Dictionary)
signal canceled

const IdUtil := preload("res://core/util/id_util.gd")

var id := ""
var kind := ""
var payload := {}
var work_callable := Callable()
var external_start_callable := Callable()
var external_cancel_callable := Callable()
var cancel_requested := false
var queue_sequence := -1

var _queue: Node = null


func _init(
	p_kind: String = "", p_payload: Dictionary = {}, p_work_callable: Callable = Callable()
) -> void:
	id = IdUtil.uuid_v4()
	kind = p_kind
	payload = p_payload.duplicate(true)
	work_callable = p_work_callable


func cancel() -> void:
	cancel_requested = true
	if external_cancel_callable.is_valid():
		external_cancel_callable.call(self)


func report_progress(ratio: float, message: String = "") -> void:
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	if _queue != null:
		_queue.call_deferred("_emit_task_progress", id, clamped_ratio, message)
	else:
		progress_reported.emit(id, clamped_ratio, message)


func execute() -> Variant:
	if cancel_requested:
		return null
	if work_callable.is_valid():
		return work_callable.call(self)
	return payload


func configure_external(start_callable: Callable, cancel_callable: Callable = Callable()) -> void:
	external_start_callable = start_callable
	external_cancel_callable = cancel_callable


func is_external_async() -> bool:
	return external_start_callable.is_valid()


func start_external() -> void:
	if cancel_requested:
		resolve(null)
		return
	if external_start_callable.is_valid():
		external_start_callable.call(self)


func resolve(result: Variant) -> void:
	if _queue != null:
		_queue.call_deferred("_complete_external_task", id, result, {})


func reject(error: Dictionary) -> void:
	if _queue != null:
		_queue.call_deferred("_complete_external_task", id, null, error)


func _assign_queue(queue: Node) -> void:
	_queue = queue
