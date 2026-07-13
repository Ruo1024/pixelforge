# gdlint: disable=max-returns
extends Node

const Fixture := preload("res://tests/fixtures/generators/beta_workspace_fixture.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")
const GraphRunnerScript := preload("res://services/graph_mock_runner.gd")
const MainScene := preload("res://ui/shell/main.tscn")
const Log := preload("res://core/util/log_util.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")

const LEGACY_WINDOW_SIZE := Vector2i(1440, 900)
const BETA_0_6_SCENARIOS := {
	"closed": {"size": Vector2i(1080, 560), "scale": 2.0, "zoom": 1.0, "center": Vector2(0, 0)},
	"overlay": {"size": Vector2i(1080, 560), "scale": 2.0, "zoom": 0.5, "center": Vector2(40, 20)},
	"batch_12_13":
	{
		"size": Vector2i(1280, 720),
		"scale": 1.25,
		"zoom": 0.5,
		"center": Vector2(610, 330),
	},
	"inspector":
	{
		"size": Vector2i(1280, 720),
		"scale": 1.5,
		"zoom": 1.0,
		"center": Vector2(-450, -170),
	},
	"batch_50":
	{
		"size": Vector2i(1440, 900),
		"scale": 1.0,
		"zoom": 0.5,
		"center": Vector2(360, 758),
	},
	"card_families":
	{
		"size": Vector2i(1440, 900),
		"scale": 1.25,
		"zoom": 1.0,
		"center": Vector2(0, 20),
	},
	"inspect":
	{
		"size": Vector2i(1440, 900),
		"scale": 1.0,
		"zoom": 4.0,
		"center": Vector2(170, 100),
	},
}


func _ready() -> void:
	call_deferred("_capture_workspace")


func _capture_workspace() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2:
		await _capture_legacy(String(args[0]), String(args[1]))
		return
	if args.size() != 4:
		_fail("Usage: capture_beta_workspace.gd -- <output.png> <locale> [scenario metadata.json]")
		return
	var output_path := String(args[0])
	var locale := String(args[1])
	var scenario := String(args[2])
	var metadata_path := String(args[3])
	if locale not in ["en", "zh_CN"]:
		_fail("Screenshot locale must be en or zh_CN")
		return
	if not BETA_0_6_SCENARIOS.has(scenario):
		_fail("Unknown Beta 0.6 screenshot scenario", scenario)
		return

	var scenario_spec: Dictionary = BETA_0_6_SCENARIOS[scenario]
	var window_size: Vector2i = scenario_spec["size"]
	var interface_scale := float(scenario_spec["scale"])
	_prepare_runtime(window_size, locale, interface_scale)
	if not _build_beta_0_6_project(scenario, locale):
		return
	var main := MainScene.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await _force_beta_0_6_geometry(main, window_size, interface_scale)
	main._on_project_loaded(ProjectService.current_project)
	main.get_node("M21UiController/ImportFlowController").refresh_empty_hint()
	await _configure_beta_0_6_scene(main, scenario, scenario_spec)
	if not _assert_beta_0_6_scene(main, scenario, locale, window_size, scenario_spec):
		return
	for _frame in range(8):
		await get_tree().process_frame
	main.queue_redraw()
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var physical_size := get_window().size
	if image.get_size() != physical_size:
		_fail(
			"Screenshot viewport size does not match scaled scenario",
			{"actual": image.get_size(), "expected": physical_size},
		)
		return
	image.resize(window_size.x, window_size.y, Image.INTERPOLATE_LANCZOS)
	if not _save_image(image, output_path):
		return
	if not _save_metadata(main, scenario, locale, window_size, metadata_path):
		return
	Log.info(
		"Beta 0.6 workspace screenshot captured",
		{"locale": locale, "path": output_path, "scenario": scenario, "size": window_size}
	)
	get_tree().quit(OK)


func _capture_legacy(output_path: String, locale: String) -> void:
	if locale not in ["en", "zh_CN"]:
		_fail("Screenshot locale must be en or zh_CN")
		return
	_prepare_runtime(LEGACY_WINDOW_SIZE, locale, 1.25)
	if not _build_legacy_project():
		return
	var main := MainScene.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	DisplayServer.window_set_size(LEGACY_WINDOW_SIZE)
	main._on_project_loaded(ProjectService.current_project)
	main.get_node("M21UiController/ImportFlowController").refresh_empty_hint()
	for _frame in range(8):
		await get_tree().process_frame
	main.queue_redraw()
	await RenderingServer.frame_post_draw
	if not _save_image(get_viewport().get_texture().get_image(), output_path):
		return
	get_tree().quit(OK)


func _prepare_runtime(window_size: Vector2i, locale: String, interface_scale: float) -> void:
	DisplayServer.window_set_size(_physical_size(window_size, interface_scale))
	SettingsService.set_setting("onboarding", "v1_complete", true, false)
	SettingsService.set_setting("ui", "interface_scale", interface_scale, false)
	LocalizationService.apply_language(locale, locale)
	AssetLibrary.clear()


func _force_beta_0_6_geometry(main: Control, window_size: Vector2i, interface_scale: float) -> void:
	main._interface_scale = interface_scale
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, interface_scale)
	get_window().min_size = _physical_size(Vector2i(1080, 560), interface_scale)
	DisplayServer.window_set_size(_physical_size(window_size, interface_scale))
	for _frame in range(3):
		await get_tree().process_frame


func _build_beta_0_6_project(scenario: String, locale: String) -> bool:
	match scenario:
		"batch_12_13":
			return _build_batch_boundary_project()
		"batch_50":
			return _build_batch_fifty_project()
		"inspect":
			return _build_inspect_project()
		_:
			return _build_card_families_project(locale)


func _build_card_families_project(locale: String) -> bool:
	ProjectService.new_project(
		"Beta 0.6 卡片产品化长标题" if locale == "zh_CN" else "Beta 0.6 card productization"
	)
	var asset_ids := _register_assets(6, "family")
	var graph_id := "beta06_cards"
	var nodes := [
		{
			"id": "prompt",
			"type": "text_prompt",
			"position": [-330, -380],
			"params": {"text": "Moonlit forest props"}
		},
		{
			"id": "objects",
			"type": "object_list",
			"position": [-700, 30],
			"params": {"items": "tower\nbarrel\nlantern"}
		},
		{
			"id": "style",
			"type": "style_preset",
			"position": [0, -380],
			"params": {"preset_id": "gameboy"}
		},
		{
			"id": "size",
			"type": "size_spec",
			"position": [290, -380],
			"params": {"width": 32, "height": 32, "per_subject": 2}
		},
		{
			"id": "image",
			"type": "image_input",
			"position": [-330, 30],
			"params": {"asset_id": asset_ids[0]}
		},
		{
			"id": "references",
			"type": "reference_set",
			"position": [-40, 30],
			"params": {"asset_ids": asset_ids.slice(0, 3)}
		},
		{
			"id": "generate",
			"type": "ai_generate",
			"position": [-700, -380],
			"params": {"provider_id": "mock", "model_id": "offline", "batch_size": 4, "seed": 606}
		},
		{
			"id": "results",
			"type": "batch",
			"position": [330, 30],
			"params":
			{
				"asset_ids": asset_ids.slice(0, 4),
				"label": "候选结果" if locale == "zh_CN" else "Candidates",
				"review_states":
				{asset_ids[0]: "keep", asset_ids[1]: "reject", asset_ids[2]: "flag"}
			}
		},
	]
	ProjectService.set_graph_data(
		graph_id,
		{"graph_version": 1, "id": graph_id, "name": "Card families", "nodes": nodes, "edges": []},
		false
	)
	var min_sizes := {
		"prompt": [320, 240],
		"objects": [360, 360],
		"style": [280, 220],
		"size": [280, 220],
		"image": [280, 300],
		"references": [360, 320],
		"generate": [360, 400],
		"results": [360, 240],
	}
	var items := []
	for index in range(nodes.size()):
		var node: Dictionary = nodes[index]
		var node_id := String(node["id"])
		(
			items
			. append(
				{
					"id": "%s_card" % node_id,
					"type": "node",
					"graph_id": graph_id,
					"node_id": node_id,
					"position": node["position"],
					"size": min_sizes[node_id],
					"display_title":
					(
						"像素生成"
						if locale == "zh_CN" and node_id == "generate"
						else ("Forest Prompt" if node_id == "prompt" else "")
					),
					"z_index": index + 1,
				}
			)
		)
	(
		items
		. append(
			{
				"id": "sprite_card",
				"type": "sprite",
				"asset_id": asset_ids[4],
				"position": [470, -260],
				"size": [200, 188],
				"display_title": "独立精灵" if locale == "zh_CN" else "Hero sprite",
				"z_index": 20,
			}
		)
	)
	ProjectService.set_canvas_data(
		{"camera": {"center": [40, 20], "zoom": 1.0}, "items": items}, false
	)
	return true


func _build_batch_boundary_project() -> bool:
	ProjectService.new_project("12 / 13 result boundary")
	var asset_ids := _register_assets(13, "boundary")
	var graph_id := "beta06_boundary"
	var nodes := [
		{
			"id": "twelve",
			"type": "batch",
			"position": [0, 0],
			"params": {"asset_ids": asset_ids.slice(0, 12), "label": "12 results"}
		},
		{
			"id": "thirteen",
			"type": "batch",
			"position": [620, 0],
			"params": {"asset_ids": asset_ids, "label": "13 results"}
		},
	]
	ProjectService.set_graph_data(
		graph_id,
		{"graph_version": 1, "id": graph_id, "name": "Boundary", "nodes": nodes, "edges": []},
		false
	)
	(
		ProjectService
		. set_canvas_data(
			{
				"camera": {"center": [610, 330], "zoom": 0.5},
				"items":
				[
					{
						"id": "batch_12",
						"type": "node",
						"graph_id": graph_id,
						"node_id": "twelve",
						"position": [0, 0],
						"size": [600, 240]
					},
					{
						"id": "batch_13",
						"type": "node",
						"graph_id": graph_id,
						"node_id": "thirteen",
						"position": [620, 0],
						"size": [600, 240]
					},
				],
			},
			false
		)
	)
	return true


func _build_batch_fifty_project() -> bool:
	ProjectService.new_project("All 50 results")
	var asset_ids := _register_assets(50, "result")
	var graph_id := "beta06_fifty"
	(
		ProjectService
		. set_graph_data(
			graph_id,
			{
				"graph_version": 1,
				"id": graph_id,
				"name": "Fifty results",
				"nodes":
				[
					{
						"id": "results",
						"type": "batch",
						"position": [0, 0],
						"params":
						{
							"asset_ids": asset_ids,
							"label": "All 50 results",
							"review_states": {asset_ids[0]: "keep", asset_ids[49]: "flag"}
						}
					}
				],
				"edges": [],
			},
			false
		)
	)
	(
		ProjectService
		. set_canvas_data(
			{
				"camera": {"center": [360, 758], "zoom": 0.5},
				"items":
				[
					{
						"id": "batch_50",
						"type": "node",
						"graph_id": graph_id,
						"node_id": "results",
						"position": [0, 0],
						"size": [720, 240]
					}
				],
			},
			false
		)
	)
	return true


func _build_inspect_project() -> bool:
	ProjectService.new_project("400% pixel inspect")
	var asset_ids := _register_assets(4, "inspect")
	(
		ProjectService
		. set_canvas_data(
			{
				"camera": {"center": [170, 100], "zoom": 4.0},
				"items":
				[
					{
						"id": "inspect_sprite",
						"type": "sprite",
						"asset_id": asset_ids[0],
						"position": [0, 0],
						"size": [200, 188],
						"display_title": "16×16 RGBA"
					},
					{
						"id": "inspect_batch",
						"type": "batch_card",
						"asset_ids": asset_ids,
						"position": [210, 0],
						"size": [360, 240],
						"label": "Pixel candidates",
						"selected_asset_ids": [asset_ids[0]]
					},
				],
			},
			false
		)
	)
	return true


func _configure_beta_0_6_scene(main: Control, scenario: String, spec: Dictionary) -> void:
	var canvas: Control = main.get_node("Root/Content/Workspace/InfiniteCanvas")
	canvas.set_camera_zoom(float(spec["zoom"]), canvas.size * 0.5)
	canvas._center_on_world(Vector2(spec["center"]))
	match scenario:
		"overlay":
			main._toggle_inspector()
		"inspector":
			canvas.select_ids(["image_card"])
			main._toggle_inspector()
		"card_families":
			canvas.select_ids(["sprite_card"])
			canvas.get_node("WorkspaceNavigation/NavigationRow/ToggleMinimap").pressed.emit()
		"inspect":
			canvas.select_ids(["inspect_sprite"])
	for _frame in range(4):
		await get_tree().process_frame
	await _wait_for_capture_items(canvas, scenario)


func _wait_for_capture_items(canvas: Control, scenario: String) -> void:
	var expected_ids: Array[String] = []
	match scenario:
		"batch_12_13":
			expected_ids = ["batch_12", "batch_13"]
		"batch_50":
			expected_ids = ["batch_50"]
	if expected_ids.is_empty():
		return
	for _frame in range(30):
		var all_ready := true
		for item_id in expected_ids:
			if not canvas._items_by_id.has(item_id):
				all_ready = false
				break
		if all_ready:
			return
		await get_tree().process_frame


func _assert_beta_0_6_scene(
	main: Control, scenario: String, locale: String, window_size: Vector2i, spec: Dictionary
) -> bool:
	var workspace: Control = main.get_node("Root/Content/Workspace")
	var canvas: Control = workspace.get_node("InfiniteCanvas")
	var inspector: Control = workspace.get_node("ContextInspector")
	if LocalizationService.current_locale != locale:
		_fail("Screenshot locale assertion failed", LocalizationService.current_locale)
		return false
	var logical_size_error := (main.size - Vector2(window_size)).abs()
	if logical_size_error.x > 1.0 or logical_size_error.y > 1.0:
		_fail(
			"Logical window assertion failed",
			{
				"main": main.size,
				"requested": window_size,
				"viewport": get_viewport().get_visible_rect(),
				"window": DisplayServer.window_get_size(),
				"minimum": get_window().min_size,
				"content_scale": get_tree().root.content_scale_factor,
			}
		)
		return false
	if not is_equal_approx(canvas.camera_zoom, float(spec["zoom"])):
		_fail("Camera zoom assertion failed", canvas.camera_zoom)
		return false
	var zoom_label: Label = canvas.get_node("ZoomControl/ZoomRow/ZoomLabel")
	if zoom_label.text != "%d%%" % roundi(float(spec["zoom"]) * 100.0):
		_fail("Zoom label assertion failed", zoom_label.text)
		return false
	var drawer_expected := scenario in ["overlay", "inspector"]
	if inspector.visible != drawer_expected:
		_fail("Inspector visibility assertion failed", inspector.visible)
		return false
	if drawer_expected and not workspace.is_inspector_overlay():
		_fail("Inspector must overlay in the requested screenshot", workspace.size.x)
		return false
	for action_id in [
		"file", "add_input", "import_reference", "run_selection", "export", "inspector", "more"
	]:
		if _action_count(main, action_id) != 1:
			_fail("Toolbar action uniqueness assertion failed", action_id)
			return false
	match scenario:
		"batch_12_13":
			if not canvas._items_by_id.has("batch_12") or not canvas._items_by_id.has("batch_13"):
				_fail("12/13 result cards were not ready")
				return false
			var twelve: Node = canvas._items_by_id["batch_12"]
			var thirteen: Node = canvas._items_by_id["batch_13"]
			if twelve._rows() != 3 or thirteen._rows() != 4:
				_fail("12/13 row boundary assertion failed", [twelve._rows(), thirteen._rows()])
				return false
		"batch_50":
			if not canvas._items_by_id.has("batch_50"):
				_fail("50 result card was not ready")
				return false
			var batch: Node = canvas._items_by_id["batch_50"]
			if (
				batch.get_visible_asset_ids().size() != 50
				or batch._columns() != 5
				or batch._rows() != 10
			):
				_fail("50 result expansion assertion failed")
				return false
			if batch.asset_index_at_world(batch.position + batch._slot_rect(49).get_center()) != 49:
				_fail("50 result tail hit assertion failed")
				return false
	return true


func _save_image(image: Image, output_path: String) -> bool:
	var absolute_output := ProjectSettings.globalize_path(output_path)
	var output_dir := absolute_output.get_base_dir()
	var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_error != OK:
		_fail("Could not create screenshot directory", {"error": dir_error, "path": output_dir})
		return false
	var save_error := image.save_png(absolute_output)
	if save_error != OK:
		_fail("Could not save screenshot", {"error": save_error, "path": absolute_output})
		return false
	return true


func _save_metadata(
	main: Control, scenario: String, requested_locale: String, window_size: Vector2i, path: String
) -> bool:
	var workspace: Control = main.get_node("Root/Content/Workspace")
	var canvas: Control = workspace.get_node("InfiniteCanvas")
	var inspector: Control = workspace.get_node("ContextInspector")
	var batch_counts := {}
	var card_bounds := {}
	for item_id in canvas._items_by_id:
		var item: Node = canvas._items_by_id[item_id]
		var bounds: Rect2 = item.get_canvas_bounds()
		card_bounds[String(item_id)] = [
			bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y
		]
		if item.has_method("get_visible_asset_ids"):
			batch_counts[String(item_id)] = item.get_visible_asset_ids().size()
	var inspector_rect := []
	if inspector.visible:
		var rect := inspector.get_global_rect()
		inspector_rect = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var metadata := {
		"scenario": scenario,
		"requested_locale": requested_locale,
		"actual_locale": LocalizationService.current_locale,
		"png_size": [window_size.x, window_size.y],
		"ui_scale": main._interface_scale,
		"camera_zoom": canvas.camera_zoom,
		"zoom_index": canvas.zoom_index,
		"zoom_label": canvas.get_node("ZoomControl/ZoomRow/ZoomLabel").text,
		"drawer_rect": inspector_rect,
		"drawer_mode":
		(
			"overlay"
			if inspector.visible and workspace.is_inspector_overlay()
			else ("dock" if inspector.visible else "closed")
		),
		"window_pixel_size": [get_window().size.x, get_window().size.y],
		"toolbar_mode": String(main.get_node("Root/TopBar").get_meta("layout_mode", "unknown")),
		"batch_counts": batch_counts,
		"card_bounds": card_bounds,
	}
	var absolute_path := ProjectSettings.globalize_path(path)
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if dir_error != OK:
		_fail("Could not create screenshot metadata directory", dir_error)
		return false
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not open screenshot metadata", FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(metadata, "\t"))
	return true


func _physical_size(logical_size: Vector2i, interface_scale: float) -> Vector2i:
	return Vector2i(
		roundi(float(logical_size.x) * interface_scale),
		roundi(float(logical_size.y) * interface_scale),
	)


func _register_assets(count: int, prefix: String) -> Array[String]:
	var result: Array[String] = []
	for index in range(count):
		result.append(
			AssetLibrary.register_image(
				_fixture_image(index),
				"%s-%02d" % [prefix, index + 1],
				{"origin": "generated_fixture"}
			)
		)
	return result


func _fixture_image(seed: int) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var red := float((x * 17 + seed * 23) % 256) / 255.0
			var green := float((y * 19 + seed * 31) % 256) / 255.0
			var blue := float(((x + y) * 13 + seed * 47) % 256) / 255.0
			var alpha := 0.55 if (x + y + seed) % 11 == 0 else 1.0
			image.set_pixel(x, y, Color(red, green, blue, alpha))
	return image


func _action_count(root: Node, action_id: String) -> int:
	var count := 0
	for node in root.find_children("*", "Control", true, false):
		if String(node.get_meta("action_id", "")) == action_id:
			count += 1
	return count


func _build_legacy_project() -> bool:
	var fixture: Dictionary = Fixture.build()
	ProjectService.new_project(String(fixture["manifest_name"]))
	var graph_data: Dictionary = fixture["graphs"][Fixture.GRAPH_ID]
	var reference_ids := [
		AssetLibrary.register_image(_reference_image(Color.CORNFLOWER_BLUE), "reference_a"),
		AssetLibrary.register_image(_reference_image(Color.DARK_ORANGE), "reference_b"),
	]
	for node in graph_data["nodes"]:
		var node_id := String(node.get("id", ""))
		if node_id == "reference_a":
			node["params"]["asset_id"] = reference_ids[0]
		elif node_id == "reference_b":
			node["params"]["asset_id"] = reference_ids[1]
	var runner := GraphRunnerScript.new()
	for batch_id in ["batch_a", "batch_b"]:
		var result: Dictionary = runner.run_to_batch(
			GraphScript.from_json(graph_data), AssetLibrary, batch_id, false
		)
		if not bool(result.get("ok", false)):
			_fail("Fixture generation failed", result)
			return false
		graph_data = result["graph"]
	ProjectService.set_graph_data(Fixture.GRAPH_ID, graph_data, true)
	ProjectService.set_canvas_data(fixture["canvas"], true)
	return true


func _reference_image(color: Color) -> Image:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return image


func _fail(message: String, detail: Variant = null) -> void:
	Log.error(message, detail)
	get_tree().quit(1)
