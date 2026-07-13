# PixelForge 项目执行文档包

> 本文档包面向负责开发的 AI 与工程师。当前产品路线已于 2026-07-14 更新：旧 M0–M7 归入 Beta 0.1 工程历史，Beta 0.2 已工程收口，Beta 0.3–0.5 已形成未人工签收的工程候选；当前主线是 Beta 0.6 卡片产品化与画布可读性。

工作代号 PixelForge 仅为占位名；应用名称与版本由 `pixel/core/util/app_info.gd` 单点定义。

## 首次阅读顺序

1. `03-milestones/CURRENT-STATE.md`：当前真实状态、分支和下一步；
2. `03-milestones/BETA-0.6-PLAN.md` 与 `BETA-0.6-CARD-DESIGN-SPEC.md`；
3. `00-vision/PRODUCT.md` 与 `01-architecture/ARCHITECTURE.md`；
4. 当前卡涉及的 `02-contracts/` 和 `05-quality/QUALITY.md`；
5. 只有追溯既有实现时才进入 Beta 0.3–0.5、旧 M 系列计划与 reports。

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
│   ├── BETA-0.2-PLAN.md          # 已工程收口的历史执行书
│   ├── BETA-0.2-UI-DIAGNOSTICS.md # 已工程收口的显示诊断卡
│   ├── BETA-0.3-0.5-ROADMAP.md   # 已工程完成、人工待验的原型路线
│   ├── BETA-0.3-0.5-PARITY-MATRIX.md # 固定 90% 分母、主卡与场景
│   ├── BETA-0.3-PLAN.md          # 内容工作区
│   ├── BETA-0.4-PLAN.md          # 云端生成与结果回流
│   ├── BETA-0.5-PLAN.md          # 工作流复用与 90% 收口
│   ├── BETA-0.6-PLAN.md          # 当前卡片产品化执行书
│   ├── BETA-0.6-CARD-DESIGN-SPEC.md # 当前唯一视觉与交互规格
│   ├── BETA-0.3-CANDIDATES.md    # 已完成取舍的历史候选池
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
Beta 0.1 工程历史
    └─> Beta 0.2 工程候选（人工待验）
          └─> Beta 0.3 内容工作区
                └─> Beta 0.4 云端生成与结果回流
                      └─> Beta 0.5 工作流复用与 90% 收口
                            └─> Beta 0.6 卡片产品化与画布可读性
                                  └─> 唯一候选 → 项目所有者统一人工验收
```

账号、权限、协作和版本历史永久排除；本地模型/ComfyUI 无限期延后。M8 仍为远期研究，不进入当前 Beta 主线。

## 执行方式

1. **任务卡是边界，不是停顿点**：当前一个 Goal 连续完成 Beta 0.6 的 B6-0 至 B6-8，不在单卡或集成切片停下请求用户。
2. **契约即法律**：发现契约缺口时提出最小修订；未获批准不得静默造第二套格式或语义。
3. **自动化持续运行**：卡内跑定向测试，整体切片合流时跑全量门禁；自动化红灯不得继续扩张。
4. **自动化开发、最终人工**：Beta 0.6 开发期间完全不使用 Computer Use，只运行自动化和脚本截图；全部工程完成后由项目所有者统一人工验收。
5. **状态分层**：工程通过、人工通过、发布通过分别记录，自动化截图不能代替人工。
6. **复杂 UI 故障先归因**：显示、字体与缩放问题进入隔离诊断分支，按自动化采证—实验—最小修复收口。
7. **保持可回退**：按完整卡/切片本地提交；人工验收前不合并 `main`、不 push。

## 环境与工具链

- 引擎：Godot 4.6.x；锁定 4.6 大版本，升级另立任务。
- 语言：GDScript；只有真实性能证据才评估 GDExtension。
- 测试：GUT 9.x + 本地 verify 脚本；GitHub Actions 当前不是已启用门禁。
- 代码风格：gdformat/gdlint；文件行数约 1000 行为软目标。
- 用户文案：English/简体中文统一走 i18n 目录/访问层。
- Git：本地 `codex/` 分支；多 agent 改代码使用独立 worktree。
