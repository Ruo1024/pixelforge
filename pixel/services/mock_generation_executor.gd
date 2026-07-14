class_name PFMockGenerationExecutor
extends RefCounted

## Runs the pure local mock and delegates every run/slot/Output write to the coordinator.

const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
const GenerationRunCoordinatorScript := preload("res://services/generation_run_coordinator.gd")
const ProviderResultMapperScript := preload("res://services/provider_result_mapper.gd")


static func execute(
	graph: PFGraph,
	generate_node_id: String,
	output_node_id: String,
	plan: Dictionary,
	asset_library: Node,
	coordinator: PFGenerationRunCoordinator = null
) -> Dictionary:
	var writer := coordinator
	if writer == null:
		writer = GenerationRunCoordinatorScript.new()
	var prepared: Dictionary = writer.prepare_full_run(
		graph, generate_node_id, output_node_id, plan
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	var executed: Dictionary = execute_prepared(
		graph, generate_node_id, output_node_id, plan, asset_library, writer
	)
	if not bool(executed.get("ok", false)):
		writer.rollback_pending_run(graph, prepared["rollback_token"])
	return executed


static func execute_prepared(
	graph: PFGraph,
	_generate_node_id: String,
	output_node_id: String,
	plan: Dictionary,
	asset_library: Node,
	coordinator: PFGenerationRunCoordinator
) -> Dictionary:
	var writer := coordinator
	var executed: Dictionary = GraphMockRunnerScript.new().run_to_batch(
		graph, asset_library, output_node_id
	)
	if not bool(executed.get("ok", false)):
		return executed
	var terminal_items: Array = executed.get("terminal_items", [])
	var cursor := 0
	for request_value in plan.get("requests", []):
		var request: Dictionary = request_value
		var request_id := String(request.get("request_id", ""))
		var planned_slots := []
		for slot_value in plan.get("slots", []):
			if String(slot_value.get("request_id", "")) == request_id:
				planned_slots.append(Dictionary(slot_value).duplicate(true))
		var item_count := int(request.get("batch", 0))
		if cursor + item_count > terminal_items.size():
			return {"ok": false, "error": {"code": "mock_result_count_mismatch"}}
		var items := []
		for index in range(item_count):
			var terminal: Dictionary = terminal_items[cursor + index]
			var metadata: Dictionary = terminal.get("metadata", {})
			(
				items
				. append(
					{
						"index": index,
						"image": terminal.get("image") as Image,
						"actual_seed": metadata.get("actual_seed"),
						"error": terminal.get("error"),
					}
				)
			)
		cursor += item_count
		var submitting: Dictionary = writer.mark_submitting(graph, output_node_id, request_id)
		if not bool(submitting.get("ok", false)):
			return submitting
		var normalized := {
			"request_id": request_id,
			"items": items,
			"actual_cost_usd": null,
			"charge_id": "",
			"provider_meta": {},
		}
		var mapped: Dictionary = ProviderResultMapperScript.map_result(
			request, planned_slots, normalized
		)
		var applied: Dictionary = writer.apply_provider_mapping(
			graph, output_node_id, request, mapped, asset_library
		)
		if not bool(applied.get("ok", false)):
			return applied
	return {
		"ok": true,
		"terminal_items": terminal_items,
		"result_slots": graph.get_node_params(output_node_id).get("result_slots", []),
		"graph": graph.to_json(),
		"output_node_id": output_node_id,
	}
