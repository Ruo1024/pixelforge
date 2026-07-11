class_name PFAnimation
extends RefCounted

## Lightweight frame animation whose frames remain independent AssetLibrary assets.

const IdUtil := preload("res://core/util/id_util.gd")

var id := ""
var name := "Animation"
var frames: Array = []
var durations_ms: Array = []
var loop := true
var tags: Array = []
var extra := {}


func _init(anim_name: String = "Animation") -> void:
	id = IdUtil.uuid_v4()
	name = anim_name


func configure(frame_ids: Array, frame_durations_ms: Array, should_loop: bool = true) -> bool:
	if frame_ids.is_empty() or frame_ids.size() != frame_durations_ms.size():
		return false
	frames = []
	durations_ms = []
	for index in range(frame_ids.size()):
		var frame_id := String(frame_ids[index])
		if frame_id.is_empty():
			return false
		frames.append(frame_id)
		durations_ms.append(maxi(1, int(frame_durations_ms[index])))
	loop = should_loop
	return true


func get_duration_ms() -> int:
	var total := 0
	for duration in durations_ms:
		total += int(duration)
	return total


func get_frame_index(time_ms: int, offset_ms: int = 0) -> int:
	if frames.is_empty():
		return -1
	var total := get_duration_ms()
	if total <= 0:
		return 0
	var local_time := maxi(0, time_ms + offset_ms)
	if loop:
		local_time %= total
	else:
		local_time = mini(local_time, total - 1)
	var cursor := 0
	for index in range(durations_ms.size()):
		cursor += int(durations_ms[index])
		if local_time < cursor:
			return index
	return frames.size() - 1


func get_frame_asset_id(time_ms: int, offset_ms: int = 0) -> String:
	var index := get_frame_index(time_ms, offset_ms)
	return String(frames[index]) if index >= 0 else ""


func to_json() -> Dictionary:
	var data: Dictionary = extra.duplicate(true)
	(
		data
		. merge(
			{
				"id": id,
				"name": name,
				"frames": frames.duplicate(),
				"durations_ms": durations_ms.duplicate(),
				"loop": loop,
				"tags": tags.duplicate(true),
			},
			true
		)
	)
	return data


static func from_json(data: Dictionary) -> PFAnimation:
	var animation := PFAnimation.new(String(data.get("name", "Animation")))
	animation.id = String(data.get("id", animation.id))
	animation.extra = data.duplicate(true)
	for known_key in ["id", "name", "frames", "durations_ms", "loop", "tags"]:
		animation.extra.erase(known_key)
	animation.tags = data.get("tags", []).duplicate(true)
	animation.configure(
		Array(data.get("frames", [])),
		Array(data.get("durations_ms", [])),
		bool(data.get("loop", true))
	)
	return animation
