# M5 — 地图拼接与多层动效合成（功能4）

> 目标：素材 → 完整场景：网格拼图画板（tileset 地形 + 自由摆放道具）+ 图层系统 + 动效层叠加 + 场景导出。
> 依赖：M2（素材库）、M1（色板校验）。可与 M3/M4 并行开发（接口独立）。
> 技术依据：RESEARCH-NOTES §1（TileMapLayer + Better Terrain 插件结论）、§4（blob 47 tileset 标准）。

---

## M5-1 拼图画板（Board）数据模型与基础 UI

**目标**：新文档类型 Board：有限尺寸网格画板（区别于无限画布——地图有边界），多图层。

**技术实现指导**：
- 数据模型（core 侧 `pf_board.gd`，序列化进 .pxproj boards/，PROJECT-FORMAT 的 board schema 在本卡正式定稿并回写契约文件——按 README 规则走契约修订流程）：
```json
{
  "id": "board_xx", "name": "farm_scene",
  "grid": { "tile_size": 16, "cols": 60, "rows": 40 },
  "layers": [
    { "id": "l1", "name": "terrain", "kind": "tile",   "visible": true, "opacity": 1.0,
      "cells": { "12,7": {"asset_id": "...", "variant": 3} } },
    { "id": "l2", "name": "props",   "kind": "free",   "items": [{"asset_id": "...", "pos": [192,112], "z": 0, "flip_h": false}] },
    { "id": "l3", "name": "vfx",     "kind": "free",   "items": [], "blend": "add", "anim_offset_ms": 0 }
  ]
}
```
- 两种图层：`tile`（网格吸附，单元=tile_size）与 `free`（像素级自由摆放，吸附可开关）——分别覆盖"地形"与"道具/角色/特效"。
- UI：Board 编辑 Tab：左素材库面板（标签筛选+搜索+缩略图，拖出即放置）、中画板（复用 M0 画布的相机交互代码——抽 `CameraRig` 公共组件）、右图层面板（增删/排序拖拽/显隐/不透明度/混合模式 normal|add|multiply）。
- 渲染：tile 层用 TileMapLayer（运行时构建 TileSet：每素材→一个 atlas source）；free 层用 Node2D+Sprite2D 池。
- 色板一致性：放置素材时若其 palette_ref ≠ 项目预设 → 角标警告（不阻断，提供"重映射到项目色板"快捷动作调 M1）。

**验收标准**：
1. 集成：建 60×40 板 → terrain 铺 200 tile + props 放 30 件 → 保存重开一致。
2. 图层操作（排序/显隐/混合）实时正确；free 层 add 混合视觉验证（fixture 发光特效图）。
3. 万格大板（100×100 铺满）平移缩放 60fps。

---

## M5-2 地形笔刷与自动拼接（autotile）

**目标**：痛点级功能：用户把"一套地形 tile"定义为地形组，笔刷涂抹自动选块。

**技术实现指导**：
- 地形组定义 UI：用户从素材库选 N 张 tile → 标注其 blob 角色。**两种路径**：
  - 自动识别：若素材是 M2 切分出的标准 47-blob sheet（或 16-blob 简化集），按位置模板自动映射——支持"AI 生成整张 tileset → 切分 → 一键成地形组"的核心流水线。
  - 手动标注：3×3 宫格代表图升级版（对 16-blob：每 tile 点选其四角连接性）。
- 笔刷算法**自实现 blob 匹配**（不依赖 Godot Terrain 系统——调研结论：其运行时 API 难用且有 bug；Better Terrain 是编辑器插件不可运行时用）：涂抹单元 → 计算 8 邻接位掩码 → 查 47/16-blob 映射表选 tile；缺块降级（47 缺块时回退最近形态 + 黄色提示角标）。
- 笔刷/橡皮/矩形填充/油漆桶（同地形 flood）。
- 随机变体：同一 blob 角色多 tile 时按 hash(坐标) 稳定随机（重绘不闪变）。

**验收标准**：
1. 单测：8 邻接掩码→blob 索引映射表全 256 case 正确（对照公开 blob 参考表）。
2. 集成：16-blob 地形组涂"U 形湖"→ 边角块全部正确；擦除中间→邻接自动更新。
3. 缺块降级有提示不崩溃。

---

## M5-3 动效层与帧序列叠加

**目标**：把"多层动效素材拼接合成"做实：board 上的 free 层条目可引用**动画素材**（帧序列），画板内实时预览叠加效果。

**技术实现指导**：
- 动画素材模型（anim/{id}.anim.json，契约在本卡定稿回写 PROJECT-FORMAT）：`{frames: [asset_id...], durations_ms: [...], loop: true}`——注意帧=独立素材（复用素材库），轻量。
- 来源：M2 切分的 spritesheet 一键转动画（切分结果按序成帧）；M6 编辑器产出；导入 GIF（解码为帧）。
- Board 渲染：free item 引用动画素材时用 AnimatedSprite2D 等价逻辑（自管理计时器统一驱动，全板同步时钟 + 每条目 anim_offset_ms 相位差——群体特效错峰自然感）。
- 播放控制：画板工具栏 播放/暂停/速度；性能：50 个动画条目同播 60fps。
- 静态导出时可选"指定时刻帧"或逐层全帧导出（见 M5-4）。

**验收标准**：
1. 火焰 8 帧素材放 20 个实例不同 offset → 同步播放正确、错峰可见、fps 达标。
2. anim.json round-trip；引用帧素材删除时引用完整性警告（M0-4 机制扩展）。

---

## M5-4 场景导出器

**目标**：board → 游戏引擎可用产物。

**技术实现指导**：
- 模式：
  - 整图 PNG（合并可见层，动画层取 t=0 或指定帧）。
  - 分层 PNG（每层一文件 + layers.json 描述混合/不透明度）。
  - 动画层帧序列（vfx 层 → 每帧一 PNG / spritesheet）。
  - Godot 友好导出（v1 简版）：tileset.png + board.tres 说明文档（教程式 docs，不做引擎插件——范围控制，记 backlog）。
- 大图拼接注意内存：分块绘制（Image.blit_rect 按层按区块流式合成），1 万格 ×16px = 1600×640 轻松，但预留 8000×8000 上限保护。

**验收标准**：
1. 三种模式产物在外部工具（图像查看器/Godot 导入）验证正确；分层 PNG 重叠还原与画板内渲染一致（混合模式 normal 层逐像素一致，add 层容差 ≤1/255）。
2. 万格导出 < 15s。

---

## M5 整体验收

- 用户旅程后半段落地：素材库 → 拼出农田场景（地形笔刷 + 道具 + 火把动效）→ 三种导出。录屏评审。
- Board 与无限画布的关系在 UI 上清晰（文档 Tab 模型：Canvas / Graph / Board 三类 Tab）。
