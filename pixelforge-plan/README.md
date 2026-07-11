# PixelForge 项目执行文档包

> 本文档包面向负责开发的 AI 与工程师。当前产品路线已于 2026-07-12 重基线：旧 M0–M7 统一归入 Beta 0.1 工程历史，当前主线是 Beta 0.2 的产品可用性重构。

工作代号 PixelForge 仅为占位名；应用名称与版本由 `pixel/core/util/app_info.gd` 单点定义。

## 首次阅读顺序

1. `03-milestones/CURRENT-STATE.md`：当前真实状态、分支和下一步；
2. 当前执行书：现在是 `03-milestones/BETA-0.2-PLAN.md`；
3. `00-vision/PRODUCT.md` 与 `01-architecture/ARCHITECTURE.md`；
4. 当前卡涉及的 `02-contracts/` 和 `05-quality/QUALITY.md`；
5. 只有追溯既有实现时才进入旧 M 系列计划与 reports。

不要为了开工而通读所有历史报告。原始历史、源码和外部资料可交给边界明确的子 agent 收集，主 agent 负责产品判断和集成。

## 文档结构

```text
pixelforge-plan/
├── 00-vision/PRODUCT.md
├── 01-architecture/ARCHITECTURE.md
├── 02-contracts/                 # 跨模块接口唯一事实来源
├── 03-milestones/
│   ├── CURRENT-STATE.md
│   ├── BETA-0.1-BASELINE.md      # 旧 M0–M7 的工程历史归并
│   ├── BETA-0.2-PLAN.md          # 当前执行主线
│   ├── BETA-0.2-UI-DIAGNOSTICS.md # 独立高强度 UI/显示诊断卡
│   ├── BETA-0.3-CANDIDATES.md    # 待用户选择，不得提前执行
│   ├── M0...M8                   # 原计划，保留为历史证据
│   └── reports/                  # diff 模式报告、负证据与旧验收包
├── 04-research/
│   ├── LIBTV-INFINITE-CANVAS-EVIDENCE.md
│   └── ...
├── 05-quality/QUALITY.md
└── 06-algorithm-refs/
```

## 当前产品路线

```text
Beta 0.1 工程基线（旧 M0–M7；未人工通过、未发布）
    │
    └─> Beta 0.2 内容模块工作台
          ├─ 常规主线：工作区壳 → 内容模块 → 最小闭环 → 中英文
          ├─ 专项主线：macOS 字体/弹窗/跨屏缩放诊断
          └─ 合流：整体回归 → 候选 → 项目所有者统一人工验收
                    │
                    └─> Beta 0.3：只从候选池选择真实反馈驱动项

M8 仍为远期研究，不进入当前 Beta 主线。
```

## 执行方式

1. **任务卡是边界，不是停顿点**：一个 Goal 可按当前计划连续完成同一集成阶段内的多张卡。
2. **契约即法律**：发现契约缺口时提出最小修订；未获批准不得静默造第二套格式或语义。
3. **自动化持续运行**：卡内跑定向测试，整体切片合流时跑全量门禁；自动化红灯不得继续扩张。
4. **集中体验验证**：不为每个小模块反复 UI 冒烟或要求用户测试。完成计划定义的整体切片后做一次 agent 冒烟；项目所有者人工测试默认集中到 Beta 候选。
5. **状态分层**：工程通过、agent 冒烟、人工通过、发布通过分别记录，禁止互相代替。
6. **复杂 UI 故障先归因**：真实显示、字体与缩放问题进入隔离诊断分支，按复现—实验—最小修复收口。
7. **保持可回退**：按完整卡/切片本地提交；人工验收前不合并 `main`、不 push。

## 环境与工具链

- 引擎：Godot 4.6.x；锁定 4.6 大版本，升级另立任务。
- 语言：GDScript；只有真实性能证据才评估 GDExtension。
- 测试：GUT 9.x + 本地 verify 脚本；GitHub Actions 当前不是已启用门禁。
- 代码风格：gdformat/gdlint；文件行数约 1000 行为软目标。
- 用户文案：English/简体中文统一走 i18n 目录/访问层。
- Git：本地 `codex/` 分支；多 agent 改代码使用独立 worktree。
