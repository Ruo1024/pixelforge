extends "res://addons/gut/test.gd"

const CONTROLLER_PATH := "res://services/provider_cancel_settlement_v2.gd"
const GROUP_PATH := "res://services/cancel_group_settlement_v2.gd"
const ManualSchedulerScript := preload(
	"res://tests/fixtures/providers/manual_deadline_scheduler.gd"
)


func test_cancel_order_deadlines_and_dedupe() -> void:
	var script: Script = load(CONTROLLER_PATH)
	assert_not_null(script)
	if script == null:
		return
	var scheduler := ManualSchedulerScript.new()
	var generation := _generation_task("request-1")
	var calls := {"local": 0, "remote": 0}
	var controller: Variant = script.new("openai_image", scheduler)
	var first: Variant = controller.cancel(
		"request-1",
		generation,
		false,
		func() -> void: calls["local"] += 1,
		func() -> void: calls["remote"] += 1
	)
	var second: Variant = controller.cancel(
		"request-1", generation, false, Callable(), Callable()
	)
	var events := []
	var result := {}
	generation.canceled.connect(func(_request_id: String) -> void: events.append("generation"))
	first.resolved.connect(
		func(value: Dictionary) -> void:
			result.assign(value)
			events.append("cancel")
	)
	assert_same(first, second)
	scheduler.advance_ms(0)
	assert_eq(calls, {"local": 1, "remote": 0})
	scheduler.advance_ms(4999)
	assert_false(first.is_terminal())
	controller.confirm_local_stopped("request-1", null)
	assert_eq(calls, {"local": 1, "remote": 1})
	assert_eq(events, ["generation"])
	scheduler.advance_ms(2999)
	assert_false(first.is_terminal())
	scheduler.advance_ms(1)
	assert_eq(events, ["generation", "cancel"])
	assert_eq(result["remote_cancel_confirmed"], false)
	assert_eq(result["billing_update"], null)


func test_local_timeout_fails_generation_before_cancel_wrapper() -> void:
	var script: Script = load(CONTROLLER_PATH)
	assert_not_null(script)
	if script == null:
		return
	var scheduler := ManualSchedulerScript.new()
	var generation := _generation_task("request-timeout")
	var controller: Variant = script.new("retrodiffusion", scheduler)
	var cancel_task: Variant = controller.cancel(
		"request-timeout", generation, false, func() -> void: pass, Callable()
	)
	var events := []
	var errors := []
	generation.failed.connect(
		func(error: Dictionary) -> void:
			errors.append(error)
			events.append("generation")
	)
	cancel_task.rejected.connect(
		func(error: Dictionary) -> void:
			errors.append(error)
			events.append("cancel")
	)
	scheduler.advance_ms(0)
	scheduler.advance_ms(4999)
	assert_eq(events, [])
	scheduler.advance_ms(1)
	assert_eq(events, ["generation", "cancel"])
	assert_eq(errors.size(), 2)
	assert_eq(errors[0], errors[1])
	assert_eq(errors[0]["code"], "cancel_failed")
	assert_eq(errors[0]["stage"], "cancel")


func test_queued_and_remote_confirmed_branches() -> void:
	var script: Script = load(CONTROLLER_PATH)
	assert_not_null(script)
	if script == null:
		return
	var scheduler := ManualSchedulerScript.new()
	var queued_generation := _generation_task("request-queued")
	var queued_calls := {"local": 0, "remote": 0}
	var queued_controller: Variant = script.new("openai_image", scheduler)
	var queued_task: Variant = queued_controller.cancel(
		"request-queued",
		queued_generation,
		true,
		func() -> void: queued_calls["local"] += 1,
		func() -> void: queued_calls["remote"] += 1
	)
	var queued_result := {}
	queued_task.resolved.connect(func(value: Dictionary) -> void: queued_result.assign(value))
	scheduler.advance_ms(0)
	assert_eq(queued_calls, {"local": 0, "remote": 0})
	assert_eq(queued_result["remote_cancel_confirmed"], true)

	var running_generation := _generation_task("request-remote")
	var running_controller: Variant = script.new("retrodiffusion", scheduler)
	var running_task: Variant = running_controller.cancel(
		"request-remote", running_generation, false, func() -> void: pass, func() -> void: pass
	)
	var running_result := {}
	running_task.resolved.connect(func(value: Dictionary) -> void: running_result.assign(value))
	scheduler.advance_ms(0)
	running_controller.confirm_local_stopped(
		"request-remote",
		{
			"actual_cost_usd": "0.250000",
			"charge_id": "charge-1",
			"provider_meta": {"remote_task_id": "remote-1"},
		}
	)
	running_controller.confirm_remote_cancel("request-remote", true)
	assert_eq(running_result["remote_cancel_confirmed"], true)
	assert_eq(running_result["billing_update"]["actual_cost_usd"], "0.250000")
	scheduler.advance_ms(3000)
	assert_eq(running_result["remote_cancel_confirmed"], true)


func test_multi_request_wrappers_all_settle() -> void:
	var controller_script: Script = load(CONTROLLER_PATH)
	var group_script: Script = load(GROUP_PATH)
	assert_not_null(controller_script)
	assert_not_null(group_script)
	if controller_script == null or group_script == null:
		return
	var scheduler := ManualSchedulerScript.new()
	var controller: Variant = controller_script.new("openai_image", scheduler)
	var tasks := []
	for request_id in ["request-a", "request-b", "request-c"]:
		tasks.append(
			{
				"request_id": request_id,
				"task":
				controller.cancel(
					request_id, _generation_task(request_id), false, func() -> void: pass
				),
			}
		)
	var group: Variant = group_script.new()
	var settled := []
	group.settled.connect(func(outcomes: Array) -> void: settled.assign(outcomes))
	for item in tasks:
		group.add(String(item["request_id"]), item["task"])
	group.seal()
	scheduler.advance_ms(0)
	controller.confirm_local_stopped("request-a", null)
	controller.confirm_local_stopped("request-b", null)
	assert_eq(settled, [])
	scheduler.advance_ms(5000)
	assert_eq(settled.size(), 3)
	assert_eq(settled.map(func(item: Dictionary) -> String: return item["request_id"]), [
		"request-a", "request-b", "request-c"
	])
	assert_eq(settled.map(func(item: Dictionary) -> String: return item["status"]), [
		"resolved", "resolved", "rejected"
	])


func _generation_task(request_id: String) -> PFProviderTaskV2:
	return PFProviderTaskV2.new(
		{
			"request_id": request_id,
			"provider_id": "openai_image",
			"provider_output_size": [1, 1],
			"batch": 1,
		},
		[]
	)
