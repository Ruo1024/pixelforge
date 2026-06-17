# PixelForge Godot Project

本仓库当前采用“本地 agent 验证”作为出口门控，不启用 GitHub Actions。M1 统一入口是 `./scripts/verify_m1.sh`，它会依次执行 lint、GUT 测试、M1 性能采样和 headless/export-template 检查。M0 口径仍保留在 `./scripts/verify_m0.sh`。

PixelForge 是一个 Godot 4.6 工具型应用工程。当前阶段实现到 M1：在 M0 工程骨架、无限画布、基础服务、项目保存/打开、撤销与任务队列之上，新增纯本地像素清洗管线。清洗管线已按显式步骤链组织，可按步骤启停，并支持内置调色板、自定义调色板与后续算法扩展。检查器支持 300ms 防抖预览、手动网格 overlay、批量取消和清洗 provenance 写入。

## 目录摘要

- `core/`：纯逻辑领域层，只放不依赖场景树的像素算法、数据模型和工具。
- `services/`：应用服务层，管理项目、素材、撤销、任务队列、设置和事件总线。
- `infra/`：基础设施层，封装日志、文件 IO、HTTP/WebSocket 等外部能力。
- `ui/`：界面层，包含主窗口、无限画布和后续面板。
- `tests/`：GUT 自动化测试，按 unit / integration / smoke 分层。
- `docs/`：手动测试脚本、交付说明和维护文档。
- `addons/gut/`：GUT 测试框架。

## 常用命令

```bash
./scripts/verify_m1.sh
./scripts/verify_m0.sh
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
godot --headless --script res://scripts/measure_m1.gd
```

如果系统 PATH 没有 `godot`，脚本会自动尝试 `/Applications/Godot.app/Contents/MacOS/Godot`。

`./scripts/lint.sh` 需要 `gdformat` 和 `gdlint`。本地缺少 gdtoolkit 时会失败退出，安装命令：

```bash
python -m pip install gdtoolkit
```

如果项目内存在 `.godot/gdtoolkit-venv/bin`，`lint.sh` 会自动优先使用该本地环境。

Windows fresh clone 第一次运行测试时不需要手动 import；`run_tests.sh` 会先执行 `godot --headless --import --quit`，并把 `HOME`、`APPDATA`、`LOCALAPPDATA` 隔离到项目内 `.godot/home`。

导出预设使用 `export_presets.cfg.example` 作为模板。需要本地导出时复制为 `export_presets.cfg`，该本地文件已加入 `.gitignore`。

## 算法参考

`core/pixel/` 中网格检测与重采样的部分思路参考了 [perfectPixel](https://github.com/theamusing/perfectPixel)（MIT License，作者 theamusing）。详见 `../pixelforge-plan/06-algorithm-refs/perfectPixel/`。
