# PixelForge

PixelForge 是一个基于 Godot 4.6 的 AI 像素美术工具项目。当前仓库包含两部分：

- `pixel/`：可运行的 Godot 工程，目前完成 M0 工程骨架、无限画布底座、基础服务、项目保存/打开、撤销与任务队列。
- `pixelforge-plan/`：面向后续 agent 协作的阶段计划、架构、接口契约、质量策略和里程碑拆分。

本仓库不包含本地垃圾桶、Godot 学习网页和临时压缩包。

## 快速开始

```bash
cd pixel
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

如果系统 PATH 没有 `godot`，脚本会自动尝试 `/Applications/Godot.app/Contents/MacOS/Godot`。

`./scripts/lint.sh` 需要 `gdformat` 和 `gdlint`：

```bash
python -m pip install gdtoolkit
```

## 用 Agent 测试每个阶段

把下面这段作为通用开场发给任意 coding agent，然后按阶段替换里程碑文件即可：

```text
你正在维护 PixelForge。先阅读 README.md、pixel/README.md、pixelforge-plan/README.md、pixelforge-plan/01-architecture/ARCHITECTURE.md、pixelforge-plan/05-quality/QUALITY.md。

当前目标：执行 pixelforge-plan/03-milestones/M0-foundation.md 中的验收检查，或继续推进指定里程碑。

约束：
- Godot 工程在 pixel/。
- 优先保持现有目录结构和 GDScript 风格。
- 不提交 .godot/、export_presets.cfg、本地构建产物、垃圾桶或学习指导网页。
- 修改后至少运行 ./scripts/lint.sh 和 ./scripts/run_tests.sh；如果涉及导出，运行 ./scripts/check_export_templates.sh。
- 完成后更新相关阶段文档、pixel/CHANGELOG.md 或交付说明。
```

常用阶段入口：

- M0 基础骨架：`pixelforge-plan/03-milestones/M0-foundation.md`
- M1 AI 图清洗管线：`pixelforge-plan/03-milestones/M1-cleanup-pipeline.md`
- M2 抠图与切分：`pixelforge-plan/03-milestones/M2-matting-slicing.md`
- M3 节点图：`pixelforge-plan/03-milestones/M3-node-graph.md`
- M4 AI Provider：`pixelforge-plan/03-milestones/M4-ai-providers.md`
- M5 地图编辑器：`pixelforge-plan/03-milestones/M5-map-composer.md`
- M6 像素编辑器：`pixelforge-plan/03-milestones/M6-pixel-editor.md`
- M7 插件与 ComfyUI：`pixelforge-plan/03-milestones/M7-plugins-comfyui.md`
- M8 体素远期研究：`pixelforge-plan/03-milestones/M8-voxel-future.md`

## 手动检查

暂不启用 GitHub Actions。需要验证时在本地或 agent 环境中手动运行：

```bash
cd pixel
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

## 致谢与算法参考

- 像素网格检测/重采样部分参考了 [perfectPixel](https://github.com/theamusing/perfectPixel)（MIT License）的算法思路，提炼与整合分析见 `pixelforge-plan/06-algorithm-refs/perfectPixel/`。
