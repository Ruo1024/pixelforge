class_name PFM2ActionController
extends RefCounted

## M2 批量动作控制器。
## 职责：把 shell 顶栏命令接到 TaskQueue，并把抠图/切分/描边结果登记为新素材。
## main.gd 只保留窗口搭建与通用项目命令，避免主窗口脚本继续膨胀。

const Strings := preload("res://ui/shell/strings.gd")
const TaskScript := preload("res://services/pf_task.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Segmenter := preload("res://core/pixel/segmenter.gd")
const Outliner := preload("res://core/pixel/outliner.gd")

const CLEANUP_RESULT_GAP := 8

var _canvas: Control = null
var _cleanup_inspector: Control = null
var _status_label: Label = null
var _task_id := ""


func setup(canvas: Control, cleanup_inspector: Control, status_label: Label) -> void:
	_canvas = canvas
	_cleanup_inspector = cleanup_inspector
	_status_label = status_label


func matte_selection() -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new("pixel_matting", {"items": snapshots}, _matting_work)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_MATTING_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_MATTING_QUEUED


func slice_selection() -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new("pixel_slicing", {"items": snapshots}, _slice_work)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_SLICE_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_SLICE_QUEUED


func outline_selection() -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new("pixel_outline", {"items": snapshots}, _outline_work)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_OUTLINE_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_OUTLINE_QUEUED


func cancel_current_task() -> bool:
	if _task_id.is_empty():
		return false
	TaskQueue.cancel(_task_id)
	return true


func _selected_snapshots() -> Array:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.is_empty():
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
	return snapshots


func _matting_work(task_ref: Variant) -> Dictionary:
	var items: Array = task_ref.payload["items"]
	var results := []
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var matting_result: Dictionary = Matting.matte(
			item["image"], {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
		)
		(
			results
			. append(
				{
					"source_data": item["data"],
					"image": matting_result["image"],
					"suffix": "matte",
					"tags": ["matting"],
					"provenance_key": "matting",
					"report": _json_safe(matting_result),
				}
			)
		)
		task_ref.report_progress(float(index + 1) / float(items.size()), "matting")
	return {"canceled": false, "items": results}


func _slice_work(task_ref: Variant) -> Dictionary:
	var items: Array = task_ref.payload["items"]
	var results := []
	var total_steps := maxi(1, items.size())
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var matte_result: Dictionary = Matting.matte(
			item["image"], {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
		)
		var slice_source: Image = (
			matte_result["image"] if bool(matte_result.get("is_flat_bg", false)) else item["image"]
		)
		var segments: Array = Segmenter.segment(slice_source, {"merge_distance": 2, "min_area": 4})
		for segment_index in range(segments.size()):
			var segment: Dictionary = segments[segment_index]
			(
				results
				. append(
					{
						"source_data": item["data"],
						"image": segment["image"],
						"suffix": "slice_%02d" % (segment_index + 1),
						"tags": ["matting", "slicing"],
						"provenance_key": "slice",
						"report": {"rect": _rect_to_array(segment["rect"]), "index": segment_index},
					}
				)
			)
		task_ref.report_progress(float(index + 1) / float(total_steps), "slicing")
	return {"canceled": false, "items": results}


func _outline_work(task_ref: Variant) -> Dictionary:
	var items: Array = task_ref.payload["items"]
	var results := []
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var output: Image = Outliner.add_outline(
			item["image"], {"type": Outliner.TYPE_OUTER, "color": Color.BLACK}
		)
		(
			results
			. append(
				{
					"source_data": item["data"],
					"image": output,
					"suffix": "outline",
					"tags": ["outline"],
					"provenance_key": "outline",
					"report": {"type": Outliner.TYPE_OUTER, "color": Color.BLACK.to_html(true)},
				}
			)
		)
		task_ref.report_progress(float(index + 1) / float(items.size()), "outline")
	return {"canceled": false, "items": results}


func _on_generated_asset_task_finished(result: Variant, done_status: String) -> void:
	_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_cleanup_inspector.set_selection_count(_canvas.get_selected_ids().size())
	if not (result is Dictionary) or bool(result.get("canceled", false)):
		return

	var placement_offsets := {}
	for item_result in result.get("items", []):
		var source_data: Dictionary = item_result["source_data"]
		var parent_asset_id := String(source_data.get("asset_id", ""))
		var output: Image = item_result["image"]
		var source_position := _position_from_canvas_data(source_data)
		var source_width := _source_width_for_canvas_data(source_data, output)
		var placement_index := int(placement_offsets.get(parent_asset_id, 0))
		placement_offsets[parent_asset_id] = placement_index + 1

		var provenance_key := String(item_result.get("provenance_key", "operation"))
		var provenance := {
			"provider": null,
			"model": null,
			"prompt": "",
			"seed": null,
			"parent_asset": parent_asset_id,
			"graph_id": null,
			"created_at": IdUtil.utc_now_iso(),
		}
		provenance[provenance_key] = _json_safe(item_result.get("report", {}))

		var asset_id := (
			AssetLibrary
			. register_image(
				output,
				"%s_%s" % [parent_asset_id.left(8), String(item_result.get("suffix", "m2"))],
				{
					"origin": "edited",
					"tags": item_result.get("tags", []),
					"provenance": provenance,
				}
			)
		)
		var world_position := (
			source_position
			+ Vector2(
				source_width + CLEANUP_RESULT_GAP,
				placement_index * (output.get_height() + CLEANUP_RESULT_GAP)
			)
		)
		_canvas.add_sprite_item(output, asset_id, world_position)

	_status_label.text = done_status


static func _position_from_canvas_data(data: Dictionary) -> Vector2:
	var raw_position: Array = data.get("position", [0, 0])
	return Vector2(float(raw_position[0]), float(raw_position[1]))


static func _source_width_for_canvas_data(data: Dictionary, fallback_image: Image) -> int:
	var source_width := fallback_image.get_width()
	if AssetLibrary.has_asset(String(data.get("asset_id", ""))):
		var source_image := AssetLibrary.get_image(String(data["asset_id"]))
		if source_image != null:
			source_width = source_image.get_width()
	return source_width


static func _rect_to_array(rect: Rect2i) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var output := {}
			for key in Dictionary(value).keys():
				output[String(key)] = _json_safe(Dictionary(value)[key])
			return output
		TYPE_ARRAY:
			var output := []
			for item in Array(value):
				output.append(_json_safe(item))
			return output
		TYPE_VECTOR2:
			var vector := Vector2(value)
			return [vector.x, vector.y]
		TYPE_VECTOR2I:
			var vector_i := Vector2i(value)
			return [vector_i.x, vector_i.y]
		TYPE_RECT2I:
			return _rect_to_array(Rect2i(value))
		TYPE_COLOR:
			return Color(value).to_html(true)
		_:
			return value
