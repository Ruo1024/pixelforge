# PixelForge Beta 0.6 工程报告

> 日期：2026-07-14
>
> 分支：`codex/beta0-6-card-productization`（本地，未合并 `main`、未 push）
>
> 基线：`6338a09 docs: define beta 0.6 card productization`
>
> 最终状态：**工程通过、人工待验、发布未通过**

## 1. 出口结论

| 层级 | 状态 | 依据 |
|---|---|---|
| B6-0 至 B6-8 | 工程通过 | 按冻结的 `1A / 2B / 3C` 连续完成卡片基础、工作区与输入、生成与结果、LOD 与最终证据 |
| 自动化 | 工程通过 | `verify_beta_0_6.sh` 通过；238 个 GDScript lint 通过，390/390 tests、6786/6786 assertions 通过 |
| UI 几何与截图 | 工程通过 | English/简中 × 1080/1280/1440 × 1.0/1.25/1.5 共 18 组几何矩阵通过；7 张固定脚本截图与 manifest 防伪通过 |
| 50 张结果 | 工程通过 | All 筛选下索引 0–49 全部真实存在、绘制、可命中；无分页、无内部滚动、无 `+N` |
| 兼容与往返 | 工程通过 | 旧项目、标题、尺寸、剪贴板、模板、保存重开与 Undo/Redo 自动化通过 |
| macOS 候选 | 工程通过 | 唯一 `PixelForge-0.6.0-beta.1-macOS.zip` 构建、受保护图片审计与干净用户启动通过 |
| 项目所有者人工 | 人工待验 | 仅项目所有者可填写 `manual-test-beta0.6.md` |
| 发布 | 发布未通过 | 未签名公证、未合并 `main`、未 push、未发布 |

本报告中的自动化、脚本截图和 agent 视觉检查只证明工程出口，不替代项目所有者对真实输入、操作手感、字体、跨屏和真实云端的人工签收。

## 2. 冻结产品决定的实现

### 1A：混合卡片语言

- 媒体、独立 Sprite 和结果卡采用内容优先布局；提示词、对象、风格、尺寸、参考集合与生成卡采用结构化内容层级。
- 所有卡片共用 PixelForge 自有颜色、边框、选中态、标题、端口、菜单与缩放手柄 token，没有引入外部代码、CSS、图标、截图、资产、文案或工作流文件。
- 用户可从空画布、工作区顶栏与左侧入口开始，在原位看到过程状态、结果和继续加工入口。

### 2B：改名与自由缩放

- 正式 Graph 卡、兼容旧 Batch 卡和独立 Sprite 内容卡支持单行标题编辑与右下自由缩放。
- 标题清理、80 code point 上限、空标题本地化回退、Enter/失焦提交、Esc 取消、尺寸约束、复制粘贴、模板实例化、保存重开和 Undo/Redo 使用统一语义。
- Frame 复用现有 `title`、`size` 和 Undo，不新增跨模块 schema 字段；保留 Graph、Provider、TaskQueue、项目格式与画布底层。

### 3C：全部结果展开

- 结果卡按有效宽度决定列数并按当前筛选结果自动增高；1、12、13、50 张及多个宽度都有定向测试。
- 50 张结果为 50 个真实格子和真实命中目标，序号 1–50 连续；All 下没有分页、卡内滚动或折叠尾项。
- 任务未完成时按 `max(已有结果数, expected_count)` 保留真实占位几何，结果到达时不造成外框跳动。

## 3. 工作区、响应式入口与过程反馈

- 顶栏高 52、左侧栏宽 48、项目标题槽最大 280 并省略显示完整 tooltip；全局动作在紧凑和标准模式都保持唯一且可达。
- 上下文检查器宽 360；窗口宽度 `>=1440` 时停靠，更窄时以不透明覆盖层显示，不改变画布相机中心和倍率。
- 输入与生成卡展示真实项目/Graph 数据；Provider、模型、参考、尺寸、批量、seed、费用和任务状态继续走现有服务与 i18n 访问层。
- 生成结果保留既有等待、运行、完成、失败、取消、重试与结果继续分支旅程；未调用真实付费 API。

## 4. LOD、Frame、端口与几何不变量

| 倍率 | 工程语义 |
|---|---|
| 10% | Map：只保留空间关系和主要状态，不开放卡片编辑交互 |
| 25% | Overview：独立大号 Frame 标题、卡片类型/状态与主要关系 |
| 50% | Browse：独立 24/20px 摘要层、媒体/结果预览；无端口和缩放手柄 |
| 75%–300% | Edit：完整正文、标题编辑、端口、操作与缩放手柄 |
| 400% | Inspect：保留完整编辑并显示像素检查层级 |

- LOD 只改变绘制与可用动作，不改变卡片世界尺寸、端口锚点、连线端点或 Frame 归属。
- 端口可见半径恒为屏幕空间 6px，命中半径为 20px；75% 以下不能开始连线。
- 低 LOD 双击卡片会居中并进入 100%；双击 Frame 使用不超过适配值的最近离散倍率并居中，不重置 Frame 尺寸。
- 加载保存为 50% 的项目后，画布倍率、离散索引、滑块和 `50%` 标签在同一帧一致。

## 5. 自动化与静态门

最终命令：

```bash
./pixel/scripts/verify_beta_0_6.sh
```

结果：

- `lint.sh`：238 files，no problems found。
- GUT：75 scripts，390 tests，390 passing，6786 assertions。
- `check_i18n_catalogs.sh`：通过。
- `check_ui_scaling.sh`：通过。
- `check_export_templates.sh`：隔离 HOME 中未发现模板时按既有 M0 口径验证 headless 启动；实际构建使用本机 Godot 4.6.3 官方 macOS 模板。
- `capture_beta_0_6.sh` 与 `beta_0_6_evidence.py`：7/7 截图、尺寸、mtime、颜色分布、非背景比例、唯一 SHA、场景元数据和精确文件集通过。
- `git diff --check` 与 staged raster 守护：通过。
- 基线提示保持 1 个既有 `error_tracker.gd` orphan 与退出资源提示；没有测试失败或数量增长。

全量回归前发现的两处红灯均在当前切片内清零：检查器测试的旧 420px 断言更新为冻结的 360px 规格；18 组矩阵测试补齐根窗口缩放清理，消除后续拖拽测试污染。定向回归 51/51、2422 assertions 通过后才重新执行完整门禁。

## 6. 固定截图证据

证据位于被忽略的 `scratch/beta-evidence/beta-0.6/`，不纳入 git：

| 文件 | 场景 | SHA-256 |
|---|---|---|
| `1080x560-en-100-closed.png` | English、100%、紧凑工作区 | `64202d31b07b955c6f7743b12f98d2085711979acad0115727e89e5b6e7819ec` |
| `1080x560-zh-50-overlay.png` | 简中、50%、覆盖检查器 | `db70fe932fa14658415ef1c5b66af34b1ded47fbd059421fca742c96726ca9a6` |
| `1280x720-en-50-batch-12-13.png` | 12/13 张结果自动增高边界 | `53ba1994611aed94c00eabf6a6f7d5c322109619a08e3e3ee70aaf1c769bed4b` |
| `1280x720-zh-100-inspector.png` | 简中、100%、检查器覆盖 | `5c0f2709d34af8f7875f863dd7f05e5bb06250fefc8a9dd0dd5fa13dc9918882` |
| `1440x900-en-50-batch-50-all.png` | All 下 50 张完整展开 | `e37cfed3c825765b3d7450f80c5b73b4d3b294b5aa729d4ffabaa324ac65403e` |
| `1440x900-zh-100-card-families.png` | 简中结构卡与内容卡家族 | `1484dd7a8d0b69bb6e2390405c31cf5f995130cae0d625d79009396762261d45` |
| `1440x900-en-400-inspect.png` | English、400% Inspect | `068e7ce6ebfa95d498e7c44a4ea70554ff5b3771852c9796445c103dc56369f2` |

截图由脚本固定构造，不含受保护真实图片；没有使用 Computer Use。截图只用于工程几何和信息层级证据。

## 7. 唯一 macOS 候选

- 产物：`pixel/build/PixelForge-0.6.0-beta.1-macOS.zip`，78,171,527 bytes。
- SHA-256：`9e230a8e577ade62046d307221a2360b8a14c7baf53956398aaaa5ee19eb05eb`。
- 校验文件：`pixel/build/PixelForge-0.6.0-beta.1-macOS.zip.sha256`。
- Godot：4.6.3 stable 官方 macOS 导出模板。
- ZIP 与 PCK 中的 `test picture/`、`tests/fixtures/real/` 受保护路径审计通过。
- 解包后的 `PixelForge.app` 在全新用户目录 headless 启动通过，启动日志没有 `SCRIPT ERROR` 或 `ERROR`。
- 导出器扫描临时副本时打印一条 ObjectDB Profiler 快照目录创建失败的非致命编辑器环境提示；导出命令退出 0，归档、PCK、安全审计及候选启动均通过。该提示不来自候选运行路径。
- 候选未签名、公证或发布。

## 8. Git 与保护状态

四个完整切片为：

1. `854acfc feat: establish beta 0.6 card foundation`
2. `01b9e5c feat: productize beta 0.6 workspace and inputs`
3. `abe6483 feat: connect beta 0.6 generation and results`
4. LOD 与最终证据：本报告、最终脚本和 LOD 实现随最终本地提交交付。

开发在独立 worktree 与 `codex/` 分支完成。原工作区项目所有者的 `pixel/project.godot` 修改未覆盖、未暂存、未撤销、未提交。没有修改或纳入 `垃圾桶/`、`godot-interactive-guide/`、`test picture/`、`pixel/tests/fixtures/real/`；没有 push 或合并 `main`。

## 9. 后续唯一动作

停止工程开发，等待项目所有者使用唯一候选执行 `manual-test-beta0.6.md`。项目所有者填写人工结果并给出 `go / 修复后复验 / 整体不合并`；任何合并或 push 仍需另行明确授权。
