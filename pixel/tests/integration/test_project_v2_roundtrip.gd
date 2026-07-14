extends "res://addons/gut/test.gd"

const FileIO := preload("res://infra/file_io.gd")

const PATH_A := "user://tests/b7_project_v2_a.pxproj"
const PATH_B := "user://tests/b7_project_v2_b.pxproj"
const UUID_V4_PATTERN := "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))


func before_each() -> void:
	ProjectService.new_project("Project v2")
	_remove_paths()


func after_each() -> void:
	_remove_paths()


func test_manifest_identity_and_no_global_style() -> void:
	var first_id: String = ProjectService.current_project.get_id()
	assert_true(_matches(UUID_V4_PATTERN, first_id), first_id)
	ProjectService.current_project.manifest["style_preset"] = {"id": "legacy-style"}
	ProjectService.current_project.manifest["prompt_preset"] = {"id": "global-prompt"}
	ProjectService.current_project.manifest["cleanup_preset"] = {"id": "global-cleanup"}

	assert_eq(ProjectService.save_project(PATH_A), OK)
	assert_eq(ProjectService.save_project(PATH_B), OK)
	var manifest_a := _zip_json(PATH_A, "manifest.json")
	var manifest_b := _zip_json(PATH_B, "manifest.json")
	assert_eq(String(manifest_a.get("id", "")), first_id)
	assert_eq(String(manifest_b.get("id", "")), first_id)
	for forbidden in ["style_preset", "prompt_preset", "cleanup_preset"]:
		assert_false(manifest_a.has(forbidden), "manifest retained %s" % forbidden)
		assert_false(manifest_b.has(forbidden), "Save As retained %s" % forbidden)

	ProjectService.new_project("Second v2 project")
	var second_id: String = ProjectService.current_project.get_id()
	assert_true(_matches(UUID_V4_PATTERN, second_id), second_id)
	assert_ne(second_id, first_id)


func test_output_domain_lives_only_in_graph() -> void:
	ProjectService.set_graph_data("graph-main", _graph_with_output())
	var canvas_item := _display_item()
	(
		canvas_item
		. merge(
			{
				"role": "current",
				"source_node_id": "generate",
				"source_run_id": "run-1",
				"input_snapshots": {"snapshot-1": {"kind": "generation"}},
				"request_records": [{"request_id": "request-1"}],
				"result_slots": [{"slot_id": "slot-1"}],
				"review_filter": "kept",
				"focus_asset_id": "asset-generated",
				"compare_asset_ids": ["asset-a", "asset-b"],
			}
		)
	)
	ProjectService.set_canvas_data(
		{"camera": {"center": [0, 0], "zoom": 1.0}, "items": [canvas_item]}
	)

	assert_eq(ProjectService.save_project(PATH_A), OK)
	var graph := _zip_json(PATH_A, "graphs/graph-main.json")
	var canvas := _zip_json(PATH_A, "canvas/canvas.json")
	var graph_params: Dictionary = graph["nodes"][0]["params"]
	assert_eq(graph_params, _output_params())
	var saved_item: Dictionary = canvas["items"][0]
	assert_eq(_sorted_keys(saved_item), _sorted_keys(_display_item()))
	assert_eq(saved_item, _display_item())
	for graph_only in [
		"role",
		"source_node_id",
		"source_run_id",
		"input_snapshots",
		"request_records",
		"result_slots",
		"review_filter",
		"focus_asset_id",
		"compare_asset_ids",
	]:
		assert_false(saved_item.has(graph_only), "canvas retained Graph field %s" % graph_only)


func test_canvas_keeps_only_display_fields() -> void:
	ProjectService.set_graph_data("graph-main", _graph_with_output())
	ProjectService.set_canvas_data(
		{"camera": {"center": [19, -7], "zoom": 1.5}, "items": [_display_item()]}
	)
	assert_eq(ProjectService.save_project(PATH_A), OK)
	assert_eq(ProjectService.open_project(PATH_A), OK)
	var saved_item: Dictionary = ProjectService.current_project.canvas["items"][0]
	assert_eq(saved_item["display_title"], "Generated props")
	assert_eq(saved_item["size"], [720, 488])
	assert_true(saved_item["collapsed"])
	assert_eq(saved_item["position"], [320, 160])
	assert_eq(saved_item["z_index"], 4)
	assert_eq(saved_item["frame_id"], null)
	for graph_only in _output_params().keys():
		assert_false(saved_item.has(graph_only), "canvas duplicated %s" % graph_only)


func test_generation_provenance_exact_fields() -> void:
	var image := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	image.fill(Color("4f6f8f"))
	var expected_snapshot := {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"mode": "txt2img",
		"target_width": 32.0,
		"target_height": 24.0,
		"provider_output_size": [1024.0, 1024.0],
		"actual_width": 8.0,
		"actual_height": 6.0,
		"requested_seed": -1.0,
		"actual_seed": 2147483647.0,
		"run_id": "run-1",
		"request_id": "request-1",
		"source_node_id": "generate",
		"source_row_id": "row-a",
		"prompt_preset_id": "prompt-hibit",
		"prompt_prefix": "pixel art,",
		"prompt": "pixel art, wooden barrel",
		"reference_asset_ids": ["reference-a", "reference-b"],
		"reference_content_sha256s": ["a".repeat(64), "b".repeat(64)],
		"extra": {"quality": "low"},
	}
	var unsafe_snapshot := expected_snapshot.duplicate(true)
	unsafe_snapshot["negative_prompt"] = "private negative prompt"
	unsafe_snapshot["authorization"] = "Bearer secret"
	var asset_id := (
		AssetLibrary
		. register_image(
			image,
			"Generated barrel",
			{
				"origin": "generated",
				"provenance":
				{
					"graph_id": "graph-main",
					"created_at": "2026-07-14T08:00:00Z",
					"generation_snapshot": unsafe_snapshot,
				},
			}
		)
	)

	assert_eq(ProjectService.save_project(PATH_A), OK)
	assert_eq(ProjectService.open_project(PATH_A), OK)
	var meta: Dictionary = AssetLibrary.get_asset_meta(asset_id)
	assert_eq(meta["origin"], "generated")
	assert_eq(_sorted_keys(meta["provenance"]), ["created_at", "generation_snapshot", "graph_id"])
	var snapshot: Dictionary = meta["provenance"]["generation_snapshot"]
	assert_eq(_sorted_keys(snapshot), _sorted_keys(expected_snapshot))
	assert_eq(snapshot, expected_snapshot)
	assert_eq(snapshot["reference_asset_ids"].size(), snapshot["reference_content_sha256s"].size())
	assert_false(meta.has("generation_snapshot"))
	assert_false(JSON.stringify(meta).contains("private negative prompt"))
	assert_false(JSON.stringify(meta).contains("Bearer secret"))


func _graph_with_output() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Project v2",
		"nodes": [{"id": "output", "type": "batch", "params": _output_params()}],
		"edges": [],
	}


func _output_params() -> Dictionary:
	return {
		"label": "Generated props",
		"source_node_id": "",
		"source_run_id": "",
		"role": "standalone",
		"input_snapshots": {},
		"request_records": [],
		"result_slots": [],
	}


func _display_item() -> Dictionary:
	return {
		"id": "canvas-output",
		"type": "node",
		"graph_id": "graph-main",
		"node_id": "output",
		"position": [320, 160],
		"z_index": 4,
		"display_title": "Generated props",
		"size": [720, 488],
		"collapsed": true,
		"locked": false,
		"frame_id": null,
	}


func _zip_json(path: String, entry: String) -> Dictionary:
	var unpacked: Dictionary = FileIO.zip_unpack(path)
	assert_true(unpacked.get("ok", false), JSON.stringify(unpacked))
	assert_true(unpacked.get("files", {}).has(entry), entry)
	var parsed: Variant = FileIO.bytes_to_json(unpacked["files"][entry])
	assert_true(parsed is Dictionary, entry)
	return parsed if parsed is Dictionary else {}


func _sorted_keys(value: Dictionary) -> Array:
	var keys := value.keys()
	keys.sort()
	return keys


func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


func _remove_paths() -> void:
	for path in [PATH_A, PATH_B]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
