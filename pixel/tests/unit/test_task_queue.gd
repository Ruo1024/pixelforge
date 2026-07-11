extends "res://addons/gut/test.gd"

const TaskScript := preload("res://services/pf_task.gd")


func before_each() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	queue.clear()
	queue.set_max_concurrency(2)


func test_sleep_tasks_finish_in_submission_order() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished := []
	var on_finished := func(_task_id: String, result: Variant) -> void: finished.append(result)

	queue.task_finished.connect(on_finished)
	for index in range(10):
		var task := TaskScript.new(
			"sleep",
			{"index": index},
			func(task_ref: Variant) -> Variant:
				OS.delay_msec(10)
				return task_ref.payload["index"]
		)
		queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return finished.size() == 10))
	assert_eq(finished, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
	queue.task_finished.disconnect(on_finished)


func test_cancelled_task_does_not_emit_finished() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished_ids := []
	var canceled_ids := []
	var on_finished := func(task_id: String, _result: Variant) -> void: finished_ids.append(task_id)
	var on_canceled := func(task_id: String) -> void: canceled_ids.append(task_id)

	queue.task_finished.connect(on_finished)
	queue.task_canceled.connect(on_canceled)

	var task := TaskScript.new(
		"slow",
		{},
		func(_task_ref: Variant) -> Variant:
			OS.delay_msec(80)
			return "done"
	)
	queue.submit(task)
	queue.cancel(task.id)

	assert_false(queue.is_idle())
	assert_eq(queue.get_running_count(), 1)
	assert_false(canceled_ids.has(task.id))

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_false(finished_ids.has(task.id))
	assert_true(canceled_ids.has(task.id))

	queue.task_finished.disconnect(on_finished)
	queue.task_canceled.disconnect(on_canceled)


func test_running_cancel_finishes_as_canceled_and_returns_to_idle() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished_ids := []
	var canceled_ids := []
	var on_finished := func(task_id: String, _result: Variant) -> void: finished_ids.append(task_id)
	var on_canceled := func(task_id: String) -> void: canceled_ids.append(task_id)

	queue.task_finished.connect(on_finished)
	queue.task_canceled.connect(on_canceled)

	var task := TaskScript.new(
		"cancel-full-path",
		{},
		func(_task_ref: Variant) -> Variant:
			OS.delay_msec(120)
			return "worker returned after cancel"
	)
	queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return queue.get_running_count() == 1))
	queue.cancel(task.id)

	assert_false(queue.is_idle())
	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_eq(finished_ids, [])
	assert_eq(canceled_ids, [task.id])

	queue.task_finished.disconnect(on_finished)
	queue.task_canceled.disconnect(on_canceled)


func test_progress_signal_is_emitted_on_main_thread() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var main_thread_id: String = queue.get_main_thread_id()
	var progress_thread_ids := []
	var on_progress := func(_task_id: String, _ratio: float, _message: String) -> void:
		progress_thread_ids.append(str(OS.get_thread_caller_id()))

	queue.task_progressed.connect(on_progress)

	var task := TaskScript.new(
		"progress",
		{},
		func(task_ref: Variant) -> Variant:
			task_ref.report_progress(0.5, "half")
			OS.delay_msec(20)
			return "ok"
	)
	queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_gt(progress_thread_ids.size(), 0)
	for thread_id in progress_thread_ids:
		assert_eq(thread_id, main_thread_id)

	queue.task_progressed.disconnect(on_progress)


func test_external_async_task_resolves_through_queue() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished := []
	var task := TaskScript.new("external", {"safe": true})
	task.configure_external(func(task_ref: Variant) -> void: task_ref.resolve("external-ok"))
	task.finished.connect(func(result: Variant) -> void: finished.append(result))

	queue.submit(task)

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_eq(finished, ["external-ok"])


func test_external_async_cancel_emits_only_canceled() -> void:
	var queue := get_tree().root.get_node("TaskQueue")
	var finished := []
	var canceled := []
	var task := TaskScript.new("external-cancel", {})
	task.configure_external(_hold_external, _resolve_external_cancel)
	task.finished.connect(func(result: Variant) -> void: finished.append(result))
	task.canceled.connect(func() -> void: canceled.append(task.id))

	queue.submit(task)
	queue.cancel(task.id)

	assert_true(await _wait_until(func() -> bool: return queue.is_idle()))
	assert_eq(finished, [])
	assert_eq(canceled, [task.id])


func _hold_external(_task_ref: Variant) -> void:
	pass


func _resolve_external_cancel(task_ref: Variant) -> void:
	task_ref.resolve(null)


func _wait_until(check: Callable, timeout_seconds: float = 2.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if check.call():
			return true
		await wait_seconds(0.05)
		elapsed += 0.05
	return false
