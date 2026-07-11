extends "res://addons/gut/test.gd"


func before_each() -> void:
	ProjectService.new_project("Asset Library")
	var asset_library := get_tree().root.get_node("AssetLibrary")
	asset_library.clear()


func test_cache_byte_estimate_matches_rgba8_buffer_size() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var source := Image.create(4, 3, false, Image.FORMAT_RGB8)
	source.fill(Color(0.25, 0.5, 0.75, 1.0))

	var rgba := source.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)

	assert_eq(asset_library.estimate_cache_bytes(source), rgba.get_data().size())


func test_registered_image_cache_counts_rgba8_bytes() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)

	asset_library.register_image(image, "cache-bytes")

	assert_eq(asset_library.get_cache_bytes(), image.get_data().size())


func test_cache_eviction_uses_least_recently_used_order() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	asset_library.configure_cache_limit(image.get_data().size() * 2)

	var first_id: String = asset_library.register_image(image, "first")
	var second_id: String = asset_library.register_image(image, "second")
	assert_eq(asset_library.get_cached_asset_ids(), [first_id, second_id])

	assert_not_null(asset_library.get_image(first_id))
	var third_id: String = asset_library.register_image(image, "third")

	assert_eq(asset_library.get_cached_asset_ids(), [first_id, third_id])
	assert_false(asset_library.get_cached_asset_ids().has(second_id))


func test_board_and_animation_references_block_asset_deletion() -> void:
	var asset_library := get_tree().root.get_node("AssetLibrary")
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var asset_id: String = asset_library.register_image(image, "referenced")
	(
		ProjectService
		. set_document_data(
			"boards",
			"board_ref",
			{
				"id": "board_ref",
				"layers": [{"kind": "tile", "cells": {"0,0": {"asset_id": asset_id}}}],
			}
		)
	)
	assert_eq(asset_library.remove_asset(asset_id), ERR_BUSY)
	ProjectService.remove_document("boards", "board_ref")
	ProjectService.set_document_data(
		"animations",
		"anim_ref",
		{"id": "anim_ref", "frames": [asset_id], "durations_ms": [100], "loop": true}
	)
	assert_eq(asset_library.remove_asset(asset_id), ERR_BUSY)
