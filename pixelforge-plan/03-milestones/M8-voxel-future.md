# M8 — 体素方向研究简报（功能5b：远期，暂不执行）

> 状态：**研究简报，非执行任务**。在 M7（v1.0）完成并取得用户反馈后再评估立项。
> 本文件目的：把 2026-06 调研结论与可行架构路径存档，避免未来重新摸索；同时明确"现在不做"的理由。

## 1. 为什么现在不做（决策记录）

- 2026-06 现状：AI 文本生成体素仍处早期（text2vox 等开源方案质量不稳定；VoxAI 等商业平台刚起步）——调研详见 RESEARCH-NOTES §3.7。投入产出比远低于 2D 像素主线。
- 产品焦点风险：v1.0 前加入 3D 会稀释"像素美术瑞士军刀"定位与开发资源。
- 架构已预留：体素编辑器可作为新文档 Tab 类型（Canvas/Graph/Board/Editor/**Voxel**）+ 新节点类别 + 新 provider 能力位（capabilities.voxel）接入，**无需推翻任何 v1 架构**——这是现在敢推迟的底气。

## 2. 届时的实现路径草图（供未来立项参考）

### 2.1 数据与格式
- 内部模型：`PFVoxelGrid { size: Vector3i, palette: PFPalette, voxels: PackedByteArray (调色板索引, 0=空) }`——与 2D 共用调色板体系（产品一致性延伸到 3D）。
- 互操作：导入/导出 MagicaVoxel `.vox`（公开格式规范：ephtracy/voxel-model repo；GDScript 解析二进制 chunk 结构工作量 ~500 行）。.vox 是体素生态通用语，必做。

### 2.2 渲染与编辑（Godot 优势区）
- 渲染：贪婪网格化（greedy meshing）→ ArrayMesh，调色板色→顶点色；单 64³ 模型实时重建可行（参考开源 godot voxel 工具链；大场景才需要 Zylann/godot_voxel C++ 模块，素材级编辑用不到）。
- 编辑：射线投射放置/删除/涂色三工具起步；镜像对称；逐层切片视图（像素画师友好——每层切片就是一张像素画，**复用 M6 编辑器整套工具**在切片上绘制：这是本产品独有的"像素师视角体素工作流"卖点）。

### 2.3 AI 接入
- 短期最可行路径不是 text→voxel 直生，而是**多视图像素图 → 体素重建**：用成熟的 2D 像素生成（已有全套管线！）出正/侧/顶三视图 → 启发式体素雕刻（visual hull 交集 + 调色板投影）。中等质量但完全本地、可解释、可手修。
- text2vox/Trellis 类模型成熟后再加 provider（capabilities.voxel=true）。

### 2.4 体素贴图绘制
- 用户提的"体素 3D 贴图绘制"：体素模型本身即调色板索引（无 UV 贴图概念）；若指对体素表面投影绘制 → 切片绘制已覆盖；若指导出 mesh 后的 UV 贴图 → 属于通用 3D 工具范畴，建议保持范围外（导出 .obj 后交 Blender）。

## 3. 立项触发条件（满足任一即重评）
- 用户调研中 ≥ 20% 主动要求体素能力；
- 开源 text→voxel 模型质量跨越可用线（生成 32³ 道具一次可用率 > 50%）；
- 竞品推出同类功能形成压力。

## 4. 届时需要的新契约
- VOXEL-FORMAT.md（PFVoxelGrid 序列化 + .vox 互操作映射）
- PROVIDER-API 增补 voxel 能力位与 PFVoxGenRequest（api_version+1 走版本协商，旧 provider 不受影响——机制已就位）
