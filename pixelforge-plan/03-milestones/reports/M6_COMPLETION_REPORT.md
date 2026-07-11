# M6 工程完成报告（diff 模式）

> 分支：`codex/pixelforge-full-plan-goal`。按项目所有者指令，不进行逐模块冒烟/审核；人工视觉与完整旅程统一留到 M7 后一次验收。

## 用户闭环

- 从无限画布 sprite 或 batch 缩略图双击进入独立 Pixel Repair Editor，也可通过 File/批次菜单进入；短过渡遮罩避免硬切。
- 编辑器提供铅笔、橡皮、取色、局部/全局填充、直线、矩形、椭圆、选择移动、1–8px 笔刷、像素完美线、水平/垂直镜像、透明棋盘与像素网格。
- 项目预设色板自动载入；默认约束模式用 OKLab 最近色吸附，支持色板增删重排、跨层/帧颜色重映射和全图量化。
- 图层支持导入、显隐、锁定、透明度；时间线支持新增、复制、删除、重排、逐帧时长、洋葱皮、播放、1x/2x/4x 独立预览和帧标签。
- 默认另存为新素材并写 `origin=edited`、`parent_asset`；覆盖源素材前确认。batch 来源自动替换队列引用；多帧写回 M5 Animation，Board 可立即播放。
- AI 修图增强提供孤立杂色清扫（保护显著高光）、断线端点高亮；inpaint 无 Provider 能力时按合同灰显并解释原因。

## 关键 diff

- 新增帧×层 `PFEditDoc`、独立 `PFEditHistory`、确定性绘制算法和修图分析器。
- 抽取 `PFCompositor`，BoardExporter 与编辑器拍平共用 normal/add/multiply 语义。
- Animation 合同增加可选 tags；spritesheet JSON 输出 `frameTags`。
- InfiniteCanvas 增加 sprite/batch 精确双击路由；编辑结果按来源回写 sprite 或 batch，画布 UndoService 与编辑器历史保持隔离。

## 自动化证据

- `./pixel/scripts/lint.sh`：166 files，无问题。
- `./pixel/scripts/run_tests.sh`：248/248 tests、3556 assertions 通过；`verify_m6.sh` 最终输出 `ok`。
- 120Hz 模拟圆形笔迹无断点；1000 步随机约束绘制后颜色集始终属于色板。
- 32×32 全帧色板重映射自动阈值 <50ms；32 层×64 帧拍平自动阈值 <500ms。
- 8 帧编辑→Animation tags/duration→Board 合成跨里程碑回归通过。

## DoD 核查

| 项 | 状态 | 证据/路径 |
|---|---|---|
| 代码规范 | 通过 | `pixel/scripts/lint.sh` |
| 自动测试 | 通过 | M6 unit/integration tests + `verify_m6.sh` |
| 手动测试 | 延期登记 | 项目所有者要求最终统一验收 |
| 契约同步 | 通过 | `PROJECT-FORMAT.md` Animation tags |
| TODO | 通过 | M6 门禁扫描无无主标记 |
| 性能预算 | 通过 | 120Hz、50ms、500ms 自动哨兵 |
| 跨平台 | 延期登记 | M7 最终候选统一执行 |
| 出口门控 | 通过 | `verify_m6.sh` |

工程结论：**工程通过；人工通过/发布通过均未声明。**

## 已知限制与统一验收项

- 过渡使用短共享元素遮罩，不做逐像素源卡几何 morph；最终体验验收决定是否值得增加更复杂动画。
- 杂色清扫当前确认后立即应用，端点检测提供高亮但不自动修线；这是保护像素轮廓语义的有意边界。
- inpaint 只实现能力感知占位，没有 Provider 宣称该能力时不会伪造可用链路。
- 既有 1 个 GUT `error_tracker.gd` orphan 与退出资源警告保持不变；未提交测试图片。

## 提交

- 对应本地提交：`M6 complete pixel repair editor`（哈希以分支日志为准）。
- 不 merge `main`，不 push。
