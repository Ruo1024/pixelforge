extends "res://addons/gut/test.gd"

const Policy := preload("res://services/generation_count_policy.gd")


func test_one_to_four_run_directly_and_five_to_sixteen_require_confirmation() -> void:
	for count in range(1, 17):
		var decision: Dictionary = Policy.validate(count)
		assert_true(decision["ok"])
		assert_eq(decision["requires_confirmation"], count >= 5, str(count))
	for count in [0, 17]:
		assert_false(Policy.validate(count)["ok"])


func test_controller_gates_before_output_slots_and_provider_tasks() -> void:
	var source := FileAccess.get_file_as_string("res://ui/shell/generation_run_controller.gd")
	var gate := source.find("GenerationCountPolicyScript.validate(expected_count)")
	var start := source.find("_start_full_runs(run_states, provider_id)", gate)
	var start_function := source.find("func _start_full_runs(")
	var prepare := source.find("_submit_provider_runs(run_states)", start_function)
	var dispatch := source.find("ProviderService.generate(")
	assert_gte(gate, 0)
	assert_gt(start, gate)
	assert_gt(prepare, start_function)
	assert_gt(dispatch, prepare)
	assert_true(source.contains('_pending_count_run = {"runs": run_states'))
	assert_true(source.contains("_count_dialog.canceled.connect("))
