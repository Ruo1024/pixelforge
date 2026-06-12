class_name PFTaskQueue
extends Node

## 简单 FIFO 并发任务队列。
## 关键约束：WorkerThreadPool 内不碰场景树；所有进度/完成信号都用 call_deferred 回主线程发出。

signal task_started(task_id: String, kind: String)
signal task_progressed(task_id: String, ratio: float, message: String)
signal task_finished(task_id: String, result: Variant)
signal task_failed(task_id: String, error: Dictionary)
signal task_canceled(task_id: String)

const DEFAULT_MAX_CONCURRENCY := 2

var _max_concurrency := DEFAULT_MAX_CONCURRENCY
var _pending: Array = []
var _running := {}
var _worker_ids := {}
var _completed_by_sequence := {}
var _next_sequence := 0
var _next_finish_sequence := 0
var _main_thread_id := ""


func _ready() -> void:
	_main_thread_id = str(OS.get_thread_caller_id())
	_max_concurrency = int(
		SettingsService.get_setting("tasks", "max_concurrency", DEFAULT_MAX_CONCURRENCY)
	)


func set_max_concurrency(value: int) -> void:
	_max_concurrency = maxi(1, value)
	SettingsService.set_setting("tasks", "max_concurrency", _max_concurrency)
	_pump_queue()


func get_max_concurrency() -> int:
	return _max_concurrency


func get_main_thread_id() -> String:
	return _main_thread_id


func submit(task: Variant) -> String:
	task._assign_queue(self)
	task.queue_sequence = _next_sequence
	_next_sequence += 1
	_pending.append(task)
	_pump_queue()
	return task.id


func cancel(task_id: String) -> void:
	for index in range(_pending.size()):
		var task: Variant = _pending[index]
		if task.id == task_id:
			task.cancel()
			_pending.remove_at(index)
			_store_completion(task, "canceled", null, {})
			_flush_completed_in_order()
			return

	if _running.has(task_id):
		var running_task: Variant = _running[task_id]
		# WorkerThreadPool 不能被安全抢占。这里仅设置取消标志；
		# _running 清理和 task_canceled 信号会在 worker 返回后的主线程回调中完成。
		running_task.cancel()


func clear() -> void:
	for task in _pending:
		task.cancel()
	for task_id in _running.keys():
		_running[task_id].cancel()
	_pending.clear()
	_completed_by_sequence.clear()
	_next_sequence = 0
	_next_finish_sequence = 0


func is_idle() -> bool:
	return _pending.is_empty() and _running.is_empty() and _completed_by_sequence.is_empty()


func get_running_count() -> int:
	return _running.size()


func get_pending_count() -> int:
	return _pending.size()


func _pump_queue() -> void:
	while _running.size() < _max_concurrency and not _pending.is_empty():
		var task: Variant = _pending.pop_front()
		if task.cancel_requested:
			_store_completion(task, "canceled", null, {})
			continue
		_start_task(task)
	_flush_completed_in_order()


func _start_task(task: Variant) -> void:
	_running[task.id] = task
	task_started.emit(task.id, task.kind)
	EventBus.task_started.emit(task.id, task.kind)

	var worker_callable := func() -> void:
		var result: Variant = task.execute()
		call_deferred("_complete_task_from_worker", task.id, result)

	var worker_id := WorkerThreadPool.add_task(worker_callable, false, "PFTask:%s" % task.kind)
	_worker_ids[task.id] = worker_id


func _complete_task_from_worker(task_id: String, result: Variant) -> void:
	if not _running.has(task_id):
		return

	var task: Variant = _running[task_id]
	_running.erase(task_id)
	if _worker_ids.has(task_id):
		WorkerThreadPool.wait_for_task_completion(int(_worker_ids[task_id]))
		_worker_ids.erase(task_id)

	if task.cancel_requested:
		_store_completion(task, "canceled", null, {})
	else:
		_store_completion(task, "finished", result, {})

	_flush_completed_in_order()
	_pump_queue()


func _emit_task_progress(task_id: String, ratio: float, message: String) -> void:
	if not _running.has(task_id):
		return

	var task: Variant = _running[task_id]
	if task.cancel_requested:
		return

	task.progress_reported.emit(task_id, ratio, message)
	task_progressed.emit(task_id, ratio, message)
	EventBus.task_progressed.emit(task_id, ratio, message)


func _store_completion(task: Variant, status: String, result: Variant, error: Dictionary) -> void:
	_completed_by_sequence[task.queue_sequence] = {
		"task": task,
		"status": status,
		"result": result,
		"error": error,
	}


func _flush_completed_in_order() -> void:
	while _completed_by_sequence.has(_next_finish_sequence):
		var completion: Dictionary = _completed_by_sequence[_next_finish_sequence]
		_completed_by_sequence.erase(_next_finish_sequence)
		_next_finish_sequence += 1

		var task: Variant = completion["task"]
		match String(completion["status"]):
			"finished":
				task.finished.emit(completion["result"])
				task_finished.emit(task.id, completion["result"])
				EventBus.task_finished.emit(task.id, completion["result"])
			"failed":
				task.failed.emit(completion["error"])
				task_failed.emit(task.id, completion["error"])
				EventBus.task_failed.emit(task.id, completion["error"])
			"canceled":
				task.canceled.emit()
				task_canceled.emit(task.id)
				EventBus.task_canceled.emit(task.id)
