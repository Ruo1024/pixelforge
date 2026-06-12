# M0 Brief Index

本文是 M0 的精简索引。完整交付细节、最终代码附录和审批记录仍以 `M0_COMPLETION_REPORT.md` 为准。

## 当前出口策略

- M0 不使用 GitHub Actions 作为门控。
- 本地 agent 统一运行 `./scripts/verify_m0.sh`。
- `verify_m0.sh` 顺序执行：`lint.sh`、`run_tests.sh`、`check_export_templates.sh`。
- Windows fresh clone 由 `run_tests.sh` 自动执行 Godot import，并隔离 `HOME/APPDATA/LOCALAPPDATA` 到 `.godot/home`。

## 当前状态

- 本地 macOS：lint、GUT、headless/export-template check 通过。
- Windows：真实 UI 冒烟通过；自动化失败已定位为 `atomic_write` 测试句柄语义和 Windows headless 性能采样。当前修复策略：
  - `atomic_write` 覆盖测试显式关闭读句柄。
  - Windows 锁文件语义单独测试：目标被读句柄占用时应返回错误且保留原文件。
  - Windows headless 500 元素性能采样暂不作为 M0 门控，性能优化留到后续债务。

## 开发者快速索引

- 架构边界：`core/` 纯逻辑，`services/` 应用服务，`infra/` 外部能力，`ui/` 场景与交互。
- 项目格式：`pixelforge-plan/02-contracts/PROJECT-FORMAT.md`，当前 `format_version = 1`。
- M1 接手说明：`docs/m1-handoff-notes.md`。
- 手动测试脚本：`docs/manual-test-m0.md`。
- Windows 测试摘要：`docs/m0-windows-test-summary.md`。

## M0 剩余登记项

- Windows 自动化需在本轮修复后由朋友重新跑 `./scripts/verify_m0.sh`。
- 性能数字暂不补录；Windows headless 性能问题不作为当前门控。
- `tests/fixtures/generators/` 在 M1 清洗算法开始时补齐。
- 覆盖率报告在 M1 建立，优先覆盖 `core/pixel` 算法。
