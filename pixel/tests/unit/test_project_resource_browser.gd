extends "res://addons/gut/test.gd"

const BrowserScript := preload("res://ui/inspector/project_resource_browser.gd")
const Catalog := preload("res://services/project_resource_catalog.gd")


func test_workflow_catalog_exposes_three_valid_builtins_with_preview_metadata() -> void:
	var workflows := Catalog.search_workflows("", "builtin")

	assert_eq(workflows.size(), 3)
	assert_true(workflows.all(func(item: Dictionary) -> bool: return item["node_count"] >= 4))
	assert_true(workflows.all(func(item: Dictionary) -> bool: return item["model_ids"].size() == 1))
	assert_eq(Catalog.search_workflows("reference", "builtin").size(), 1)
	assert_eq(Catalog.search_workflows("", "user"), [])


func test_resource_browser_workflow_category_is_searchable_and_draggable() -> void:
	var browser: Control = add_child_autofree(BrowserScript.new())
	await wait_process_frames(1)
	var kind: OptionButton = browser.find_child("ResourceKind", true, false)
	kind.select(2)
	kind.item_selected.emit(2)
	await wait_process_frames(1)

	var visible: Array[Dictionary] = browser.get_visible_resources()
	assert_eq(visible.size(), 3)
	assert_eq(visible[0]["kind"], "workflow_template")
	assert_true(visible[0].has("template"))
	var list: ItemList = browser.find_child("ResourceList", true, false)
	var payload: Variant = list.drag_payload_for_index(0)
	assert_eq(payload["kind"], "workflow_template")
