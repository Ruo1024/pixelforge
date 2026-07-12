# PixelForge

PixelForge 是一个基于 Godot 4.6 的 AI 像素美术工具项目。当前仓库包含两部分：

- `pixel/`：可运行的 Godot 工程；Beta 0.2 已达到工程候选，具备无限画布、内容卡、项目保存、撤销、任务队列、双语和批次加工底座。
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

## 当前 Agent 开发入口

当前路线不是旧 M0–M8 的逐阶段测试。执行 agent 应先读总路线，再由一个 Goal 连续完成 Beta 0.3–0.5：

```text
你正在维护 PixelForge。先阅读 AGENTS.md、pixelforge-plan/README.md、pixelforge-plan/03-milestones/CURRENT-STATE.md、pixelforge-plan/03-milestones/BETA-0.3-0.5-ROADMAP.md，以及正在执行的 Beta 计划。

当前目标：按总路线连续完成 Beta 0.3、0.4、0.5，不在单卡或版本出口停下请求用户。

约束：
- 开发期间完全不使用 Computer Use，只运行自动化测试和脚本截图。
- Beta 0.3/0.4 不构建候选、不写正式阶段报告；Beta 0.5 后一次性收口。
- 三版完成后由项目所有者统一人工验收；此前不合并 main、不 push。
- 账号、权限、协作、版本历史永久排除；本地模型/ComfyUI 无限期延后。
```

当前入口：

- 总路线：`pixelforge-plan/03-milestones/BETA-0.3-0.5-ROADMAP.md`
- 90% 受控矩阵：`pixelforge-plan/03-milestones/BETA-0.3-0.5-PARITY-MATRIX.md`
- Beta 0.3：`pixelforge-plan/03-milestones/BETA-0.3-PLAN.md`
- Beta 0.4：`pixelforge-plan/03-milestones/BETA-0.4-PLAN.md`
- Beta 0.5：`pixelforge-plan/03-milestones/BETA-0.5-PLAN.md`

旧 M0–M8 文档只保留为历史工程证据，不再作为当前开工入口。

## 自动化检查与最终人工

暂不启用 GitHub Actions。开发期间由脚本运行：

```bash
cd pixel
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

Beta 0.3–0.5 全部工程完成后，再由项目所有者使用唯一候选统一人工验收真实云端、完整工作流、中文和多显示器。

## 致谢与算法参考

- 像素网格检测/重采样部分参考了 [perfectPixel](https://github.com/theamusing/perfectPixel)（MIT License）的算法思路，提炼与整合分析见 `pixelforge-plan/06-algorithm-refs/perfectPixel/`。
