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
- 新 UI 组件必须接 ui_scale（`_scaled_int()`），禁止硬编码像素值。
- 算法参考 perfectPixel（MIT，https://github.com/theamusing/perfectPixel）已在 README 标注；新增外部算法参考时同样需标注来源与协议。
