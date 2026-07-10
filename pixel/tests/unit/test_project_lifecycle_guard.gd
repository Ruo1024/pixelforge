extends "res://addons/gut/test.gd"

const GuardScript := preload("res://ui/shell/project_lifecycle_guard.gd")
const ProjectServiceScript := preload("res://services/project_service.gd")


class FakeProject:
	extends RefCounted
	var dirty := true


class FakeProjectService:
	extends RefCounted
	var current_project := FakeProject.new()


class FailingAutosaveProjectService:
	extends ProjectServiceScript

	func _ready() -> void:
		current_project.reset("Autosave Failure")

	func autosave_now() -> Error:
		return ERR_CANT_CREATE


func test_new_open_and_quit_each_offer_save_discard_and_cancel() -> void:
	for action_id in [GuardScript.ACTION_NEW, GuardScript.ACTION_OPEN, GuardScript.ACTION_QUIT]:
		var service := FakeProjectService.new()
		var guard: Node = GuardScript.new()
		add_child_autofree(guard)
		guard.setup(service)

		var completed := []
		var save_requests := [0]
		guard.action_ready.connect(
			func(ready_action: String, _payload: Variant) -> void: completed.append(ready_action)
		)
		guard.save_requested.connect(func() -> void: save_requests[0] += 1)

		assert_true(guard.request_action(action_id, "payload"))
		guard.cancel_pending()
		assert_true(completed.is_empty(), "%s Cancel must keep the project" % action_id)

		assert_true(guard.request_action(action_id, "payload"))
		guard.choose_discard()
		assert_eq(completed, [action_id], "%s Discard must continue" % action_id)

		completed.clear()
		assert_true(guard.request_action(action_id, "payload"))
		guard.choose_save()
		assert_eq(save_requests[0], 1, "%s Save must request persistence" % action_id)
		assert_true(completed.is_empty())
		guard.notify_save_result(OK)
		assert_eq(completed, [action_id], "%s Save success must continue" % action_id)


func test_save_failure_keeps_destructive_action_pending() -> void:
	var guard: Node = GuardScript.new()
	add_child_autofree(guard)
	guard.setup(FakeProjectService.new())
	var completed := []
	guard.action_ready.connect(
		func(action_id: String, _payload: Variant) -> void: completed.append(action_id)
	)

	assert_true(guard.request_action(GuardScript.ACTION_QUIT))
	guard.choose_save()
	guard.notify_save_result(ERR_CANT_CREATE)

	assert_true(completed.is_empty())
	assert_true(guard.has_pending_action())
	assert_eq(guard.get_pending_action_id(), GuardScript.ACTION_QUIT)


func test_clean_project_runs_action_without_dialog() -> void:
	var service := FakeProjectService.new()
	service.current_project.dirty = false
	var guard: Node = GuardScript.new()
	add_child_autofree(guard)
	guard.setup(service)
	var completed := []
	guard.action_ready.connect(
		func(action_id: String, payload: Variant) -> void: completed.append([action_id, payload])
	)

	assert_false(guard.request_action(GuardScript.ACTION_OPEN, "project.pxproj"))
	assert_eq(completed, [[GuardScript.ACTION_OPEN, "project.pxproj"]])


func test_autosave_failure_emits_user_feedback_signal() -> void:
	var service := FailingAutosaveProjectService.new()
	add_child_autofree(service)
	service.current_project.dirty = true
	var failures := []
	service.autosave_failed.connect(
		func(error: Error, path: String) -> void: failures.append([error, path])
	)

	service._on_autosave_timeout()

	assert_eq(failures, [[ERR_CANT_CREATE, "user://autosave"]])
