extends "res://addons/gut/test.gd"

const CONTROLLER_PATH := "res://services/provider_cancel_settlement_v2.gd"
const GROUP_PATH := "res://services/cancel_group_settlement_v2.gd"
const ManualSchedulerScript := preload(
	"res://tests/fixtures/providers/manual_deadline_scheduler.gd"
)
const ContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")
const ShellControllerScript := preload("res://ui/shell/generation_run_controller.gd")


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
	var second: Variant = controller.cancel("request-1", generation, false, Callable(), Callable())
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
	var queued_keys := queued_result.keys()
	queued_keys.sort()
	assert_eq(
		queued_keys, ["billing_update", "local_stopped", "remote_cancel_confirmed", "request_id"]
	)
	assert_null(ContractV2.validate_cancel_result(queued_result))

	var running_generation := _generation_task("request-remote")
	var running_controller: Variant = script.new("retrodiffusion", scheduler)
	var running_task: Variant = running_controller.cancel(
		"request-remote", running_generation, false, func() -> void: pass, func() -> void: pass
	)
	var running_result := {}
	running_task.resolved.connect(func(value: Dictionary) -> void: running_result.assign(value))
	scheduler.advance_ms(0)
	(
		running_controller
		. confirm_local_stopped(
			"request-remote",
			{
				"actual_cost_usd": "0.250000",
				"charge_id": "charge-1",
				"provider_meta": {"remote_task_id": "remote-1"},
			}
		)
	)
	running_controller.confirm_remote_cancel("request-remote", true)
	assert_eq(running_result["remote_cancel_confirmed"], true)
	assert_eq(running_result["billing_update"]["actual_cost_usd"], "0.250000")
	assert_null(ContractV2.validate_cancel_result(running_result))
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
	assert_eq(
		settled.map(func(item: Dictionary) -> String: return item["request_id"]),
		["request-a", "request-b", "request-c"]
	)
	assert_eq(
		settled.map(func(item: Dictionary) -> String: return item["status"]),
		["resolved", "resolved", "rejected"]
	)


func test_built_in_providers_use_the_deadline_settlement_boundary() -> void:
	for path in [
		"res://plugins/provider_openai/openai_image_provider.gd",
		"res://plugins/provider_retrodiffusion/retrodiffusion_provider.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assert_true(source.contains("provider_cancel_settlement_v2.gd"), path)
		assert_true(source.contains("_cancel_settlement.cancel("), path)
		assert_true(source.contains("confirm_local_stopped"), path)
		assert_false(source.contains("_finish_canceled"), path)
	var controller_source := FileAccess.get_file_as_string(
		"res://ui/shell/generation_run_controller.gd"
	)
	assert_string_contains(controller_source, "cancel_task.resolved.connect")
	assert_string_contains(controller_source, "_record_billing_update(")


func test_cancel_billing_is_recorded_before_controller_terminalizes() -> void:
	var month := CostService.get_month_key()
	CostService.reset_month_for_tests(month)
	var controller := ShellControllerScript.new()
	add_child_autofree(controller)
	var status_label := Label.new()
	controller.add_child(status_label)
	controller._status_label = status_label
	controller._pending_runs["request-billing"] = {
		"provider_name": "Retro Diffusion",
		"request": {"request_id": "request-billing"},
		"scope_id": "",
	}
	var observed := {"pending_when_recorded": false}
	var observe := func(_month: String, _total: int) -> void:
		observed["pending_when_recorded"] = controller._pending_runs.has("request-billing")
	CostService.cost_changed_v2.connect(observe, CONNECT_ONE_SHOT)
	(
		controller
		. _on_cancel_resolved(
			{
				"request_id": "request-billing",
				"local_stopped": true,
				"remote_cancel_confirmed": false,
				"billing_update":
				{
					"actual_cost_usd": "0.250000",
					"charge_id": "charge-billing",
					"provider_meta": {"remote_task_id": "remote-billing"},
				},
			},
			"retrodiffusion",
			"request-billing",
		)
	)
	assert_true(observed["pending_when_recorded"])
	assert_false(controller._pending_runs.has("request-billing"))
	assert_eq(CostService.get_month_total_micro_usd(month), 250000)
	CostService.reset_month_for_tests(month)


func _generation_task(request_id: String) -> PFProviderTaskV2:
	return (
		PFProviderTaskV2
		. new(
			{
				"request_id": request_id,
				"provider_id": "openai_image",
				"provider_output_size": [1, 1],
				"batch": 1,
			},
			[]
		)
	)
