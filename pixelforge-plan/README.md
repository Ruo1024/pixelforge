# PixelForge 项目执行文档包（喂给执行 AI 的说明书）

> 本文档包是「PixelForge —— AI 像素美术瑞士军刀」的完整执行计划。
> 它的目标读者是**负责写代码的 AI（或人类工程师）**。请严格按照本 README 的流程消费文档。

工作代号 PixelForge 仅为占位名，正式名称在 `core/util/app_info.gd` 中单点定义，随时可改。

## 文档包结构

```
pixelforge-plan/
├── README.md                      ← 你正在读的文件
├── 00-vision/
│   └── PRODUCT.md                 ← 产品愿景、用户画像、UX 原则（做任何 UI 决策前必读）
├── 01-architecture/
│   └── ARCHITECTURE.md            ← 总体架构、目录结构、依赖规则、编码规范（每个任务开始前必读）
├── 02-contracts/                  ← 数据契约（跨模块接口的唯一事实来源，禁止私自更改）
│   ├── PROJECT-FORMAT.md          ← .pxproj 项目文件格式
│   ├── GRAPH-SCHEMA.md            ← 节点图 JSON Schema 与执行语义
│   ├── PROVIDER-API.md            ← AI Provider 抽象接口与任务队列
│   ├── PLUGIN-API.md              ← 插件清单格式与加载机制
│   └── STYLE-PRESETS.md           ← 风格预设 Schema 与内置预设数据
├── 03-milestones/                 ← 按里程碑拆分的任务卡（执行主线）
│   ├── M0-foundation.md           ← 工程骨架 + 无限画布底座
│   ├── M1-cleanup-pipeline.md     ← 功能1：像素清洗管线
│   ├── M1.1-cleanup-enhancements.md ← 功能1增强：量化质量/调色板产品化/质量加固
│   ├── M2-matting-slicing.md      ← 功能2：抠图与切分
│   ├── M3-node-graph.md           ← 功能3a：节点工作流（纯本地）
│   ├── M4-ai-providers.md         ← 功能3b：云端 AI 生成接入
│   ├── M5-map-composer.md         ← 功能4：地图拼接与多层动效合成
│   ├── M6-pixel-editor.md         ← 功能5a：像素编辑器（Aseprite-lite）
│   ├── M7-plugins-comfyui.md      ← 功能3c：插件系统 + ComfyUI 桥
│   └── M8-voxel-future.md         ← 功能5b：体素方向（研究简报，暂不执行）
├── 04-research/
│   └── RESEARCH-NOTES.md          ← 2026-06 调研结论（技术选型依据、外部 API 现状）
└── 05-quality/
    └── QUALITY.md                 ← 测试策略、完成定义（DoD）、风险登记册
```

## 执行 AI 的工作流程（必须遵守）

1. **读取顺序**：首次接触本项目时，按 `ARCHITECTURE.md → 相关 contract → 当前里程碑文件` 顺序阅读。不需要读完全部文档才动手，但**当前任务卡引用到的契约文件必须读**。
2. **任务卡是最小执行单元**。每张卡的结构：`目标 / 前置依赖 / 技术实现指导 / 涉及文件 / 验收标准`。一次会话只做一张卡（或卡内明确允许合并的子项）。
3. **验收标准是硬性的**。完成卡片必须满足全部验收标准，包括测试通过。不允许"先跳过测试"。
4. **禁止跨界修改**：任务卡未提及的模块若必须改动，先在交付说明中报告原因，并保持改动最小。
5. **契约即法律**：`02-contracts/` 中的 schema 和接口签名是跨模块协作的唯一标准。如果实现中发现契约有缺陷，**不要静默绕过**——在交付说明中提出修订建议，由项目所有者批准后更新契约文件，再改代码。
6. **每张卡完成后**：运行 `tests/` 下全部测试 + 该卡新增测试；更新对应模块的 `docs/` 注释；在 `CHANGELOG.md` 追加一行。
7. **不确定时的默认值**：遵循 `PRODUCT.md` 的 UX 原则（像素清晰度优先、不打断创作流、批量优先）做判断，并在交付说明中记录所做假设。

## 里程碑依赖关系

```
M0 ──► M1 ──► M2 ──► M3 ──► M4 ──► M7
        │      │      │      │
        └──────┴──────┴──► M5 ──► M6        M8（独立研究，M7 后再评估）
```

- M1/M2 完成后即产出第一个对外可用的 alpha（纯本地清洗工具，无 AI 依赖）。
- M4 完成 = 第一个完整价值闭环（生成→清洗→切分→入库）。
- M6 完成 = 计划中的 MVP（v0.5）。
- M7 完成 = v1.0（可扩展生态起点）。

## 环境与工具链（全局约定）

- **引擎**：Godot 4.6.x（2026-06 当前稳定版 4.6.3）。锁定 4.6 大版本，不追 4.7 beta。
- **语言**：GDScript 为主。性能热点预留 GDExtension（Rust）替换路径，但 M0–M7 全部用 GDScript 完成（理由见 ARCHITECTURE.md §7）。
- **测试**：GUT 9.x（addons/gut），CI 用 headless Godot 跑 `gut_cmdln`。
- **代码风格**：gdtoolkit（gdformat + gdlint）默认规则。
- **版本控制**：git，main 分支始终可运行；每张任务卡一个 feature 分支 + 一次合并。
- **CI**：GitHub Actions：lint → test → 三平台导出（Windows/macOS/Linux）。
