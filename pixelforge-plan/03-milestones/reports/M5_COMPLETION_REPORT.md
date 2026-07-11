# M5 工程完成报告（diff 模式）

> 分支：`codex/pixelforge-full-plan-goal`。按项目所有者指令，本阶段不做逐模块冒烟或人工审核；产品结论统一留到 M7 后总验收。

## 用户闭环

- 入口：`File > Open Board Editor...`。
- 过程：从可搜索素材库选择静态素材或动画，维护有限网格 Board、Tile/Free 图层、可见性/透明度/混合模式，使用普通、矩形、洪泛地形画笔和 16/47-blob 自动拼接。
- 反馈：缺失 terrain role 使用确定性最近角色并显示警告；素材与项目调色板不一致时显示显式警告；动画支持循环预览和逐实例偏移。
- 出口：平面 PNG、逐图层 PNG + JSON、动画帧序列及 Godot 导入指引；Board/Animation 随 `.pxproj` 保存重开。

## 关键 diff

- `PROJECT-FORMAT.md` 新增 `boards/{id}.json` 与 `anim/{id}.anim.json` 合同；ProjectService/PFProject 实现 zip 往返，未知字段无损保留。
- 新增 PFBoard、PFAnimation、PFTerrainGroup、PFTerrainBrush 与 16/47-blob 规范化；256 种 8 邻域掩码严格归一为 47 个角色。
- 新增 BoardEditor/BoardCanvas 可操作工作区，支持三种地形工具、图层管理、动画创建/播放、调色板风险反馈及真实混合预览。
- 新增 BoardExporter，限制单边 8000px，支持 normal/add/multiply、图层、动画和 Godot 指引导出。
- AssetLibrary 删除资产前检查 Board/Animation 引用，避免生成悬空文档。

## 自动化证据

- `./pixel/scripts/lint.sh`：153 files，无问题。
- `./pixel/scripts/run_tests.sh`：235/235 tests、2495 assertions 通过。
- 10,000 个 16px tile 合成为 1600×1600，自动性能阈值 15 秒；20 个错帧动画导出具备确定性覆盖。
- `./pixel/scripts/verify_m5.sh`：复用 M4 全门禁并检查合同、47-blob、10k 场景、三种画笔、UI 入口和受保护图片暂存区。

## 已知限制与统一验收项

- 当前 Board 作为独立对话框工作区接入，尚未升级为主窗口 Canvas/Graph/Board 常驻页签；功能闭环可操作，信息架构与视觉密度留到统一体验验收判断。
- 调色板不一致目前提供明确警告，不会静默改色；“一键重映射”仍由既有 Cleanup/Palette 流程完成，最终验收需判断是否必须在 Board 内增加快捷入口。
- 既有 1 个 GUT `error_tracker.gd` orphan 与退出资源警告仍存在；测试全绿，未发现 M5 用户数据损坏证据。
- 未提交任何真实/生成测试图片。所有人工视觉、真实素材和导出文件核对统一留到最终一次验收。

## 提交

- 对应本地里程碑提交：`M5 complete board scene workflow`（哈希以分支日志为准）。
- 不 merge `main`，不 push。
