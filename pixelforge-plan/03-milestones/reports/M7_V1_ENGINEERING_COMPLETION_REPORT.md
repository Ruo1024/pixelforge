# M7 / v1.0 RC 工程完成报告（diff 模式）

> 分支：`codex/pixelforge-full-plan-goal`。按项目所有者指令，M4–M7 连续开发、自动化统一收口，不执行逐模块人工冒烟或审核。本报告只声明工程通过。

## 用户闭环

- File > Plugin Manager 可安装目录缓存/PCK 插件、查看版本/权限/失败原因、启停、卸载和打开插件目录；插件 API 对节点、Provider、菜单、管线、色板、预设与导出器逐项记账，卸载逆序撤销。
- 图中的插件节点卸载后以幽灵节点保留原 JSON，重装后恢复；错误清单、版本不兼容、生命周期错误和语法错误被隔离，不阻止主程序启动。
- ComfyUI Provider 支持连通检测、API workflow 导入/槽位绑定、内置 txt2img/img2img 模板、图片上传、`/prompt`、WebSocket 进度、`/history` 轮询回退、`/view` 拉图与 `/interrupt` 取消。
- `comfyui.run_workflow` 作为一等图节点与云 Provider 节点共存；结果标记 `raw_pixel=false`，继续进入正式像素清洗链。
- 首次启动引导提供风格预设、可选 Provider 设置与示例 mock 项目；用户手册、插件开发指南、FAQ、许可/模型清单和最终统一验收页齐备。

## 关键 diff

- 新增 `plugin_service.gd`、完整 `plugin_api.gd` 记账和静态插件节点注册表；目录插件先打入用户缓存命名空间 PCK，避免导出后只读资源环境无法加载多文件 GDScript。
- 新增 `plugins/bridge_comfyui/` Provider、workflow 模板解析器、图节点、两套内置模板和 mock HTTP fixture。
- 新增 Plugin Manager、ComfyUI 模板绑定对话框、v1 onboarding；为保持职责内聚与 lint 行数预算，M6 编辑器流程抽为 `pixel_editor_flow_controller.gd`。
- 版本统一为 `1.0.0-rc.1`；导出排除 tests 与 GUT，增加三平台构建、PCK 路径审计、凭据扫描和 `verify_m7.sh`。

## 自动化与候选证据

- `./pixel/scripts/verify_m7.sh`：180 GDScript files lint 通过；254/254 tests、3589 assertions 通过；UI scaling、M3.1→M6 累积门控、安全扫描、插件打包均通过。
- 性能样本：50 张批量清洗总计 706ms、主线程峰值 14.46ms；512 kmeans k=32 为 478.74ms；magic wand 256×256 为 26.46ms。其余画布、Board 10k tiles、120Hz 绘制和 32×64 编辑器哨兵由累积门控覆盖。
- `build_v1_candidates.sh --all` 使用 Godot 4.6.3 官方模板构建三平台资源，全部通过受保护图片路径审计；macOS 另通过干净用户目录 headless 启动。

| 候选 | bytes | SHA-256 |
|---|---:|---|
| Linux executable | 71,075,864 | `2c78919325d7f29fa7607287c7c1eeac367ea4c94e7b8b6f5f4c6b20492f73d0` |
| Linux PCK | 715,920 | `17e80fdac0063ebbbcc3ca324351bb48681281f5649d4f06b499e0eb6204d59e` |
| Windows executable | 104,559,616 | `9635acd1df035f69a2102b500be25a7981cea70d5533d5e5e89c96cd149f67d5` |
| Windows PCK | 715,920 | `17e80fdac0063ebbbcc3ca324351bb48681281f5649d4f06b499e0eb6204d59e` |
| macOS ZIP | 63,462,662 | `d32670d4fd56182172adb7caca0a73ecafd41863c094b180360136a1d98465ec` |

## DoD 核查

| 项 | 状态 | 证据/路径 |
|---|---|---|
| 代码规范 | 通过 | `pixel/scripts/lint.sh` |
| 自动测试 | 通过 | 254/254、3589 assertions |
| 手动测试 | 延期登记 | 项目所有者要求最终统一验收 |
| 契约同步 | 通过 | 现有 PLUGIN/PROVIDER/GRAPH 合同内落地，无格式升版 |
| TODO | 通过 | M7 门禁扫描无无主标记 |
| 性能预算 | 通过 | 累积性能哨兵与本报告实测 |
| 跨平台 | 通过 | 三平台候选构建与 PCK 审计；Windows/Linux 真实窗口体验留统一验收 |
| 出口门控 | 通过 | `verify_m7.sh` |

工程结论：**M0–M7 工程通过，形成 v1.0 RC 工程候选；人工通过/发布通过均未声明。**

## 已知限制与统一验收项

- OpenAI、RetroDiffusion 与真实 ComfyUI 服务仍需可用凭据/模型执行一次真实链路；mock 合同不能替代外部服务验收。
- 强杀 10 次、三平台真实窗口安装/首次启动、真实素材视觉质量、三名陌生用户和插件警告法务签字属于统一人工/发布出口，不倒填通过。
- 内置 ComfyUI 模板不分发 checkpoint/LoRA；用户必须按本地文件名调整模板并自行确认模型许可。
- 保留既有 1 个 GUT `error_tracker.gd` orphan 与退出资源警告；损坏插件用例会有预期的 Godot parse error 日志，但已验证失败隔离。
- 所有候选位于 gitignore 的 `pixel/build/`；未提交测试图片，未 merge `main`，未 push。

## 提交

- 对应本地提交：`M7 complete plugin and ComfyUI v1 engineering candidate`（哈希以分支日志为准）。
