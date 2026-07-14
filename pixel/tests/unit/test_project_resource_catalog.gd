extends "res://addons/gut/test.gd"

const Catalog := preload("res://services/project_resource_catalog.gd")
const BrowserScript := preload("res://ui/inspector/project_resource_browser.gd")


func before_each() -> void:
	ProjectService.new_project("Resource Catalog")


func test_assets_searches_name_tags_origin_and_reports_damaged_entries() -> void:
	var generated := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	generated.fill(Color.CORNFLOWER_BLUE)
	var generated_id := AssetLibrary.register_image(
		generated, "Cloud observatory", {"origin": "generated", "tags": ["night", "building"]}
	)
	var imported := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	imported.fill(Color.INDIAN_RED)
	AssetLibrary.register_image(imported, "Red barrel", {"origin": "imported", "tags": ["prop"]})
	var results := Catalog.search_assets("night", "generated")
	assert_eq(results.size(), 1)
	assert_eq(results[0]["asset_id"], generated_id)
	assert_true(results[0]["available"])
	assert_true(Catalog.search_assets("prop", "generated").is_empty())


func test_split_preset_catalogs_replace_retired_style_resources() -> void:
	var prompt_presets := Catalog.search_prompt_presets("game boy")
	assert_eq(prompt_presets.size(), 1)
	assert_eq(prompt_presets[0]["id"], "prompt-gb")
	assert_eq(prompt_presets[0]["preset"]["name_key"], "PROMPT_PRESET_GB")
	assert_eq(Catalog.search_prompt_presets().size(), 6)
	var cleanup_presets := Catalog.search_cleanup_presets("game boy")
	assert_eq(cleanup_presets.size(), 1)
	assert_eq(cleanup_presets[0]["id"], "cleanup-gb")
	assert_eq(cleanup_presets[0]["preset"]["settings"]["quantize"]["palette_id"], "gb_4")
	assert_eq(Catalog.search_cleanup_presets().size(), 6)


func test_resource_browser_filters_both_sources_and_exposes_canvas_drag_payload() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var asset_id := AssetLibrary.register_image(
		image, "Searchable tower", {"origin": "imported", "tags": ["building"]}
	)
	var browser: Control = BrowserScript.new()
	browser.size = Vector2(420, 600)
	add_child_autofree(browser)
	await wait_process_frames(2)
	var browser_kinds := []
	for index in range(browser._kind_option.item_count):
		browser_kinds.append(browser._kind_option.get_item_metadata(index))
	assert_eq(
		browser_kinds,
		["project_asset", "prompt_preset", "cleanup_preset", "workflow_template"],
	)
	browser._search.text = "tower"
	browser._refresh()
	assert_eq(browser.get_visible_resources().size(), 1)
	assert_eq(browser.get_visible_resources()[0]["asset_id"], asset_id)
	var drag_payload: Variant = browser._list.drag_payload_for_index(0)
	assert_true(drag_payload is Dictionary)
	assert_eq(drag_payload["kind"], "project_asset")
	assert_eq(drag_payload["asset_id"], asset_id)
	browser._kind_option.select(1)
	browser._on_kind_selected(1)
	browser._search.text = "Game Boy"
	browser._refresh()
	assert_eq(browser.get_visible_resources().size(), 1)
	assert_eq(browser.get_visible_resources()[0]["kind"], "prompt_preset")
	assert_true(browser.get_visible_resources()[0].has("preset"))
	browser._kind_option.select(2)
	browser._on_kind_selected(2)
	browser._search.text = "Game Boy"
	browser._refresh()
	assert_eq(browser.get_visible_resources().size(), 1)
	assert_eq(browser.get_visible_resources()[0]["kind"], "cleanup_preset")
	assert_true(browser.get_visible_resources()[0].has("preset"))
