class_name PFMockGenerationHarness
extends RefCounted

## Test helper that keeps GraphMockRunner pure and materializes only through the real coordinator.

const PlanBuilderScript := preload("res://services/graph_generation_plan_builder.gd")
const ExecutorScript := preload("res://services/mock_generation_executor.gd")


static func run(
	graph: PFGraph, asset_library: Node, generate_node_id: String, output_node_id: String
) -> Dictionary:
	var plan: Dictionary = PlanBuilderScript.build(
		graph, generate_node_id, "mock", [PlanBuilderScript.mock_descriptor()], asset_library
	)
	if not bool(plan.get("ok", false)):
		return plan
	return ExecutorScript.execute(graph, generate_node_id, output_node_id, plan, asset_library)
