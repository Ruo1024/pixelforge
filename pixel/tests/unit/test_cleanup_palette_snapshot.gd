extends "res://addons/gut/test.gd"

const BUILDER_PATH := "res://services/cleanup_run_plan_builder.gd"
const PaletteRegistryScript := preload("res://core/pixel/palette_registry.gd")
const PaletteScript := preload("res://core/pixel/palette.gd")


func test_palette_hash_and_freeze() -> void:
	assert_true(ResourceLoader.exists(BUILDER_PATH), "B7-6 must add cleanup palette snapshots")
	if not ResourceLoader.exists(BUILDER_PATH):
		return
	var custom := PaletteScript.new("custom_freeze", "Freeze", [Color.RED, Color(0, 1, 0, 0.5)])
	PaletteRegistryScript.register_custom_palette(custom, {"preserve_id": true})
	var first: Dictionary = load(BUILDER_PATH).freeze_palette({"enabled": true, "mode": "fixed_palette", "palette_id": "custom_freeze"})
	assert_true(first.get("ok", false))
	assert_eq(first["snapshot"]["palette_id"], "custom_freeze")
	assert_eq(first["snapshot"]["colors_rgba8"], ["#FF0000FF", "#00FF0080"])
	assert_eq(first["snapshot"]["content_sha256"].length(), 64)
	PaletteRegistryScript.unregister_custom_palette("custom_freeze")
	assert_eq(first["snapshot"], first["snapshot"].duplicate(true), "the run owns a detached immutable-value snapshot")
	var missing: Dictionary = load(BUILDER_PATH).freeze_palette({"enabled": true, "mode": "fixed_palette", "palette_id": "does-not-exist"})
	assert_false(missing.get("ok", false))
	assert_eq(missing.get("issue", {}).get("code"), "missing_cleanup_palette")


func test_quantize_disabled_freezes_null_palette() -> void:
	if not ResourceLoader.exists(BUILDER_PATH):
		return
	var result: Dictionary = load(BUILDER_PATH).freeze_palette({"enabled": false, "mode": "none", "palette_id": "custom"})
	assert_true(result.get("ok", false))
	assert_null(result.get("snapshot"))
