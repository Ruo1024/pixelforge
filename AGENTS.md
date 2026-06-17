# PixelForge 工作区约定（所有 agent 必读：Claude / Codex / 其他）

## 文件落点
- 代码只写入 `pixel/`，计划与报告只写入 `pixelforge-plan/`。
- 里程碑/修复完成报告 → `pixelforge-plan/03-milestones/reports/`。
- 算法研究 → `pixelforge-plan/04-research/`；外部算法参考 → `pixelforge-plan/06-algorithm-refs/`。
- 临时文件/草稿 → `scratch/`（已 gitignore）。禁止在仓库根目录新建文件。
- `垃圾桶/`、`godot-interactive-guide/` 是用户保留的本地资料，不要修改、不要纳入 git。

## 测试图片红线
- `test picture/` 与 `pixel/tests/fixtures/real/` 中的图片是基于其他画师作品的 AI 生成图像，**未获公开许可，绝不允许 commit 或 push**（已 gitignore，不要绕过）。

## Git 纪律
- 每个里程碑出口必须 git commit，完成报告用 diff 模式（不内联全量代码）。
- 多 agent 并行时各用独立 `git worktree` + 分支，完成后 merge 回 main。
- commit 前自查：`git diff --cached --name-only | grep -iE '\.png$|\.jpg$'` 应无输出（addons/gut 内置图标除外）。

## 工程约定
- UI 字符串集中在 `pixel/ui/shell/strings.gd`；禁止裸 print。
- UI 缩放统一由 `Window.content_scale_factor` 继承，禁止 `_scaled_int()` / 手动 `ui_scale` 注入 / 硬编码像素字号；画布美术按"反向补偿 + 设备像素整数对齐"自管（规范本体见 `ARCHITECTURE.md §5`，守护见 `pixel/scripts/check_ui_scaling.sh`）。
- 算法参考 perfectPixel（MIT，https://github.com/theamusing/perfectPixel）已在 README 标注；新增外部算法参考时同样需标注来源与协议。

## 工程设计规范索引（按需精读，不要凭记忆写代码）

规范本体在 `pixelforge-plan/`，本节只是路标。**首次接触本项目：先读 `pixelforge-plan/README.md`**——它定义了文档消费顺序、任务卡执行流程、以及"契约即法律"原则（发现契约缺陷不许静默绕过，须提修订建议待批准）。

按操作场景的必读对照：

| 你要做的事 | 动手前必读 |
|---|---|
| 任何写代码任务 | `01-architecture/ARCHITECTURE.md`（分层依赖规则、目录结构、编码规范、性能预算） |
| 涉及 UI/交互决策 | `00-vision/PRODUCT.md`（UX 原则：像素清晰度优先、不打断创作流、批量优先） |
| 改 .pxproj 读写 / 项目数据结构 / 画布元素布局 | `02-contracts/PROJECT-FORMAT.md`（含 §4 canvas.json `node` 引用；改格式须升版+迁移，预发布期见 §6 例外） |
| 改节点图模型/执行器 | `02-contracts/GRAPH-SCHEMA.md`（含批次内容节点 §5a、菜单/节点 both-and） |
| 改 AI provider / 任务队列 | `02-contracts/PROVIDER-API.md` |
| 改插件加载 / 新内置模块 | `02-contracts/PLUGIN-API.md`（内置 provider 也按插件形态实现） |
| 改风格预设 / 调色板 schema | `02-contracts/STYLE-PRESETS.md` |
| 开工某里程碑/任务卡 | `03-milestones/` 对应文件 + `05-quality/QUALITY.md` 的 DoD 核查表 |
| 改 core/pixel 算法 | `04-research/ALGORITHM_RESEARCH.md` + `06-algorithm-refs/perfectPixel/INTEGRATION.md`（哪些思路已吸收、哪些差异是有意为之） |
| 写/补测试 | `05-quality/QUALITY.md`（测试金字塔、覆盖矩阵口径）；M1 覆盖现状见 `05-quality/COVERAGE-MATRIX-M1.md` |
| 里程碑收尾 | 完成报告（diff 模式）→ `03-milestones/reports/`；跑对应 verify 脚本（含 git 干净度检查） |

硬性提醒：`02-contracts/` 是跨模块接口的唯一事实来源，禁止私自更改；技术选型疑问先查 `04-research/RESEARCH-NOTES.md` 再做决定，不要重新调研已有结论。
