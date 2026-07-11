extends "res://addons/gut/test.gd"

const AnimationScript := preload("res://core/animation/pf_animation.gd")


func test_animation_roundtrip_loop_and_offsets_are_deterministic() -> void:
	var animation := AnimationScript.new("Flame")
	assert_true(animation.configure(["a", "b", "c"], [100, 200, 100], true))
	animation.extra["future_animation_field"] = [1, 2, 3]
	assert_eq(animation.get_duration_ms(), 400)
	assert_eq(animation.get_frame_asset_id(0), "a")
	assert_eq(animation.get_frame_asset_id(100), "b")
	assert_eq(animation.get_frame_asset_id(350), "c")
	assert_eq(animation.get_frame_asset_id(400), "a")
	assert_eq(animation.get_frame_asset_id(0, 100), "b")

	var loaded := AnimationScript.from_json(animation.to_json())
	assert_eq(loaded.to_json(), animation.to_json())
	assert_eq(loaded.to_json()["future_animation_field"], [1, 2, 3])


func test_animation_rejects_mismatched_or_empty_frames() -> void:
	var animation := AnimationScript.new()
	assert_false(animation.configure([], [], true))
	assert_false(animation.configure(["a"], [100, 100], true))
