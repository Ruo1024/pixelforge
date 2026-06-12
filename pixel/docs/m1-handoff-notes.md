# M1 Handoff Notes

本文给下一个 agent 解释 M0 地基的设计目的、可依赖契约和仍需登记的风险。M1 开始前建议先读本文件，再读 `pixelforge-plan/03-milestones/M1-cleanup-pipeline.md`。

## 架构边界

- `core/`：纯逻辑和无场景树依赖的工具。M1 的像素算法、裁切、量化和调色板逻辑优先放这里。
- `services/`：应用状态和业务流程。M1 如果需要排队执行批处理，应该通过 `TaskQueue`，不要在 UI 脚本里直接开线程。
- `infra/`：外部能力封装。HTTP/WebSocket 目前是 stub，M4/M7 才实现网络；M1 不应在这里扩展业务逻辑。
- `ui/`：Godot 控件和交互。画布状态已经开始拆分，M1 新增面板时保持 UI 只调用服务，不直接读写压缩包格式。

## TaskQueue

`TaskQueue` 有三个关键目的：

- Worker 内不触碰场景树，进度和完成信号统一回主线程发出。
- 并行任务按提交顺序 flush 完成信号，避免 M1 批量清洗时 UI 乱序刷新。
- running task 的取消是协作式取消，不是线程抢占。`cancel(task_id)` 只设置 `cancel_requested`；`task_canceled` 和 `_running` 清理要等 worker 自然返回。

M1 使用建议：

- 长任务的 work callable 需要定期检查 `task_ref.cancel_requested`，尽快返回。
- 调用方必须等 `task_canceled/task_finished/task_failed` 信号，不要把 `cancel()` 当成同步完成。
- 如果 M1 要显示批处理队列，请以 task id 和提交顺序为 UI 主键。

## UndoService

Undo 动作包含图像快照时，必须显式传入内存成本：

```gdscript
var cost := UndoService.estimate_snapshot_cost(before_image)
UndoService.perform_action("Cleanup", do_cleanup, undo_cleanup, cost)
```

如果一个 action 持有多张图像副本，逐张相加。这个约定是 M1 最容易漏的点：不传 `memory_cost_bytes` 不会立刻报错，但会让 512MB 上限失效。

## ProjectService

`open_project()` 会拒绝高于当前 `AppInfo.PROJECT_FORMAT_VERSION` 的项目，返回 `ERR_FILE_UNRECOGNIZED`。这是为了避免旧 app 静默解析新格式。

M1 如果修改 `.pxproj` 格式：

- 在 `core/util/app_info.gd` 提升 `PROJECT_FORMAT_VERSION`。
- 在 `ProjectService.MIGRATIONS` 增加从旧版本到新版本的迁移 callable。
- 补一个旧格式打开迁移测试，以及一个未来版本拒开测试。

## AssetLibrary

素材缓存统一保存 RGBA8，内存计费为 `width * height * 4`，等价 `Image.get_data().size()`。`get_image()` 返回副本，调用方可以安全修改返回图像，不会污染缓存。

LRU 由 `_lru_order` 维护：每次存入或命中缓存都会把 asset id 移到末尾，超限时从头淘汰。M1 如果增加批量清洗预览，优先复用 asset id，不要绕过 `AssetLibrary` 直接缓存裸 Image。

## Canvas

`infinite_canvas.gd` 保留坐标转换、绘制、Undo 接入和元素管理；选择、拖拽、框选状态已拆到 `canvas_selection.gd`。M3 节点图或 M1 清洗预览需要更多状态时，继续按职责拆文件，不要把所有交互状态塞回主画布。

视口剔除现在同时设置：

- `item.visible`
- `item.set_process(visible)`
- `item.set_physics_process(visible)`

这是为 M1/M2 后续元素动画或进度标记预留的 CPU 保护。

## Logger 和脚本环境

Logger 写 `user://logs/app_YYYY-MM-DD.log`，启动时按文件名日期清理 7 天前日志。测试脚本会把 `HOME` 指向项目内 `.godot/home`，这是为了避免 macOS/沙箱环境下 Godot 初始化日志时写系统目录失败。

`.godot/` 是本地临时目录，不应提交。

## HTTP/WebSocket Stub

`PFHttpClient` 固定了 `request_raw()`、`request_json()`、`cancel_all()` 和结果字典字段。M4 实现时保持 `ok/status_code/headers/body/error/url/method/timeout_seconds` 这些字段。

`PFWsClient` 固定了连接、发送、轮询和关闭签名。不要命名为 `is_connected()`，这个名字会和 Godot `Object.is_connected(signal, callable)` 冲突；当前接口是 `is_socket_connected()`。

## 登记债务

- 像素网格仍是 GDScript `draw_line` 循环。M0 性能测试通过，但 M1 末尾或 M3 前建议改成 shader/ColorRect 方案。
- Windows 11 + Godot 4.6.3 实测仍未在当前机器完成。`docs/manual-test-m0.md` 已列出手动验证项。
- 当前测试为 29 tests / 224 asserts。M1 开始前建议按 M0/M1 任务卡逐条做验收覆盖盘点，尤其是批量图像处理和错误恢复。

## 常用验证命令

```bash
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```
