# PixelForge Godot Project

当前候选版本为 **0.1.0-alpha.1**，定位是 macOS 受邀 alpha 候选，不是公开发布版，也不代表 Windows/Linux 已验收。仓库采用本地 agent 验证作为出口门控，不启用 GitHub Actions；M3.1 统一入口是 `./scripts/verify_m3_1.sh`。

PixelForge 是一个 Godot 4.6 本地像素素材工作台。当前候选已覆盖导入、清洗/抠图/切分/描边、批次筛选、项目保存重开、PNG/spritesheet 导出，以及最小 mock 节点图；M3 UX-4 overview 仍是明确设计债。受邀测试者请使用 `docs/manual-test-m3_1-alpha.md`，所有人工项在签收前仍视为未通过。

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
./scripts/verify_m3_1.sh
./scripts/build_macos_alpha.sh
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

导出预设使用 `export_presets.cfg.example` 作为模板。`build_macos_alpha.sh` 会复制本地预设、生成忽略的 `build/PixelForge-0.1.0-alpha.1-macOS.zip`，并检查可执行文件及受保护图片路径；Godot 4.6.3 export templates 必须预先安装。

## 算法参考

`core/pixel/` 中网格检测与重采样的部分思路参考了 [perfectPixel](https://github.com/theamusing/perfectPixel)（MIT License，作者 theamusing）。详见 `../pixelforge-plan/06-algorithm-refs/perfectPixel/`。
