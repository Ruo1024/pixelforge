extends "res://addons/gut/test.gd"

const Fixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")


func test_fixture_is_deterministic_and_has_two_branches_and_stages() -> void:
	var first: Dictionary = Fixture.build()
	var second: Dictionary = Fixture.build()
	assert_eq(first, second)
	assert_eq(first["canvas"]["items"].filter(_is_frame).size(), 2)
	assert_eq(first["graphs"][Fixture.GRAPH_ID]["nodes"].size(), 10)
	assert_eq(first["graphs"][Fixture.GRAPH_ID]["edges"].size(), 8)
	var graph: PFGraph = GraphScript.from_json(first["graphs"][Fixture.GRAPH_ID])
	assert_eq(graph.validate_edges(), [])
	assert_eq(graph.to_json()["nodes"].size(), 10)


func _is_frame(item: Dictionary) -> bool:
	return String(item.get("type", "")) == "frame"
