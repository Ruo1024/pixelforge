class_name PFM2ActionController
extends RefCounted

## M2 批量动作控制器。
## 职责：把 shell 顶栏命令接到 TaskQueue，并把抠图/切分/描边结果登记为新素材。
## main.gd 只保留窗口搭建与通用项目命令，避免主窗口脚本继续膨胀。

const Strings := preload("res://ui/shell/strings.gd")
const TaskScript := preload("res://services/pf_task.gd")
const Matting := preload("res://core/pixel/matting.gd")
const Segmenter := preload("res://core/pixel/segmenter.gd")
const PixelOperations := preload("res://services/pixel_operations.gd")
const ErrorHelper := preload("res://ui/dialogs/error_helper.gd")

const CLEANUP_RESULT_GAP := 8

var _canvas: Control = null
var _cleanup_inspector: Control = null
var _status_label: Label = null
var _dialog_parent: Node = null
var _task_id := ""


func setup(
	canvas: Control, cleanup_inspector: Control, status_label: Label, dialog_parent: Node = null
) -> void:
	_canvas = canvas
	_cleanup_inspector = cleanup_inspector
	_status_label = status_label
	_dialog_parent = dialog_parent


func matte_selection() -> void:
	matte_selection_with_params({})


func matte_selection_with_params(params: Dictionary) -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new(
		"pixel_matting", {"items": snapshots, "params": params}, _matting_work
	)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_MATTING_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_MATTING_QUEUED


func slice_selection() -> void:
	slice_selection_with_params({})


func slice_selection_with_params(params: Dictionary) -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new("pixel_slicing", {"items": snapshots, "params": params}, _slice_work)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_SLICE_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_SLICE_QUEUED


func outline_selection() -> void:
	outline_selection_with_params({})


func outline_selection_with_params(params: Dictionary) -> void:
	var snapshots := _selected_snapshots()
	if snapshots.is_empty():
		return

	var task := TaskScript.new(
		"pixel_outline", {"items": snapshots, "params": params}, _outline_work
	)
	task.finished.connect(
		func(result: Variant) -> void:
			_on_generated_asset_task_finished(result, Strings.STATUS_OUTLINE_DONE)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_OUTLINE_QUEUED


func batch_cleanup(card_id: String, asset_ids: Array, params: Dictionary) -> void:
	_start_batch_task(
		card_id,
		asset_ids,
		"batch_cleanup",
		{"params": params},
		_batch_cleanup_work,
		Strings.STATUS_CLEANUP_QUEUED,
		Strings.STATUS_CLEANUP_DONE
	)


func batch_matte(card_id: String, asset_ids: Array, params: Dictionary) -> void:
	_start_batch_task(
		card_id,
		asset_ids,
		"batch_matting",
		{"params": params},
		_batch_matte_work,
		Strings.STATUS_MATTING_QUEUED,
		Strings.STATUS_MATTING_DONE
	)


func batch_outline(card_id: String, asset_ids: Array, params: Dictionary) -> void:
	_start_batch_task(
		card_id,
		asset_ids,
		"batch_outline",
		{"params": params},
		_batch_outline_work,
		Strings.STATUS_OUTLINE_QUEUED,
		Strings.STATUS_OUTLINE_DONE
	)


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
	var params: Dictionary = _matte_params(task_ref.payload.get("params", {}))
	var results := []
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var operation_result: Dictionary = PixelOperations.apply_image(
			PixelOperations.OP_MATTING, item["image"], params
		)
		operation_result["source_data"] = item["data"]
		results.append(operation_result)
		task_ref.report_progress(float(index + 1) / float(items.size()), "matting")
	return {"canceled": false, "items": results}


func _slice_work(task_ref: Variant) -> Dictionary:
	var items: Array = task_ref.payload["items"]
	var params: Dictionary = _slice_params(task_ref.payload.get("params", {}))
	var matte_first := bool(params.get("matte_first", true))
	var matte_params: Dictionary = params.get("matte_params", {})
	var segment_params: Dictionary = params.get("segment_params", {})
	var results := []
	var total_steps := maxi(1, items.size())
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var slice_source: Image = item["image"]
		if matte_first:
			var matte_result: Dictionary = Matting.matte(item["image"], matte_params)
			if bool(matte_result.get("is_flat_bg", false)):
				slice_source = matte_result["image"]
		var segments: Array = Segmenter.segment(slice_source, segment_params)
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
	var params: Dictionary = _outline_params(task_ref.payload.get("params", {}))
	var results := []
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}
		var item: Dictionary = items[index]
		var operation_result: Dictionary = PixelOperations.apply_image(
			PixelOperations.OP_OUTLINE, item["image"], params
		)
		operation_result["source_data"] = item["data"]
		results.append(operation_result)
		task_ref.report_progress(float(index + 1) / float(items.size()), "outline")
	return {"canceled": false, "items": results}


func _batch_cleanup_work(task_ref: Variant) -> Dictionary:
	var asset_ids: Array = task_ref.payload["asset_ids"]
	var params: Dictionary = task_ref.payload["extra"].get("params", {})
	var result := PixelOperations.apply_to_assets(
		asset_ids,
		AssetLibrary,
		PixelOperations.OP_CLEANUP,
		params,
		func() -> bool: return task_ref.cancel_requested,
		func(ratio: float, _operation: String) -> void:
			task_ref.report_progress(ratio, "batch_cleanup")
	)
	result["card_id"] = String(task_ref.payload["card_id"])
	return result


func _batch_matte_work(task_ref: Variant) -> Dictionary:
	var asset_ids: Array = task_ref.payload["asset_ids"]
	var params: Dictionary = _matte_params(task_ref.payload["extra"].get("params", {}))
	var result := PixelOperations.apply_to_assets(
		asset_ids,
		AssetLibrary,
		PixelOperations.OP_MATTING,
		params,
		func() -> bool: return task_ref.cancel_requested,
		func(ratio: float, _operation: String) -> void:
			task_ref.report_progress(ratio, "batch_matting")
	)
	result["card_id"] = String(task_ref.payload["card_id"])
	return result


func _batch_outline_work(task_ref: Variant) -> Dictionary:
	var asset_ids: Array = task_ref.payload["asset_ids"]
	var params: Dictionary = _outline_params(task_ref.payload["extra"].get("params", {}))
	var result := PixelOperations.apply_to_assets(
		asset_ids,
		AssetLibrary,
		PixelOperations.OP_OUTLINE,
		params,
		func() -> bool: return task_ref.cancel_requested,
		func(ratio: float, _operation: String) -> void:
			task_ref.report_progress(ratio, "batch_outline")
	)
	result["card_id"] = String(task_ref.payload["card_id"])
	return result


func _on_generated_asset_task_finished(result: Variant, done_status: String) -> void:
	_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_cleanup_inspector.set_selection_count(_canvas.get_selected_ids().size())
	if not (result is Dictionary) or bool(result.get("canceled", false)):
		return

	var first_warning := _first_warning(result.get("items", []))
	if not first_warning.is_empty():
		ErrorHelper.show_matte_error(_dialog_parent, first_warning)

	var placement_offsets := {}
	for item_result in result.get("items", []):
		var source_data: Dictionary = item_result["source_data"]
		var parent_asset_id := String(source_data.get("asset_id", ""))
		var output: Image = item_result["image"]
		var source_position := _position_from_canvas_data(source_data)
		var source_width := _source_width_for_canvas_data(source_data, output)
		var placement_index := int(placement_offsets.get(parent_asset_id, 0))
		placement_offsets[parent_asset_id] = placement_index + 1
		var asset_id := PixelOperations.register_result_asset(
			AssetLibrary, parent_asset_id, item_result
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


func _start_batch_task(
	card_id: String,
	asset_ids: Array,
	task_kind: String,
	extra: Dictionary,
	work: Callable,
	queued_status: String,
	done_status: String
) -> void:
	var ids := _string_array(asset_ids)
	if ids.is_empty():
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
		return
	var task := TaskScript.new(
		task_kind, {"card_id": card_id, "asset_ids": ids, "extra": extra}, work
	)
	task.finished.connect(
		func(result: Variant) -> void: _on_batch_task_finished(result, done_status)
	)
	_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = queued_status


func _on_batch_task_finished(result: Variant, done_status: String) -> void:
	_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_cleanup_inspector.set_selection_count(_canvas.get_selected_ids().size())
	if not (result is Dictionary) or bool(result.get("canceled", false)):
		return

	var first_warning := _first_warning(result.get("items", []))
	if not first_warning.is_empty():
		ErrorHelper.show_matte_error(_dialog_parent, first_warning)

	var new_asset_ids: Array[String] = []
	var source_asset_ids: Array[String] = []
	for item_result in result.get("items", []):
		var parent_asset_id := String(item_result.get("parent_asset", ""))
		var asset_id := PixelOperations.register_result_asset(
			AssetLibrary, parent_asset_id, item_result
		)
		new_asset_ids.append(asset_id)
		source_asset_ids.append(parent_asset_id)

	_canvas._replace_batch_asset_ids(
		String(result.get("card_id", "")), new_asset_ids, true, source_asset_ids
	)
	_status_label.text = done_status


func _matte_params(params: Dictionary) -> Dictionary:
	return PixelOperations.normalize_matte_params(params)


func _slice_params(params: Dictionary) -> Dictionary:
	if params.is_empty():
		return {
			"matte_first": true,
			"matte_params": _matte_params({}),
			"segment_params": {"merge_distance": 2, "min_area": 4},
		}
	return {
		"matte_first": bool(params.get("matte_first", true)),
		"matte_params": _matte_params(params.get("matte_params", {})),
		"segment_params":
		{
			"merge_distance":
			int(Dictionary(params.get("segment_params", {})).get("merge_distance", 2)),
			"min_area": int(Dictionary(params.get("segment_params", {})).get("min_area", 4)),
		},
	}


func _outline_params(params: Dictionary) -> Dictionary:
	return PixelOperations.normalize_outline_params(params)


func _first_warning(items: Array) -> String:
	for item in items:
		var warning := String(Dictionary(item).get("warning", ""))
		if not warning.is_empty():
			return warning
	return ""


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in Array(value):
			result.append(String(item))
	return result


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
