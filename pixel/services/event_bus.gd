class_name PFEventBus
extends Node

## 全局事件总线。
## UI 模块之间不直接互相引用；跨模块消息集中在这里声明，便于新手查找事件来源。
## 命名约定：按 project / asset / canvas / task 分组；事件用过去式或状态变化后缀
## （如 saved、added、changed）；参数顺序优先 id/path，再放结果对象或状态值。

signal project_created(project_id: String)
signal project_opened(path: String)
signal project_saved(path: String)
signal project_dirty_changed(is_dirty: bool)
signal recovery_available(autosaves: Array)
signal asset_added(asset_id: String)
signal asset_removed(asset_id: String)
signal canvas_changed
signal workflow_templates_changed
signal task_started(task_id: String, kind: String)
signal task_progressed(task_id: String, ratio: float, message: String)
signal task_finished(task_id: String, result: Variant)
signal task_failed(task_id: String, error: Dictionary)
signal task_canceled(task_id: String)
