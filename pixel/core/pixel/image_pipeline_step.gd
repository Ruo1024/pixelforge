class_name PFImagePipelineStep
extends RefCounted

## 图像管线步骤描述。
## 每个步骤只通过 context 字典交换 image/params/report，便于后续插入或跳过算法。

var id := ""
var label := ""
var enabled_by_default := true
var work_callable := Callable()


func _init(
	p_id: String = "",
	p_label: String = "",
	p_enabled_by_default: bool = true,
	p_work_callable: Callable = Callable()
) -> void:
	id = p_id
	label = p_label
	enabled_by_default = p_enabled_by_default
	work_callable = p_work_callable


func is_enabled(params: Dictionary) -> bool:
	var step_params: Dictionary = params.get(id, {})
	return bool(step_params.get("enabled", enabled_by_default))


func apply(context: Dictionary) -> Dictionary:
	if not work_callable.is_valid():
		return context
	return work_callable.call(context)
