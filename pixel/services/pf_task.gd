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


func _assign_queue(queue: Node) -> void:
	_queue = queue
