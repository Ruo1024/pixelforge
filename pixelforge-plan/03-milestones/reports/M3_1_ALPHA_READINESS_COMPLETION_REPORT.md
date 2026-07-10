# M3.1 受邀 Alpha 可用性收口完成报告

> 共享增量报告：AR-1～AR-3 依序追加。报告只记录 diff 范围与验证证据，不内联整份最终源码。

## Goal 元信息

- Goal 基线：`bdfeafc`
- Goal 分支：`codex/m3-1-alpha-goal`
- 合并状态：尚未合并 `main`
- 推送状态：尚未 push
- 人工状态：待统一人工验收

## 2026-07-11 AR-1 数据安全底线

### 服务的用户动作与原痛点

- 用户在有未保存工作时执行 New、选择 Open 文件或关闭窗口；此前三个入口会直接破坏内存状态或退出。
- 启动恢复信号在 autoload `_ready()` 阶段发出，主 UI 建立后可能已错过。
- 恢复 autosave 后，项目路径直接指向 autosave 文件，后续 Save 会把恢复副本当成普通项目目标。
- 保存、打开、自动保存失败主要只有日志，用户不知道原因和下一步。

### 本轮实现

- 新增统一项目生命周期守卫，New / Open / Quit 共用 Save / Discard / Cancel；Save 失败时保留待执行动作，不继续 New/Open/Quit。
- 关闭自动接受退出，由主窗口在守卫通过后才清理 session lock 并退出。
- ProjectService 缓存待恢复 autosave，主 UI 连接完成后主动读取，消除启动时序丢信号。
- 新增 `recover_project()`：恢复内容作为 dirty 的未保存副本打开，`project_path` 为空且记录 `recovered_from_path`；Save 必须让用户选择新目标，成功后才清除恢复来源。
- 保存、打开、自动保存失败均显示路径、简短错误和可执行下一步；日志只保留诊断证据。
- 新增 M3.1 统一本地门禁脚本，并守护图片与本地参考目录红线。

### 修改文件

- `pixel/services/pf_project.gd`
- `pixel/services/project_service.gd`
- `pixel/ui/shell/project_lifecycle_guard.gd`
- `pixel/ui/shell/main.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/tests/unit/test_project_lifecycle_guard.gd`
- `pixel/tests/integration/test_project_roundtrip.gd`
- `pixel/tests/smoke/test_project_lifecycle_ui.gd`
- `pixel/scripts/verify_m3_1.sh`
- `pixel/CHANGELOG.md`
- 本报告

### 自动验证命令与结果

- `./pixel/scripts/lint.sh`：116 个 GDScript 文件零问题。
- `./pixel/scripts/run_tests.sh`：184/184 tests、1423 assertions 通过。
- 覆盖：三个 dirty 入口各自的 Save / Discard / Cancel；Save 失败不继续；clean 项目直接执行；恢复通知跨启动时序到达；恢复副本保存目标；原项目字节不变；保存/打开/自动保存失败反馈。
- `./pixel/scripts/check_ui_scaling.sh`：通过。
- `./pixel/scripts/verify_m3_1.sh`：通过；含 lint、全量测试、UI 缩放守护、headless startup 与 staged 红线检查。
- `git diff --check`：提交前运行并记录最终结果。

### Agent 实机冒烟

- 环境：macOS Retina，Godot 4.6.3，真实独立 Debug 窗口，界面倍率 2.0。
- 生成 Mock Batch 形成 dirty 状态后点击 New：显示 Save / Discard / Cancel；Cancel 保留画布与 dirty 标记。
- 点击窗口关闭：显示同一守卫，动作名称为 Quit；Cancel 保留画布，应用没有退出。
- 本节只记 agent 实机冒烟，不算用户人工签收。

### 统一人工测试需要覆盖

1. 分别对 dirty 项目执行 New / Open / Quit，逐一验证 Save / Discard / Cancel。
2. 对无路径项目选择 Save，取消文件对话框；预期破坏性动作取消、原工作保留。
3. 模拟不可写保存目标；预期显示原因与 Save As 建议，New/Open/Quit 不继续。
4. 强杀后重启并恢复；预期恢复提示可靠出现，恢复项目带 dirty 标记。
5. 对恢复项目按 Save；预期必须选择新文件名，默认带 `_recovered`，原项目不被覆盖。
6. 模拟打开失败与自动保存失败；预期 UI 显示路径、原因和下一步，不依赖日志。

人工状态：**待统一人工验收**。

### 已知失败与明确延期

- 强杀恢复、无写权限路径、Open/Quit 全分支仍需用户统一人工验收；本轮自动化和 agent 冒烟不能替代签收。
- Godot 4.6.3 export templates 尚未安装；AR-3 候选构建前处理，不把当前 startup fallback 写成候选构建通过。
- 既有 GUT 1 个 orphan 与退出资源警告仍存在，本轮没有新增用户影响证据。

### 本地提交与 diff

- 对应本地提交：`M3.1 guard unsaved project lifecycle`（哈希以 Goal 分支日志为准；提交对象不能在自身内容中可靠自引用）。
- diff 模式：新增生命周期守卫、服务恢复状态与失败信号、主窗口接线、自动化、门禁脚本和集中字符串；不内联全量源码。
