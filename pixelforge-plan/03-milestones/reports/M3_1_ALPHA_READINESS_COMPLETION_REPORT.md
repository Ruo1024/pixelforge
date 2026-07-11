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

## 2026-07-11 AR-2 首次任务与关键反馈

### 服务的用户动作与原痛点

- 陌生用户面对空画布时缺少低干扰入口；旧首次启动提示是模态对话框。
- 文件对话框导入在关闭后读取鼠标位置，真实大图可能落到意外位置；逐文件解码和注册会在中途失败时留下半成品。
- 1254×1254 输入的预览可能完成后仍显示 `Preview queued`；M2 任务未统一处理 progress / cancel / failure。
- 导出没有明确完整路径、打开目录入口或部分产物说明，覆盖行为也没有可自动验证的应用级状态。

### 本轮实现

- 空画布改为居中的低干扰 Import Images 提示，不再弹 M2.1 模态 onboarding；拖放入口保留。
- 文件对话框入口在选择文件前就使用当前视图中心作为稳定世界坐标；空画布自动 fit，新内容在已有工作区不强制缩放，并提供 `File > Focus Last Import`。
- 导入先完成全部格式/解码预检，再统一注册；任一文件失败则本轮零素材、零画布元素，并显示失败文件与 Retry Import。
- 清洗预览新增 5%/100% progress、完成/取消/失败状态；清洗、抠图、切分、描边与 batch 任务统一接 progress / canceled / failed。清洗完成会取消选择变化触发的陈旧预览，最终状态稳定为 `Cleanup complete`。
- 导出流程独立为控制器：应用级覆盖确认可选择 Cancel/Overwrite；成功显示完整路径和 Open Folder；失败摘要区分已生成与未生成文件。

### 修改文件

- `pixel/ui/shell/import_flow_controller.gd`
- `pixel/ui/shell/empty_canvas_import_hint.gd`
- `pixel/ui/shell/export_flow_controller.gd`
- `pixel/ui/shell/m2_1_ui_controller.gd`
- `pixel/ui/shell/m2_action_controller.gd`
- `pixel/ui/shell/main.gd`
- `pixel/ui/inspector/cleanup_inspector.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/tests/smoke/test_alpha_first_task_ui.gd`
- `pixel/CHANGELOG.md`
- `pixelforge-plan/03-milestones/CURRENT-STATE.md`
- 本报告

### 自动验证命令与结果

- 定向 `test_alpha_first_task_ui.gd`：5/5 tests、34 assertions 通过。
- `./pixel/scripts/lint.sh`：120 个 GDScript 文件零问题。
- `./pixel/scripts/run_tests.sh`：189/189 tests、1457 assertions 通过。
- 覆盖：空画布入口；对话框稳定落点；导入预检原子性与失败文件；空/非空画布聚焦策略；1254×1254 preview queued → running → done；任务取消；清洗完成状态不被预览覆盖；导出成功路径、Open Folder、覆盖 Cancel/Overwrite、部分产物失败摘要。
- `./pixel/scripts/check_ui_scaling.sh`：通过。
- `./pixel/scripts/verify_m3_1.sh`：通过；含 staged 图片与受保护目录红线。
- `git diff --check`：提交前通过。

### Agent 实机冒烟

- 环境：macOS Retina，Godot 4.6.3，界面倍率 2.0；使用本地未授权测试目录中的一张真实 1254×1254 图片，仅本机读取，未复制、未 stage、未 commit。
- 空画布显示低干扰提示；从提示进入文件对话框后，真实图立即出现在视图中并合理 fit。
- preview 状态从 5% 进入 `Cleanup preview ready`，不再卡在 queued。
- Apply Cleanup 显示 queued/进度，产出在原图旁可见，最终状态稳定为 `Cleanup complete`。
- 导出到 `/tmp/pixelforge-ar2-smoke.png` 后显示完整路径和 Open Folder；再次导出同名文件时显示 Cancel / Overwrite，Cancel 保留现有文件。
- 本节只记 agent 实机冒烟，不算用户人工签收。

### 统一人工测试需要覆盖

1. 空画布通过提示导入 1 张真实图；预期立即可见、合理 fit，落点不受文件对话框关闭时鼠标位置影响。
2. 已有工作区再导入 1–5 张；预期不强制改变缩放，`File > Focus Last Import` 可返回新内容。
3. 同时选择一个有效文件和一个损坏/不支持文件；预期列出失败文件、提供 Retry Import，且不新增任何半成品。
4. 用真实 1254×1254 图执行 preview 与 Apply Cleanup；预期 queued、进行中、完成状态准确，最终不回退为 `Preview queued/ready`。
5. 在可取消清洗任务进行中点击 Cancel Cleanup；预期显示 canceled、按钮恢复，不物化未完成结果。
6. 分别执行单图 PNG 与多图 spritesheet 导出；预期成功摘要包含完整路径并可打开目录。
7. 对已有导出选择 Cancel 与 Overwrite；预期 Cancel 不改文件，Overwrite 更新产物。
8. 模拟 spritesheet JSON 写失败；预期明确 PNG 是否已存在、JSON 未生成及重试建议。

人工状态：**待统一人工验收**。

### 已知失败与明确延期

- 真实图片仅用于 agent 本机冒烟；用户完整最小旅程、取消时机手感、文件管理器打开结果仍待统一人工验收。
- 现有 WorkerThreadPool 采用协作式取消，不强杀正在运行的算法；界面已准确显示当前能力，本轮不扩张底层抢占机制。
- Godot export templates 仍待 AR-3 准备。
- 既有 GUT 1 个 orphan 与退出资源警告保持已知；本轮无新增用户影响证据。

### 本地提交与 diff

- 对应本地提交：`M3.1 close first task feedback loop`（哈希以 Goal 分支日志为准；提交对象不能在自身内容中可靠自引用）。
- diff 模式：抽离 import/export 流程控制器，补任务状态接线、集中字符串、smoke 自动化与状态/报告增量；不内联全量源码。

## 2026-07-11 AR-3 macOS 候选构建与统一验收准备

### 版本与候选

- 应用版本、项目设置与 README 同步为 `0.1.0-alpha.1`；范围只声明 macOS 受邀 alpha 候选，不声明公开发布或跨平台完成。
- 安装与 Godot 4.6.3 精确匹配的官方 macOS export template；先后修正 universal 导出所需 ETC2/ASTC 与 bundle identifier 配置。
- 候选：本地忽略文件 `pixel/build/PixelForge-0.1.0-alpha.1-macOS.zip`，64,761,252 bytes。
- SHA-256：`c3704e0d2d6d0dcb71e9c9a02b40a4a6657028e4c6b912d08d6ecde2f00baa8d`。
- 构建未签名、未公证、未上传；符合本卡明确延期范围，测试者若被 Gatekeeper 阻断须如实登记失败点。

### 包红线与可复现门禁

- 新增 `tests/fixtures/real/.gdignore`，从 Godot import/export 资源索引源头隔离本地未授权图片；Git 的图片红线保持不变。
- staged 红线只为该固定 `.gdignore` 安全标记开例外；同目录任何其他新增文件仍会失败，所有 PNG/JPG 仍由扩展名门禁无条件拒绝。
- `build_macos_alpha.sh` 校验版本、模板、可执行文件，解析 Godot PCK 的权威目录而不是仅 grep 压缩字节，并检查 ZIP/PCK 均无 `test picture/` 或 `tests/fixtures/real/` 条目。
- 首次 all-resources 构建被审计正确拦截，确认包曾包含 3 个 real fixture；该失败包已被后续成功构建覆盖，不作为候选。
- “仅主场景依赖”尝试虽通过图片审计，但干净启动发现 preload 脚本缺失，亦判失败并覆盖。最终方案保留完整运行时资源，并由 `.gdignore` 结构性隔离受保护目录。
- 构建脚本会解包候选，以全新 HOME/APPDATA/LOCALAPPDATA headless 启动并对 `SCRIPT ERROR` / `ERROR:` 失败关闭。
- 最终 `./pixel/scripts/verify_m3_1.sh`：189/189 tests、1457 assertions 通过；真实 fixture 回归在 `.gdignore` 存在时仍由 `FileAccess` 正常读取，UI 缩放和已安装 export template 检查通过。

### Agent 候选实机冒烟

- 环境：macOS Retina、Godot 4.6.3 universal 导出、临时干净用户目录、导出后的独立 `PixelForge.app`（bundle id `org.pixelforge.alpha`）。
- 独立窗口正常显示空画布低干扰导入提示；导入本地 `/tmp` 冒烟 PNG 后立即可见并自动 fit。
- Apply Cleanup 生成结果，最终状态为 `Cleanup complete`；PNG 导出到 `/tmp/pixelforge-alpha1-smoke.png`，界面显示完整路径与 Open Folder。
- 项目保存到 `/tmp/pixelforge-alpha1-smoke.pxproj`，New 清空后通过 Open 重开，原图与清洗结果均恢复可见。
- 本节只算 agent 冒烟，不算陌生测试者人工签收，也不记录“首次导出时间”产品指标。

### 统一人工验收材料与当前出口结论

- 一页说明：`pixel/docs/manual-test-m3_1-alpha.md`；只给候选与该页，不口头教学。
- 每人原样记录：是否 15 分钟内独立完成、首次成功导出用时、是否愿意处理下一批、数据丢失/找不到导入内容/任务无反馈、失败点与自恢复情况。
- 需要至少 3 名未参与开发的目标用户参加，且至少 2/3 在 15 分钟内无需口头指导完成；当前尚未执行，因此 `QUALITY.md` 对应项保持未通过。
- 用户还需统一覆盖既有 `a9003ab` 快速添加落点、AR-1 New/Open/Quit 与强杀恢复、AR-2 真实输入/取消/导出失败，以及本 AR-3 候选旅程。

人工状态：**待统一人工验收；M3.1 受邀 alpha 尚未通过**。

### 本地提交与 diff

- 对应本地提交：`M3.1 prepare macOS alpha candidate`（哈希以 Goal 分支日志为准）。
- diff 模式：版本/README、导出预设、构建与 PCK 审计脚本、受保护目录导入隔离、一页测试说明、当前状态与本报告增量；不内联全量源码，不提交候选 ZIP。

## 2026-07-11 长期 Goal 继承审计

- M3 工程收口提交 `d6efb6e`、M3.1 AR-1～AR-3 提交 `8c2afab..531aa86` 均为长期 Goal 起点 `44a5081` 的祖先；报告与 Git diffstat 可对账。
- `./pixel/scripts/verify_m4_v1.sh` 复用并通过 `verify_m3_1.sh`：197/197 tests、1515 assertions；M3.1 包红线、UI 缩放、模板和 headless 启动门均通过。
- 候选 ZIP 仍是本地忽略产物，未 stage、未 commit、未上传；本次审计没有触碰保留目录或未授权图片。
- 人工状态保持：**待最终统一验收；M3.1 受邀 alpha 尚未通过**。
- 长期分支 `codex/pixelforge-full-plan-goal` 只继承这些本地提交；main 保持 `bdfeafc`，origin/main 保持 `a9003ab`，没有 merge 或 push。
