# PixelForge Godot Project

本仓库暂不启用 GitHub Actions；lint、GUT 测试和导出模板检查通过本地脚本手动运行。

PixelForge 是一个 Godot 4.6 工具型应用工程。本阶段实现 M0：工程骨架、无限画布底座、基础服务、项目保存/打开、撤销与任务队列。

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
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_export_templates.sh
```

如果系统 PATH 没有 `godot`，脚本会自动尝试 `/Applications/Godot.app/Contents/MacOS/Godot`。

`./scripts/lint.sh` 需要 `gdformat` 和 `gdlint`。本地缺少 gdtoolkit 时会失败退出，安装命令：

```bash
python -m pip install gdtoolkit
```

如果项目内存在 `.godot/gdtoolkit-venv/bin`，`lint.sh` 会自动优先使用该本地环境。

导出预设使用 `export_presets.cfg.example` 作为模板。需要本地导出时复制为 `export_presets.cfg`，该本地文件已加入 `.gitignore`。
