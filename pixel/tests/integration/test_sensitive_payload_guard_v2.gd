extends "res://addons/gut/test.gd"

const Clipboard := preload("res://core/graph/canvas_graph_clipboard.gd")
const FileIO := preload("res://infra/file_io.gd")
const Scanner := preload("res://tests/helpers/credential_sentinel_scanner.gd")
const OpenAIProviderScript := preload("res://plugins/provider_openai/openai_image_provider.gd")

const PROJECT_PATH := "user://tests/b7_sensitive_v2.pxproj"

var _provider: PFOpenAIImageProvider = null


func before_each() -> void:
	ProjectService.new_project("Sensitive v2 surfaces")
	AssetLibrary.clear()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	_provider = OpenAIProviderScript.new()
	assert_null(_provider.configure({"api_key": Scanner.VALUE}))


func after_each() -> void:
	_provider.clear_session_config()
	if FileAccess.file_exists(PROJECT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROJECT_PATH))


func test_sentinel_only_reaches_transport_not_v2_persistence() -> void:
	var graph := _graph_fixture()
	graph["nodes"][0]["params"]["extra"]["authorization_hint"] = Scanner.VALUE
	(
		ProjectService
		. set_canvas_data(
			{
				"camera": {"center": [0, 0], "zoom": 1.0},
				"items":
				[
					{
						"id": "item-generate",
						"type": "node",
						"graph_id": "graph-main",
						"node_id": "generate",
						"position": [100, 100],
						"z_index": 1,
						"collapsed": false,
						"locked": false,
						"frame_id": null,
					}
				],
			},
			false
		)
	)
	var clipboard := Clipboard.capture(
		graph,
		ProjectService.current_project.canvas["items"],
		["item-generate"],
		ProjectService.current_project.get_id()
	)
	assert_true(clipboard.get("ok", false), JSON.stringify(clipboard))
	assert_false(Scanner.contains(clipboard, Scanner.VALUE))
	ProjectService.set_graph_data("graph-main", _graph_fixture(), false)

	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color("4f6f8f"))
	(
		AssetLibrary
		. register_image(
			image,
			"generated-safe",
			{
				"id": "asset-generated-safe",
				"origin": "generated",
				"provenance":
				{
					"graph_id": "graph-main",
					"created_at": "2026-07-14T00:00:00Z",
					"generation_snapshot": _generation_snapshot_with_sentinel(),
				},
			}
		)
	)
	assert_false(Scanner.contains(AssetLibrary.get_all_meta(), Scanner.VALUE))
	assert_eq(ProjectService.save_project(PROJECT_PATH), OK)
	var unpacked: Dictionary = FileIO.zip_unpack(PROJECT_PATH)
	assert_true(unpacked.get("ok", false), JSON.stringify(unpacked))
	assert_false(Scanner.contains(unpacked.get("files", {}), Scanner.VALUE))


func _graph_fixture() -> Dictionary:
	return {
		"graph_version": 2,
		"id": "graph-main",
		"name": "Safe graph",
		"nodes":
		[
			{
				"id": "generate",
				"type": "ai_generate",
				"params":
				{
					"provider_id": "openai_image",
					"model_id": "gpt-image-2",
					"target_width": 32,
					"target_height": 32,
					"batch_size": 1,
					"seed": -1,
					"extra": {"quality": "low"},
				},
			}
		],
		"edges": [],
	}


func _generation_snapshot() -> Dictionary:
	return {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"mode": "txt2img",
		"target_width": 32,
		"target_height": 32,
		"provider_output_size": [1024, 1024],
		"actual_width": 2,
		"actual_height": 2,
		"requested_seed": -1,
		"actual_seed": null,
		"run_id": "run-safe",
		"request_id": "request-safe",
		"source_node_id": "generate",
		"source_row_id": "",
		"prompt_preset_id": "",
		"prompt_prefix": "",
		"prompt": "safe prompt",
		"reference_asset_ids": [],
		"reference_content_sha256s": [],
		"extra": {"quality": "low"},
	}


func _generation_snapshot_with_sentinel() -> Dictionary:
	var snapshot := _generation_snapshot()
	snapshot["extra"]["authorization_hint"] = Scanner.VALUE
	return snapshot
