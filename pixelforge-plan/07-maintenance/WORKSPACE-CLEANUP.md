# 工作区规整执行清单

> 生成日期：2026-06-13。生成时另一 agent 仍在开发中——**本清单仅在确认无其他 agent 运行、且其成果已落盘后执行**。
> 所有命令在仓库根目录（即包含 pixel/ 与 pixelforge-plan/ 的顶层文件夹）下执行。
> 原则：先 commit 快照，再做任何移动/删除——有了提交，每一步都可逆。

## 0. 勘察结论速览（2026-06-13 快照）

- git 仓库根 = 顶层文件夹（不是 pixel/），最后提交停在 `3860717 M0 finish`。
- 悬空变更：17 个已修改文件 + 60+ 个未跟踪文件（M1/M1.1 全部成果，含 mac 显示修复）。
- 顶层 `.gitignore` 已排除：`.DS_Store`、`zitXfz3h`、`垃圾桶/`、`godot-interactive-guide/`——这些只污染目录视觉，不污染 git。
- `zitXfz3h`（无扩展名 zip）内容是 godot-learning 的**旧快照**（文件停在 6/11 11:35）；`垃圾桶/godot-learning/` 是**更新的版本**（6/11 12:50）。删 zip 不丢内容。
- `垃圾桶/godot-learning-backup/godot-learning-backup.zip` 是损坏的 zip（central directory 缺失），同目录已有解包后的同名文件，zip 可删。
- `test picture/` 未被 gitignore，6MB PNG 会被 `git add -A` 吞进仓库——第 1 步前必须先决定去留。

## 1. 先提交快照（最高优先级）

执行前检查：确认没有 agent 在运行（问用户），然后看一眼 `git status` 与本清单快照的差异，新增文件归入对应 commit。

```bash
# 1a. 防止测试图片混入（若决定不入库）
echo 'test picture/' >> .gitignore

# 1b. 按逻辑分批提交（建议拆法，可按需调整）：
# 批次一：M1 核心管线 + 测试
git add pixel/core/pixel/ pixel/assets/ pixel/tests/ pixel/scripts/ \
        pixel/ui/canvas/cleanup_grid_overlay.gd* pixel/ui/inspector/
git commit -m "M1: pixel cleanup pipeline, palettes, tests, verify scripts"

# 批次二：M1.1 改进轮 + mac 显示修复（含被修改的既有文件）
git add pixel/ui/ pixel/services/ pixel/project.godot pixel/docs/ \
        pixel/CHANGELOG.md pixel/README.md
git commit -m "M1.1: improvement round + mac display scale fix"

# 批次三：报告与计划文档
git add pixel/*.md pixelforge-plan/ .gitignore
git commit -m "docs: M1/M1.1 reports, plan updates, coverage matrix"

# 1c. 收尾确认无遗漏
git status --short   # 应只剩被 ignore 的项
```

若不想现场拆批，可先 `git add -A && git commit -m "WIP: M1.1 + mac fix snapshot"` 一把梭，之后用 `git rebase -i` 再拆——比悬空强。

## 2. 逐文件处置表（在第 1 步 commit 之后执行）

| 路径 | 处置 | 理由/命令 |
|---|---|---|
| `zitXfz3h` | 删除 | godot-learning 旧快照，垃圾桶里有更新版。`rm zitXfz3h` |
| `垃圾桶/godot-learning-backup/` | 删除整个子目录 | 与 `垃圾桶/godot-learning/` 重复且 zip 损坏。`rm -rf 垃圾桶/godot-learning-backup` |
| `垃圾桶/`（其余） | 移出仓库或保留待定 | 学习材料，与项目无关。建议移到仓库外，如 `~/Documents/godot-learning/` |
| `godot-interactive-guide/` | 同上 | 学习材料。可与垃圾桶内容合并到同一处 |
| `pixel/M0_COMPLETION_REPORT.md` 等 5 份报告 | `git mv` 到 `pixelforge-plan/03-milestones/reports/` | 报告属文档区不属代码区。**用 git mv 保留历史** |
| `pixel/ALGORITHM_RESEARCH.md` | `git mv` 到 `pixelforge-plan/04-research/` | 同上 |
| `test picture/` | 重命名 `test-assets/`（去空格）或移出 | 路径含空格易坑脚本。若测试夹具已复制进 `pixel/tests/fixtures/real/` 则可整体移出仓库 |
| 各处 `.DS_Store` | `find . -name .DS_Store -not -path './.git/*' -delete` | 已被 ignore，删了清爽 |

报告搬移示例：

```bash
mkdir -p pixelforge-plan/03-milestones/reports
git mv pixel/M0_COMPLETION_REPORT.md pixel/M1_COMPLETION_REPORT.md \
       pixel/M1_1_COMPLETION_REPORT.md pixel/M1_1_IMPROVEMENT_REPORT.md \
       pixel/MAC_DISPLAY_FIX_COMPLETION_REPORT.md \
       pixelforge-plan/03-milestones/reports/
git mv pixel/ALGORITHM_RESEARCH.md pixelforge-plan/04-research/
git commit -m "chore: relocate reports to plan docs area"
```

注意：报告内若有相对链接（指向 pixel/ 内文件），搬移后抽查修正。

## 3. 防复发规矩（清理完成后立刻立）

### 3a. 仓库根放一份 CLAUDE.md（agent 落点约定）

```markdown
# PixelForge 工作区约定（所有 agent 必读）
- 代码只写入 pixel/，计划与报告只写入 pixelforge-plan/。
- 里程碑/修复完成报告 → pixelforge-plan/03-milestones/reports/。
- 临时文件/草稿 → scratch/（已 gitignore），禁止在仓库根新建文件。
- 每个里程碑出口必须 git commit；完成报告用 diff 模式。
- 新 UI 组件必须接 ui_scale，禁止硬编码像素值。
```

并执行 `mkdir -p scratch && echo 'scratch/' >> .gitignore`。

### 3b. 出口脚本加"git 干净度"检查

在 `verify_m1_1.sh`（及后续 verify_m2.sh）末尾追加：

```bash
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 工作区有未提交变更——里程碑出口要求 commit 后再签字"
  exit 1
fi
```

### 3c. 多 agent 并行用 worktree 隔离

```bash
git worktree add ../pixelforge-m2 -b m2-matting   # agent A
git worktree add ../pixelforge-fix -b hotfix-xxx  # agent B
# 各自完成后 merge 回主分支，worktree 用完即删：
git worktree remove ../pixelforge-m2
```

每个对话窗口的 agent 指定到各自 worktree 目录工作，从根上避免互相踩踏。

### 3d. 目标终态

```
pixelforge/
├── CLAUDE.md
├── README.md
├── PixelForge项目计划书.md
├── pixel/              # 仅代码与引擎资源
├── pixelforge-plan/    # 计划、契约、质量、报告
├── test-assets/        # （若保留）测试图片
└── scratch/            # gitignored 临时区
```

## 4. 验证

- [ ] `git log --oneline` 可见快照提交，`git status` 干净（仅 ignore 项）
- [ ] `pixel/` 根目录无 *.md 报告（README/CHANGELOG 除外）
- [ ] `zitXfz3h`、损坏 zip、`.DS_Store` 已消失
- [ ] CLAUDE.md 存在且新 agent 对话可复述其约定
- [ ] verify 脚本含干净度检查并能正常报红/报绿
