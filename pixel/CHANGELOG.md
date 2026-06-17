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
- M2: 新增色键抠图、魔棒/矩形/套索选区模型、连通域切分、描边工具、spritesheet 导出器、顶栏批量 Matte/Slice/Outline 入口和 M2 自动化验收。
- M2.1: 新增 File > Import Images、Matte/Slice/Outline 参数预览对话框、W/M/L 像素选区工具、左下角缩放滑条、非纯色底错误引导、无连线批次卡与整批菜单。
- M2.2: 修复高分屏缩放钳制、清洗台矮窗可达性、批次卡可读尺寸与导入取景、滚轮缩放过冲、导出空选区提示、描边低 alpha 噪点和首启引导标记时机；暂隐藏未接入算法的 W/M/L 工具入口。
- M2.3: UI 缩放迁移到 `content_scale_factor`；删除组件级 `ui_scale` / `_scaled_int` 约定，画布按设备整数倍率反向补偿，并新增 M2.3 缩放守护脚本与回归测试。
- M2.4: 加固缩放体验，画布层平移吸附到物理像素网格，FileDialog 统一 Godot 自绘以跟随界面缩放，新增跨屏 live re-scale 防抖、`--scale-audit` 日志与 M2.4 出口门控。
- M2.4 追加修复: 拆分 UI 可读缩放与窗口像素几何缩放，修正无缩放 2K 偏小和 macOS Retina 内屏 UI 过大裁切的自动档位。
