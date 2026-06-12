# M0 — 工程骨架 + 无限画布底座

> 目标：可运行的空壳应用：主窗口 + 无限画布（平移/缩放/拖图入画布）+ 项目保存/打开 + 本地 agent 验证全绿。
> 依赖：无。本里程碑是一切的地基，质量要求最高。

## 2026-06-12 执行口径补充

当前仓库 M0 出口门控采用**本地 agent 验证**，暂不启用 GitHub Actions。原因是项目维护者选择由本地 agent 自动跑完整脚本，并把结果写入交付文档。后续如果重新启用 GitHub Actions，需要同步 README、`QUALITY.md` 和本文件的出口说明。

本地 agent 统一入口：

```bash
cd pixel
./scripts/verify_m0.sh
```

`verify_m0.sh` 必须顺序执行：

1. `./scripts/lint.sh`
2. `./scripts/run_tests.sh`
3. `./scripts/check_export_templates.sh`

Windows fresh clone 不要求人工先 import；`run_tests.sh` 会先执行 `godot --headless --import --quit`，并把 `HOME`、`APPDATA`、`LOCALAPPDATA` 隔离到项目内 `.godot/home`。

M0 精简索引见 `pixel/docs/m0-brief.md`；完整完成报告见 `pixel/M0_COMPLETION_REPORT.md`。

### 精简实施流程

1. 核对目录和 autoload：`services/` 必须是顶级目录，`project.godot` 的服务路径必须指向 `res://services/*.gd`。
2. 核对基础服务：`SettingsService`、`ProjectService`、`AssetLibrary`、`TaskQueue`、`UndoService`、`EventBus`、`Logger` 都应存在且在报告中列明。
3. 核对项目格式：保存的 `.pxproj` 必须是标准 ZIP，至少包含 `manifest.json`、`canvas/canvas.json`、`assets/*.png`、`assets/*.meta.json`。
4. 核对测试分层：`tests/unit`、`tests/integration`、`tests/smoke`、`tests/fixtures` 必须存在；M1 开始时补 `tests/fixtures/generators/`。
5. 运行 `./scripts/verify_m0.sh`，把结果写入 `M0_COMPLETION_REPORT.md`。
6. Windows 结果以 `pixel/docs/m0-windows-test-summary.md` 和 `pixel/docs/manual-test-m0.md` 为准；当前性能采样不作为 M0 门控。

---

## M0-1 工程初始化与规范落地

**目标**：建立 git 仓库与 Godot 4.6 工程，目录骨架、lint、测试、本地 agent 验证一步到位。

**技术实现指导**：
- 按 ARCHITECTURE.md §3 创建全部目录（空目录放 `.gitkeep`）。
- `project.godot`：项目名占位 PixelForge；渲染器 **Forward+**（桌面目标；若后续低端机反馈差再评估 Compatibility，记录在 README）；窗口 1440×900 可缩放；`low_processor_usage_mode = true`（工具类应用必须，省电关键）；纹理默认 filter = Nearest（全局像素清晰）。
- `core/util/app_info.gd`：`const APP_NAME`, `APP_VERSION`，全部 UI 标题从这里读。
- 安装 GUT 到 `addons/gut/`；写一个自检测试 `tests/unit/test_sanity.gd`（断言 1+1=2）验证测试链路。
- gdtoolkit 配置文件 + `scripts/lint.sh`。
- 本地 agent 验证：`scripts/verify_m0.sh` 跑 lint + headless 测试（`godot --headless -s addons/gut/gut_cmdln.gd`）+ headless/export-template 检查。
- `CHANGELOG.md`、`.gitignore`（Godot 模板 + `user://` 无关）。

**涉及文件**：全仓库骨架。
**验收标准**：
1. `godot --headless --quit` 无报错启动退出。
2. 本地 agent 三阶段（lint/test/headless-export-check）全绿。
3. 仓库根有 README 简述目录结构（从 ARCHITECTURE.md 摘要）。

---

## M0-2 基础设施层：日志、设置、文件 IO

**目标**：infra 四件套可用且有单测。

**技术实现指导**：
- `logger.gd`（autoload）：分级 debug/info/warn/error；同时写 `user://logs/app_{date}.log`（滚动保留 7 天）与控制台；**全局禁止裸 print**（lint 规则加一条自定义检查脚本）。
- `settings_service.gd`（autoload）：包装 ConfigFile 于 `user://settings.cfg`；典型键：界面语言、最近项目列表、任务并发数。change 信号。
- `file_io.gd`：静态工具类。`save_png(image, path)`、`load_png(path) -> Image`、`zip_pack(dir_map: Dictionary, path)`、`zip_unpack(path) -> Dictionary`（用 ZIPPacker/ZIPReader）、`atomic_write(path, bytes)`（tmp+rename）。
- `http_client.gd`：本卡只建文件与接口签名（M4 实现），避免 M4 改动 infra 目录结构。

**验收标准**：
1. 单测：zip 打包→解包内容一致；原子写中断模拟（写 tmp 后不 rename）不损坏原文件；PNG round-trip 像素一致。
2. 日志文件按日期生成。

---

## M0-3 无限画布核心交互

**目标**：丝滑的无限画布：平移、缩放、元素增删选移、像素对齐。这是用户 80% 时间停留的界面，体验 > 功能数量。

**技术实现指导**：
- 场景结构：`InfiniteCanvas (SubViewportContainer 或直接 Node2D 树) > Camera2D + ItemLayer (Node2D) + OverlayLayer (CanvasLayer, 选框/网格/角标)`。
- 缩放：滚轮以鼠标位置为锚点缩放，档位 `[0.125, 0.25, 0.5, 1, 2, 4, 8, 16, 32]`（整数倍优先，像素清晰）；**缩放后元素纹理必须最近邻**（CanvasItem texture_filter = NEAREST 全树默认）。
- 平移：空格+拖拽 / 中键拖拽；触控板双指（InputEventPanGesture）。
- 元素（canvas_item_sprite.gd）：包 ImageTexture；选中描边（OverlayLayer 画，不改元素本身）；拖动吸附整数坐标；Shift 多选、框选；Del 删除（经 undo_service）。
- 性能（架构 §7 预算）：视口外元素 `visible=false` 剔除（每帧脏检查或定时 0.1s）；500 元素 60fps 验收。
- 网格显示：zoom ≥ 4 时叠加 1px 像素网格线（shader 或 draw_rect，注意性能）。
- 拖文件入窗口（`get_window().files_dropped`）：PNG → 创建元素于鼠标位；带 EXIF/大图（>1024²）提示将在 M1 清洗（本卡只导入原图）。
- **本卡不做**：编组框、note、graph_anchor（M3）；只做 sprite 元素。

**验收标准**：
1. 手动脚本化冒烟测试（GUT 场景测试）：实例化画布→加 500 个 64×64 随机图元素→模拟平移缩放→帧时间 < 16ms（用 Performance.get_monitor 断言宽松上限 33ms 防自动化环境波动）。Windows headless 的 `TIME_PROCESS` 暂不作为 M0 门控，性能债登记到后续。
2. 缩放任意档位截图（headless RenderingServer 截图）：元素边缘无模糊（相邻像素无中间色——可编程断言：放大后颜色集合不超原图颜色集合）。
3. 增删移操作 Ctrl+Z/Ctrl+Shift+Z 完整可逆。

---

## M0-4 项目模型与保存/打开

**目标**：实现 PROJECT-FORMAT.md 契约 v1：新建/保存/打开/自动保存。

**技术实现指导**：
- `project_service.gd`（autoload）：内存模型 `PFProject {manifest, canvas_items, assets_index}`；脏标记；保存走 file_io.zip_pack + atomic_write。
- `asset_library.gd`：素材注册（生成 UUID、写 meta dict）、按 id 取 Image（LRU 缓存上限 256MB 字节估算）、引用计数（canvas 引用检查）。
- 自动保存：Timer 3min → `user://autosave/{project_id}/{timestamp}.pxproj` 环形保留 5 份；启动时检测未正常关闭（lock 文件）提示恢复。
- 迁移框架：`MIGRATIONS` 数组就位（空），`format_version` 校验逻辑完整（高于当前版本 → 拒开提示升级 app）。
- UI：欢迎页（最近项目列表）、Ctrl+S/Ctrl+O、标题栏脏标记 `*`。

**验收标准**：
1. 集成测试：建项目→加 3 元素→保存→关闭→重开→canvas/manifest/素材逐字段比对一致。
2. 保存的 .pxproj 用系统 unzip 可解开且 manifest.json 可读（人类可检查性）。
3. kill 进程后重启出现恢复提示，恢复内容正确。

---

## M0-5 任务队列与撤销服务

**目标**：services 层两大机制就位（后续所有里程碑依赖）。

**技术实现指导**：
- `task_queue.gd`（autoload）：按 ARCHITECTURE §4.2 的 PFTask 契约实现。并发槽默认 2；`submit(task)`、`cancel(id)`、信号转发。CPU 任务用 `WorkerThreadPool.add_task` + `call_deferred` 回主线程发信号（**信号必须主线程发**，否则 UI 崩）。
- `undo_service.gd`（autoload）：包装 UndoRedo；`begin_action(name)/commit()`；图像快照辅助 `snapshot_region(image, rect)`。上限 100 步或 512MB（图像快照计费），超限丢最老。
- `event_bus.gd`：纯信号集散（`project_opened`, `asset_added`, `task_progress` 等，按需增补，集中声明加注释）。

**验收标准**：
1. 单测：提交 10 个 sleep 任务并发=2 时按序完成；中途 cancel 的任务不发 finished；进度信号在主线程（断言 `OS.get_thread_caller_id()`）。
2. 单测：undo 栈混合"轻量命令+图像快照"操作 50 步往返，内存计费正确淘汰。

---

## M0 整体验收（里程碑出口）

- 全部任务卡验收标准通过。
- 当前执行口径下，`./scripts/verify_m0.sh` 绿灯等价于 M0 本地 agent 验证通过；若未来启用 GitHub Actions，则恢复 CI 绿灯为出口门控。
- 手动体验脚本（写入 `docs/manual-test-m0.md`）：新建项目→拖入 10 张 PNG→平移缩放排列→保存重开→一致。在 Windows + macOS 实测通过。
- 代码量预估：~3500 行 GDScript。如发现单卡超 800 行，回报拆卡。
