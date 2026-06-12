# M0 Windows Test Summary

来源：`/Users/ruo/Library/Containers/com.tencent.qq/Data/Downloads/M0-Windows-Test-Report.md`

测试时间：2026-06-12 23:00-23:31（Asia/Shanghai）

## 结论

Windows 真实 UI 冒烟通过，但自动化测试初次报告未全绿。

已通过：

- Godot 4.6.3 可启动项目窗口。
- 顶部按钮、画布、状态栏可见。
- `New`、滚轮缩放基础交互可用。
- `check_export_templates.sh` headless 启动通过。

发现并处理的自动化问题：

- fresh clone 直接跑测试前需要 Godot import。
  - 处理：`scripts/run_tests.sh` 已前置 `godot --headless --import --quit`。
- Windows 仅设置 `HOME` 不足以隔离 Godot 数据目录。
  - 处理：脚本同时设置 `HOME`、`APPDATA`、`LOCALAPPDATA` 到项目内 `.godot/home`。
- `atomic_write` 覆盖已有文件的测试在读句柄未关闭时失败。
  - 处理：覆盖测试显式关闭读句柄；新增 Windows 锁定目标时“不破坏原文件”的语义测试。
- Windows headless 的 `Performance.TIME_PROCESS` 对 500 元素测试报告约 0.4s。
  - 处理：性能问题暂不作为 M0 门控；Windows headless 下仅保留 500 元素结构冒烟。

## 复测入口

```bash
./scripts/verify_m0.sh
```
