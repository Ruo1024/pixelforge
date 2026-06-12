# Changelog

## Unreleased

- M0: 建立 Godot 4.6 工程骨架、基础设施服务、无限画布、项目保存/打开、撤销/任务队列和测试流水线。
- M0 修订: 禁用 viewport stretch 压缩，增加自动 UI scale，修复 Retina/高分屏下窗口与字体显示过小的问题。
- M0 复审加固: 严格执行 gdtoolkit lint、模板化 export presets、补充任务取消/AssetLibrary 缓存计费测试，并拆出画布选择状态模块。
- M0 二审加固: 补齐 TaskQueue running cancel 生命周期、未来项目格式拒开、Logger 日志清理、真实 LRU 验证、视口外 process 剔除、HTTP/WebSocket stub 签名和 M1 交接说明。
- M0 验收口径: 采用本地 agent `verify_m0.sh` 作为出口门控，补 Windows fresh clone import、APPDATA/LOCALAPPDATA 隔离、atomic_write Windows 语义测试和 M0 精简索引。
- M1: 新增像素清洗 core 管线、9 个内置调色板、6 个风格预设、fixtures 生成器、清洗检查器 UI、批量 Apply、单图 PNG 导出和 `verify_m1.sh` 门控。
- M1 算法层重构: 引入颜色空间工具、调色板解析器和显式步骤链，支持自定义调色板、按步骤启停、edge-aware 重采样与 chromatic 抖动。
- M1 验收补丁: 补实时预览防抖、手动网格 overlay、批量取消、清洗 provenance、真实 AI fixtures、24 样本网格矩阵、P95 性能采样和 orphan 固定断言。
- M1.1: 新增 auto_k kmeans 策略、自定义调色板导入/预览/删除与项目持久化、core 覆盖矩阵门控、base_size 先验断言和 50 张分帧批量清洗性能断言。
- M1.1 改进: kmeans 空簇重播种；批量压测负载加重与 strict/relaxed 性能口径；覆盖矩阵反向 API 完整性检查与 EXEMPT 豁免；verify_m1_1 p95 回归带；inspector 文案迁入 PFStrings；mac 显示初步修复（inspector 接入 ui_scale、残留 interface_scale 迁移、缩放决策链日志、Cmd 快捷键）；完成报告改 git diff 模式；content_scale_factor 迁移决策卡入 M2。详见 M1_1_IMPROVEMENT_REPORT.md。
- mac 显示二次修复: 针对 `screen_get_scale=1.0` 且 `usable_rect` 为 macOS 点口径时自动检测仍落回 1.0 的复发场景，补 Retina 点尺寸兜底、窗口像素/点尺寸换算、窗口默认值日志和 smoke 覆盖；完整流程见 `MAC_DISPLAY_FIX_COMPLETION_REPORT.md`。
