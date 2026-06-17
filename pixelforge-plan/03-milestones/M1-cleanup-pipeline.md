# M1 — 像素清洗管线（功能1：对齐/缩放/重采样/量化/抖动）

> 目标：把 AI 生成的"伪像素图"一键清洗为真像素素材。本里程碑产出产品第一个核心价值，全部纯本地算法，无网络依赖。
> 依赖：M0。
> 算法依据：04-research/RESEARCH-NOTES.md §3（unfake.js / proper-pixel-art 等先例已验证全部算法路线）。

## M1 开始前置项

M1 会首次引入真正的 `core/pixel` 算法，因此以下事项需要作为 M1 开发前置工作，不再留到 M1 结束：

1. 建立 `tests/fixtures/generators/`：黄金样本必须由 GDScript 生成器产生，禁止手工 PNG 作为算法真值。真实 AI 样本只能用于人工评审。
2. 建立 core 覆盖率输出：目标对齐 `QUALITY.md`，`core/` 行覆盖 ≥80%。如果 GUT 覆盖率工具在 Godot 4.6 下有局限，至少要在完成报告中解释替代统计方法。
3. 对齐项目格式契约：M1 如果新增清洗 provenance、pipeline report 或样本字段，需要先更新 `02-contracts/PROJECT-FORMAT.md`，再修改实现。
4. 继续使用本地 agent 验证：M0 当前出口口径为 `pixel/scripts/verify_m0.sh`，M1 可新增 `verify_m1.sh`，但不能降低 lint/test/headless 三项底线。

---

## M1-1 调色板模块与内置调色板数据

**目标**：`core/pixel/palette.gd` + 9 个内置调色板 JSON（清单见 STYLE-PRESETS.md §3）。

**技术实现指导**：
- `PFPalette { id, name, colors: PackedColorArray }`；`from_json/to_json`。
- 最近色映射：实现 RGB 欧氏与 **OKLab** 距离两种（OKLab 优于 CIELAB 且实现简单，转换公式见 Björn Ottosson 公开文章；纯函数易测）。默认 OKLab。
- 性能关键：`map_image(img, palette) -> Image` 对全图映射。优化：颜色查找表缓存（同色像素只算一次——伪像素图颜色高度重复，命中率极高）。
- 从图像提取调色板：中位切分（median cut）实现 `extract_palette(img, k) -> PFPalette`（k-means 作为质量增强可选，先 median cut 保速度）。
- 内置调色板 JSON 数据：从 Lospec 公开数据（CC0）手工录入 hex 列表，**逐色核对**。

**验收标准**：
1. 单测：构造 4 色图 + DB32 映射，每像素结果等于手算最近色（OKLab 与 RGB 各验 3 个边界用例）。
2. 单测：纯色图提取 k=4 调色板恰得该色；双色棋盘图提取恰得两色。
3. 512×512 全图映射 < 300ms（缓存命中场景）。

---

## M1-2 网格检测器（grid_detector.gd）—— 本里程碑技术核心

**目标**：输入伪像素 Image，输出 `{scale: float, offset: Vector2, confidence: float}`（每个逻辑像素≈scale 物理像素，网格相位 offset）。

**技术实现指导**（按 RESEARCH-NOTES §3.1，参照 unfake.js/proper-pixel-art 思路用 GDScript 重实现）：
1. 灰度化 + Sobel 梯度幅值图（手写卷积，3×3 核，PackedFloat32Array 上算，不逐 Color 对象操作——性能）。
2. 梯度沿 x、y 轴分别投影（按列/行求和）得两条 1D 信号。
3. 对投影信号做**自相关**（朴素 O(n·maxlag) 足够：maxlag ≤ 64）；峰值间距的众数 = 该轴 scale。x/y 取均值（限制：先假设方形像素；非方形列为 future，meta 中记录）。
4. 相位 offset：固定 scale 后，穷举 offset ∈ [0, scale)，最大化"网格线位置上的梯度能量和"。
5. confidence：峰值显著性（主峰能量/均值能量），< 阈值（调参定，初始 2.0）视为"非像素图或网格太乱"，UI 提示走手动模式。
6. **手动覆盖路径**：检查器面板允许用户直接指定 scale/offset（拖网格叠加层对齐），算法只是给初值——这是兜底，必须有。
7. 若 style preset 提供 base_size 先验：在先验 ±30% 范围内搜索 scale，提高鲁棒性。

**验收标准**：
1. 黄金测试集（fixtures 程序生成）：取 8 张已知真像素图（含 16/32/48px 内容），分别施加 {×3.7 双线性放大, ×4 + (1,2)px 平移, ×6.2 + JPEG 噪声 q=85} 变换共 24 个样本 → 检测 scale 误差 ≤ 5%，offset 误差 ≤ 1 物理像素，达标率 ≥ 90%（允许 JPEG 重噪声组 2 例失败但 confidence 须正确报低）。
2. 纯照片输入：confidence 低于阈值（不误报）。
3. 512×512 检测耗时 < 1s。

---

## M1-3 重采样器（resampler.gd）

**目标**：按检测/指定的网格把图降到逻辑分辨率。

**技术实现指导**：
- 三种策略枚举：`mode`（众数，默认）、`center`（中心点）、`median`（通道中位数）。
- 众数实现：每网格单元统计颜色出现次数（Dictionary[int(rgba32)] 计数）；并列取靠单元中心者。
- 透明处理：alpha < 128 视为透明票仓，独立计票（防边缘半透明污染）。输出像素 alpha 二值化（0/255）——可选参数 `keep_alpha_gradient=false` 默认。
- 输出尺寸 = ceil(src/scale)，边缘不完整单元正常计票。

**验收标准**：
1. 单测：已知答案往返——真像素图 ×4 最近邻放大后 mode 重采样 = 原图逐像素一致（3 种内容样本）。
2. 加 10% 椒盐噪声后 mode 重采样仍 ≥ 99% 像素与原图一致（mode 抗噪验证，center 会失败——对照断言其确实更差以验证策略差异真实存在）。

---

## M1-4 量化器与抖动器（quantizer.gd / ditherer.gd）

**目标**：颜色数压缩到风格预设目标；可选抖动。

**技术实现指导**：
- 量化两模式：`auto_k`（median cut 到 max_colors_per_sprite）与 `fixed_palette`（palette.map_image）。
- 抖动（ditherer.gd）：`bayer2/4/8`（标准 Bayer 矩阵阈值法，作用于量化误差方向）与 `error_diffusion`（Floyd-Steinberg，serpentine 扫描）。strength 参数 0–1 线性缩放阈值扰动幅度。
- **像素画默认 none/bayer**（调研：社区美学偏好 ordered；FS 仅照片转像素场景）——默认值进 StylePreset 不在算法里写死。
- 抖动在量化时联动（先扰动再找最近色），不是后处理叠加。

**验收标准**：
1. 单测：渐变图 fixed_palette(bw_2) + bayer4 → 输出仅含 2 色且呈 Bayer 周期图案（断言 4×4 平铺周期性）。
2. 量化后任意图颜色数 ≤ 目标 k（硬性）。
3. strength=0 时输出与无抖动逐像素一致。

---

## M1-5 清洗管线编排 + 检查器 UI

**目标**：`pipeline.gd` 串全链 + 右侧检查器面板交互，画布元素一键清洗。

**技术实现指导**：
- `PFCleanupParams`（Dictionary 契约，提交时写入 docs 注释）：`{detect: auto|manual, scale, offset, resample: mode|center|median, quantize: none|auto_k|fixed_palette, palette_id, k, dither, dither_strength, target_size: null|Vector2i}`。默认值从当前项目 StylePreset 派生（契约 STYLE-PRESETS §2）。
- `pipeline.apply(src, params) -> {image, report}`，report 含各步骤实际参数与 confidence（UI 展示 + 写 provenance）。
- UI：选中画布元素 → 检查器出现"像素清洗"区：检测结果展示（scale/conf）、参数控件、**实时预览**（300ms 防抖后台跑管线，预览叠加在元素上半透明对比 / 按住 Alt 看原图）、Apply（生成新素材+新元素并排放置，原图保留——体验原则4）。
- 批量：多选元素 → 同参数批量 Apply（task_queue 并行，进度角标）。
- 手动网格模式：叠加可拖拽网格线 overlay。

**验收标准**：
1. 端到端集成测试：fixtures 伪像素图 → 默认参数 apply → 输出尺寸/色数/网格对齐全达标。
2. 50 张批量清洗 UI 不冻结（帧时间监控断言），总耗时 < 60s（自动化环境放宽 2 倍）。
3. 手动模式拖网格后 Apply 结果与指定网格一致。
4. 实测 3 张真实 AI 生成图（fixtures/real/ 目录，从公开模型生成存档）效果人工评审通过——评审标准：无肉眼可见网格错位、色数达标、关键轮廓未损。

---

## M1 整体验收

- v0.1 内部版本：拖入 AI 图 → 清洗 → 导出 PNG（画布右键导出单图，简版）跑通。
- 性能预算表（ARCHITECTURE §7）实测数字填入 RESEARCH-NOTES 附录，超标项立替换决策卡。
- 预估 ~2500 行 + 测试。
