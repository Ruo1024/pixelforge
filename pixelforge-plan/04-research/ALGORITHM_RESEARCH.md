# 像素画处理算法研究报告

> 基于 pixelforge 当前实现（resampler.gd / ditherer.gd / pipeline.gd）的算法缺陷分析与改进方案。

---

## 章节1：边缘感知重采样（Edge-Aware Resampling）

### 1.1 问题背景

当前 `_sample_cell()` 对所有网格格子使用同一策略（mode/center/median），不区分边缘格与内部格。对于像素画下采样，高反差边缘区域的网格格子内往往存在两种截然不同的颜色，直接取众数会导致细线丢失或边缘发生颜色"渗漏"。

### 1.2 如何判断一个网格格子是否处于边缘区域

GridDetector 中已有 Sobel 算子实现（`_sobel_magnitude`），可直接复用。

**判断标准：格内梯度能量阈值法**

对格子内每个像素计算 Sobel 幅值，取平均值：

```
edge_energy = mean(sobel(pixel) for pixel in cell)
is_edge_cell = edge_energy > threshold   # 推荐阈值 0.12~0.20（归一化梯度）
```

更精确的方式是计算"颜色方差"：若格内最大色差（Δ in OKLab）超过阈值（如 0.15），则标记为边缘格。颜色方差比原始梯度更能反映下采样问题的本质——格内是否同时存在多种视觉差异颜色。

**GDScript 可用的最简实现：**

```gdscript
static func _is_edge_cell(image: Image, cell: Rect2i, threshold: float = 0.15) -> bool:
    var colors: Array[Color] = []
    for y in range(cell.position.y, cell.position.y + cell.size.y):
        for x in range(cell.position.x, cell.position.x + cell.size.x):
            colors.append(image.get_pixel(x, y))
    if colors.size() < 2:
        return false
    # 用亮度极差作快速判断
    var min_l := 1.0
    var max_l := 0.0
    for c in colors:
        var l := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
        min_l = minf(min_l, l)
        max_l = maxf(max_l, l)
    return (max_l - min_l) > threshold
```

### 1.3 边缘格的最优采样策略

**问题**：众数策略在边缘格中会偏向面积大的颜色，导致细线消失。

**推荐策略：沿边缘方向的定向投票（Directional Mode Sampling）**

原理：
1. 计算格内主梯度方向（Gx/Gy 分量的均值），得到边缘的法线方向。
2. 将格内像素分为"边缘法线正侧"和"负侧"两组。
3. 分别对两组取众数，选取与相邻格颜色连续性更好的那个。

更简单但有效的近似方案——**双色分离投票**：

```
1. 对格内所有像素做 K=2 的 K-means 聚类（或简单的亮度二分）
2. 若两类颜色的 OKLab 距离 > 分离阈值，则此格为"双色边缘格"
3. 选择与四个方向相邻格颜色距离最近的那个颜色作为输出
   （而不是取面积最大的颜色）
```

这种方法的效果：细线（1px 逻辑宽）不会因为物理像素占比少于50%而消失；斜线锯齿更平滑。

### 1.4 perfectPixel 的 refine_grids 思路对边缘的意义

`refine_grids` 的核心思想：让每条网格线（grid line）吸附到梯度峰值位置，而不是严格按等间距放置。

**原理**：真实像素画的物理像素边界恰好对应梯度峰值（颜色跳变点）。若网格线稍微偏移，会导致一个逻辑像素格内同时包含两个相邻逻辑像素的像素，造成颜色混合。让网格线吸附到梯度峰值后：

- 边缘格内的像素颜色分布更纯净（两侧颜色不再混入同一格）
- mode/center 采样的结果都会更准确
- 等效于在采样前做了边缘对齐的预处理

`grid_detector.gd` 中的 `_find_offset()` 函数已实现了基于 Sobel 投影的偏移优化，这正是 refine_grids 的简化版本。更完整的实现可以对每条网格线独立做局部梯度峰值搜索（±半格范围内），代替全局统一偏移。

### 1.5 具体的 GDScript 可实现方案："边缘感知 mode 采样"

**函数签名扩展：**

```gdscript
# 在 resampler.gd 中新增参数
const MODE_EDGE_AWARE := "edge_aware"

# _sample_cell 中新增分支
static func _sample_cell(image: Image, cell: Rect2i, mode: String, keep_alpha_gradient: bool) -> Color:
    if mode == MODE_EDGE_AWARE:
        return _sample_edge_aware(image, cell, keep_alpha_gradient)
    # ... 原有分支不变

static func _sample_edge_aware(image: Image, cell: Rect2i, keep_alpha_gradient: bool) -> Color:
    const EDGE_THRESHOLD := 0.15
    if not _is_edge_cell(image, cell, EDGE_THRESHOLD):
        return _sample_mode(image, cell, keep_alpha_gradient)  # 内部格：原有众数
    # 边缘格：双色分离，取与中心色更近的颜色
    var center_color := _sample_center(image, cell, keep_alpha_gradient)
    var mode_color := _sample_mode(image, cell, keep_alpha_gradient)
    # 若众数颜色与中心颜色差异过大，说明中心像素恰好在少数派颜色上
    # 此时倾向于中心颜色（保留细线）
    var center_l := center_color.r * 0.299 + center_color.g * 0.587 + center_color.b * 0.114
    var mode_l := mode_color.r * 0.299 + mode_color.g * 0.587 + mode_color.b * 0.114
    if absf(center_l - mode_l) > EDGE_THRESHOLD:
        return center_color  # 中心像素处于边缘少数派，优先保留
    return mode_color
```

**性能影响**：`_is_edge_cell` 仅做亮度极差计算，每格增加 O(n) 次浮点比较（n 为格内像素数），可接受。

### 1.6 小结

| 策略 | 内部格 | 边缘格 |
|------|--------|--------|
| 当前 mode | 优（稳定）| 差（细线丢失）|
| edge_aware | 同 mode | 优（保留细线）|
| 双色分离投票 | 中等 | 最优（需 KMeans）|

推荐实现顺序：先实现 `edge_aware`（亮度极差 + center/mode 切换），再考虑双色分离投票。

---

## 章节2：艺术性"缺陷像素"抖动（Chromatic Dithering）

### 2.1 "缺陷像素"的视觉效果与历史来源

8-bit 时代（NES、Game Boy、Amiga OCS 等）的显示硬件存在固有色噪：DAC 转换误差、模拟信号串扰、CRT 磷光点间距等物理因素叠加，造成颜色在空间上的随机性扰动。这种扰动的关键特征是**色度噪声**而非单纯亮度噪声——相邻像素不只是亮一点/暗一点，而是色相也会轻微飘移（偏绿、偏洋红等）。

当代像素艺术家刻意复现这种效果（俗称"crunchy dithering"或"broken pixels"）来：
- 增加视觉纹理密度，避免大色块的塑料感
- 模拟老硬件的怀旧质感
- 在调色板受限情况下增加有效色彩过渡

Lucas Pope 在 **Return of the Obra Dinn** 中使用了精心设计的 1-bit 有序抖动，通过视觉混色（小格 Bayer 矩阵）让双色画面产生丰富的灰度感知，是现代"美学缺陷"抖动的标志性案例。

**当前实现的核心缺陷**（来自 ditherer.gd）：
```gdscript
var offset := (threshold - 0.5) * strength * ORDERED_AMPLITUDE  # 单一 offset
Color(r + offset, g + offset, b + offset, a)  # 三通道同步偏移
```
三通道加同样的偏移 = 只扰动亮度（沿 RGB 灰轴移动）= 调色板映射时只选更亮或更暗的颜色，无法触达色相不同的邻近调色板颜色。

### 2.2 OKLab 色空间中的 a/b 轴扰动原理

OKLab 是感知均匀色空间，三轴含义：
- **L**：感知亮度（0=黑，1=白）
- **a**：绿←→品红轴
- **b**：蓝←→黄轴

当前抖动只扰动 L 轴。引入 a/b 扰动后，颜色会在色相环上产生漂移，扰动后映射到调色板时会选择色相不同的临近色，产生真正的色度噪声。

**OKLab 与 Linear RGB 的互转（GDScript 可实现版本）：**

```gdscript
# sRGB → Linear RGB（近似）
static func srgb_to_linear(c: float) -> float:
    return c * c  # 精确版用 pow(c, 2.2)，快速近似足够

# Linear RGB → OKLab
static func rgb_to_oklab(r: float, g: float, b: float) -> Vector3:
    var lr := srgb_to_linear(r)
    var lg := srgb_to_linear(g)
    var lb := srgb_to_linear(b)
    var l := 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
    var m := 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
    var s := 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
    var lc := pow(l, 1.0/3.0)
    var mc := pow(m, 1.0/3.0)
    var sc := pow(s, 1.0/3.0)
    return Vector3(
        0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc,
        1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc,
        0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc
    )

# OKLab → sRGB（逆变换）
static func oklab_to_rgb(L: float, a: float, b: float) -> Color:
    var lc := L + 0.3963377774 * a + 0.2158037573 * b
    var mc := L - 0.1055613458 * a - 0.0638541728 * b
    var sc := L - 0.0894841775 * a - 1.2914855480 * b
    var l := lc * lc * lc
    var m := mc * mc * mc
    var s := sc * sc * sc
    var lr := +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    var lg := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    var lb := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return Color(clampf(sqrt(maxf(lr,0.0)), 0.0, 1.0),
                 clampf(sqrt(maxf(lg,0.0)), 0.0, 1.0),
                 clampf(sqrt(maxf(lb,0.0)), 0.0, 1.0), 1.0)
```

### 2.3 参数化控制设计

三个独立维度：

| 参数 | 含义 | 实现 | 推荐范围 |
|------|------|------|----------|
| `contrast` | L 轴扰动幅度 | L += offset_L | 0.0 ~ 0.25 |
| `chroma` | a/b 轴扰动幅度 | a += offset_a, b += offset_b | 0.0 ~ 0.15 |
| `density` | 触发扰动的概率 | if threshold < density: apply | 0.0 ~ 1.0 |

`density` 控制多大比例的像素被扰动——低密度时产生稀疏噪点，高密度时接近全覆盖有序抖动。

a/b 轴的扰动方向：可以使用 Bayer 矩阵的两个独立位平面分别驱动 a 和 b 轴，或者使用旋转角度将单一 threshold 映射为色相旋转：

```
angle = threshold * 2π
offset_a = chroma * cos(angle)
offset_b = chroma * sin(angle)
```

这样抖动图案会在色相环上均匀分布，避免颜色偏向某一色相。

### 2.4 调色板约束下色度扰动的作用机制

关键洞察：抖动扰动本身不是最终颜色，而是**影响调色板最近色选择**的扰动。

```
原始颜色 C  →  扰动后 C'  →  find_nearest_palette_color(C')  →  输出颜色 P
```

纯亮度扰动（当前实现）：C' 在灰轴方向移动，只能选到亮度不同的调色板颜色。
色度扰动：C' 在色相方向移动，可以触达调色板中**色相不同**的近邻颜色，产生真正的颜色噪点。

实现要点：
- 扰动幅度应校准到调色板相邻颜色间距（OKLab 距离）的 40%~70%，太小无效（不足以切换颜色），太大造成跳变过于明显
- 对于 db16 等低色数调色板，chroma 建议 ≤ 0.08；对 aap64 等高色数调色板，可放宽到 0.15

### 2.5 GDScript 实现方案

**函数签名：**

```gdscript
# ditherer.gd 新增模式常量
const MODE_CHROMATIC := "chromatic"

# 新增参数化色度抖动函数
static func chromatic_adjust(
    color: Color,
    x: int, y: int,
    bayer_mode: String,    # 驱动矩阵，如 MODE_BAYER4
    contrast: float,       # L 轴扰动幅度 [0,0.25]
    chroma: float,         # a/b 轴扰动幅度 [0,0.15]
    density: float         # 触发密度 [0,1]
) -> Color:
    var threshold := ordered_threshold(x, y, bayer_mode)
    if threshold > density:
        return color  # 此像素不扰动
    
    # 转到 OKLab
    var lab := rgb_to_oklab(color.r, color.g, color.b)
    
    # L 轴扰动（对应当前 contrast 参数）
    var L_offset := (threshold - 0.5) * contrast * ORDERED_AMPLITUDE
    
    # a/b 轴扰动（色相旋转）
    var angle := threshold * TAU
    var a_offset := chroma * cos(angle)
    var b_offset := chroma * sin(angle)
    
    var result := oklab_to_rgb(
        clampf(lab.x + L_offset, 0.0, 1.0),
        lab.y + a_offset,
        lab.z + b_offset
    )
    result.a = color.a
    return result
```

**在 quantizer.gd 中的集成位置**：在 `find_nearest_palette_color` 调用之前，将 `ordered_adjust` 替换/扩展为 `chromatic_adjust`，其余流程不变。

**向后兼容**：`chroma=0` 时退化为纯 L 轴扰动，行为与当前一致。

---

## 章节3：管线扩展性改进

### 3.1 当前 pipeline.gd 设计分析

当前架构是**线性静态函数链**：

```
apply() → _resolve_grid() → Resampler.resample() → _apply_quantize() → Ditherer
```

问题：
- 每新增一个处理步骤（锐化、去噪、色调映射等）都需要修改 `apply()` 函数本体
- 参数字典 `merged` 扁平化，所有步骤共用同一命名空间，参数名容易冲突
- 步骤之间无法动态启用/禁用，只能靠 `mode == "none"` 约定
- 没有中间结果暴露机制，调试困难

### 3.2 "处理步骤注册表"/"策略链"设计方案

**方案：步骤数组 + 统一 context 字典**

每个步骤是一个拥有 `apply(context) -> context` 接口的对象（在 GDScript 中用 Dictionary + Callable 或 RefCounted 子类实现）：

```gdscript
# 步骤接口约定（概念伪代码）
# context 包含：image, params, report（累积报告）

class_name PFPipelineStep extends RefCounted
    var name: String
    func apply(ctx: Dictionary) -> Dictionary:
        return ctx  # 默认透传

# pipeline.gd 改造
static func apply(source: Image, params: Dictionary = {}) -> Dictionary:
    var steps := _build_steps(params)
    var ctx := {"image": source.duplicate(), "params": params, "report": {}}
    for step in steps:
        if step.enabled(ctx):
            ctx = step.apply(ctx)
    return {"image": ctx["image"], "report": ctx["report"]}

static func _build_steps(params: Dictionary) -> Array:
    return [
        PFStepDetectGrid.new(),
        PFStepResample.new(),
        PFStepSharpen.new(),   # M2 新增，disabled by default
        PFStepDenoise.new(),   # M2 新增，disabled by default
        PFStepQuantize.new(),
    ]
```

每个步骤只读写自己关心的 context 键，互不干扰。

**最小改造路径**（不破坏现有接口）：在现有 `apply()` 内部引入步骤列表，外部接口保持不变：

```gdscript
# 在 apply() 内部用数组描述步骤，便于插入新步骤
var pipeline := [
    func(ctx): return _step_detect(ctx),
    func(ctx): return _step_resample(ctx),
    func(ctx): return _step_quantize(ctx),
]
for step_fn in pipeline:
    ctx = step_fn.call(ctx)
```

### 3.3 参数字典的扩展性设计建议

**当前问题**：所有步骤参数扁平化在同一字典，如 `mode` 既可能指 resample mode 也可能指 quantize mode。

**推荐：按步骤命名空间分组**

```gdscript
# 新参数结构（向后兼容：顶层 key 仍作为 fallback）
{
    "detect": {"method": "auto", "base_size": 0},
    "resample": {"mode": "edge_aware", "scale": 4.0, "offset": Vector2.ZERO},
    "sharpen": {"enabled": false, "amount": 0.5},
    "denoise": {"enabled": false, "radius": 1},
    "quantize": {
        "mode": "auto_k",
        "palette_id": "db32",
        "k": 16,
        "dither": "bayer4",
        "dither_strength": 0.5,
        "chroma": 0.0,     # 新增色度参数
        "contrast": 0.5,
        "density": 1.0,
    }
}
```

`default_params()` 负责填充所有默认值，步骤从 `ctx["params"]["resample"]` 等子字典中读取，避免冲突。

### 3.4 M2 加入"锐化"和"去噪"预处理步骤需要的改动

当前结构需要的改动清单：

**最小改动（不重构）：**
1. `apply()` 中在 `Resampler.resample()` 调用后、`_apply_quantize()` 调用前，插入两个可选函数调用：
   ```gdscript
   if merged.get("sharpen_enabled", false):
       resampled = _apply_sharpen(resampled, merged)
   if merged.get("denoise_enabled", false):
       resampled = _apply_denoise(resampled, merged)
   ```
2. `default_params()` 中增加 `sharpen_enabled: false`、`denoise_enabled: false` 等默认值
3. Report 字典中增加对应步骤的报告节点

**理想改动（同时重构为步骤链）：**
按 3.2 方案将 pipeline 改为步骤数组，新步骤只需添加到数组中，无需修改 `apply()` 本体。

**锐化实现推荐**：非锐化掩蔽（Unsharp Mask），对下采样后的图像施加，强度 0.3~0.8 之间可调。

**去噪实现推荐**：双边滤波（Bilateral Filter）或简单的中值滤波，去除量化引入的椒盐噪点。GDScript 中双边滤波计算量较大，推荐先实现 3×3 中值滤波作为快速方案。

---

## 章节4：调色板覆盖度分析

### 4.1 当前9个调色板的覆盖盲区

基于对现有调色板的分析（颜色数/深浅分布/饱和度分布）：

| 调色板 | 颜色数 | 皮肤色 | 鲜艳色 | 柔和色 | 大地色 | 定位 |
|--------|--------|--------|--------|--------|--------|------|
| db16   | 16     | 3      | 0      | 2      | 1      | 复古极简 |
| db32   | 32     | 3      | 3      | 1      | 2      | 通用经典 |
| pico8  | 16     | 2      | 9      | 1      | 0      | 高饱和卡通 |
| endesga32 | 32  | 8      | 9      | 2      | 0      | 游戏人物 |
| endesga64 | 64  | 9      | 26     | 3      | 0      | 高饱和游戏 |
| aap64  | 64     | 6      | 13     | 3      | 5      | 综合写实 |
| gb_4   | 4      | 0      | 0      | 0      | 0      | Game Boy |
| nes_full | 55   | 4      | 45     | 3      | 0      | NES 硬件全色 |
| bw_2   | 2      | 0      | 0      | 1      | 0      | 1-bit |

**主要覆盖盲区：**

1. **柔和/粉彩色系严重不足**：所有调色板的柔和色（低饱和度、高亮度）都极少（最多3个）。这意味着处理柔和水彩风格、粉色系、浅色调插画时，量化效果差。

2. **大地色/自然色贫乏**：只有 aap64（5个）和 db32（2个）有较多大地色。处理森林、建筑、角色皮肤（暗部）等自然场景时选择有限。

3. **极深色覆盖不足**：大多数调色板深色（亮度<0.15）只有1~3个，黑色到深色的渐变过渡困难。

4. **冷色调中间调不足**：蓝灰、紫灰等低饱和冷色调（用于阴影）在大多数调色板中缺失，aap64 相对最好。

5. **无灰度阶调色板**：现有调色板中没有纯灰阶（4~8级）调色板，适用于素描风格转换时需要手动用 bw_2 或自定义。

### 4.2 推荐补充的调色板

| 推荐调色板 | 颜色数 | 补充理由 | Lospec ID |
|-----------|--------|----------|-----------|
| **GameBoy Color** (GBC) | 10~56 | 弥补 gb_4 过于极端、gb_full 缺失的问题；GBC 硬件色彩在像素游戏中极常见 | `gbc-lcd` |
| **CGA (Mode 4)** | 4 | 经典 PC 颜色，洋红+青色+白+黑的特征色彩，复古 PC 风不可缺少 | `color-graphics-adapter` |
| **C64 (Commodore 64)** | 16 | 16色中有大量大地色、棕色系，覆盖当前盲区 | `commodore64` |
| **MSX** | 15 | 覆盖鲜艳+暗色混合，日式复古风格 | `msx` |
| **Apollo** (aap作者另一套) | 42 | 专注柔和色，弥补粉彩盲区 | `apollo` |
| **Sweetie-16** | 16 | 平衡的全色系极简调色板，比 pico8 更中性 | `sweetie-16` |
| **灰阶8级** | 8 | 自定义：纯感知均匀灰阶，素描/速写风格 | 自建 |

**优先级推荐**：先加 C64（覆盖大地色盲区）+ Apollo（覆盖柔和色盲区）+ 灰阶8级（新用途）。

### 4.3 Median Cut 在 RGB 空间的问题

**核心问题**：Median Cut 算法在 RGB 立方体上做颜色空间分割，而 RGB 不是感知均匀色空间。

具体缺陷：
1. **感知不均匀**：RGB 空间中等距的两个颜色，人眼感知的差异差别很大。例如深蓝区域 RGB 距离 10 可能几乎看不出差别，但浅绿区域同样距离差异显著。
2. **过度采样高亮蓝色**：人眼对蓝色亮度变化不敏感，但 Median Cut 在 RGB 空间会给蓝色通道分配与红绿同等的权重，导致调色板在蓝色系过度细分。
3. **皮肤色/棕色聚类差**：皮肤色在 RGB 空间聚集在狭小区域，Median Cut 倾向于合并它们，导致皮肤渐变失真。

**解决方案：在 OKLab 空间做 Median Cut / K-means**

OKLab 是感知均匀色空间，L/a/b 各轴的等距变化对应人眼的等感知差异。在 OKLab 空间做聚类：
- 切分时权重自然与感知差异对齐
- 皮肤色、暗色等聚集区域不会被过度合并
- 最终调色板颜色分布更均匀，整体量化误差（感知意义上）更小

**GDScript 改动位置**：`quantizer.gd` 中的颜色聚类/k-means 部分，将颜色转换改为 OKLab 后做距离计算，聚类完成后转回 sRGB 存储。对应的 `palette.gd` 中 `DISTANCE_OKLAB` 已用于最近色查找，聚类部分对齐即可。

---

## 章节5：综合改进建议（优先级排序）

以下改进项按"影响/工作量比"排序，优先实现高收益低成本的项目。

---

### P1（高优先级）— 立即可做，收益显著

#### 5.1 色度抖动（Chromatic Dithering）

**影响**：直接解决用户需求"反差度+色度饱和度可控的缺陷像素效果"，是当前最明显的功能缺口。  
**工作量**：小。只需修改 `ditherer.gd` 的 `ordered_adjust()`，新增 OKLab 互转函数（约30行），并在 `quantizer.gd` 传递新参数。  
**推荐实现**：见章节2.5，新增 `chromatic_adjust()` 函数，`chroma=0` 时行为完全向后兼容，无破坏性风险。  
**新增参数**：`dither_chroma: float = 0.0`，`dither_density: float = 1.0`。

#### 5.2 边缘感知重采样（Edge-Aware Resampling）

**影响**：改善高反差边缘的细线丢失问题，对精细 pixel art（1~2px 细线、斜线）效果提升明显。  
**工作量**：小。在 `resampler.gd` 新增 `MODE_EDGE_AWARE` 分支和 `_is_edge_cell()` 函数（约20行），原有代码不变。  
**推荐实现**：见章节1.5的亮度极差方案，无需引入 Sobel，纯亮度极差判断即可。  
**新增参数**：`resample: "edge_aware"`（新模式，需在 UI 下拉选项中注册）。

---

### P2（中优先级）— 有明确收益，需要一定设计工作

#### 5.3 补充调色板（C64 + Apollo + 灰阶8级）

**影响**：覆盖当前调色板的大地色盲区（C64）和柔和色盲区（Apollo），扩展使用场景。灰阶8级支持素描转换新用途。  
**工作量**：小（JSON文件）+ 小（注册到 BUILTIN_IDS）。从 Lospec 获取颜色数据，写成与现有格式相同的 JSON，添加到 `palette.gd` 的 `BUILTIN_IDS` 数组。  
**注意**：调色板文件需核实版权/授权（Lospec 上大多数调色板为公开免费使用）。

#### 5.4 OKLab 空间的自动 K-means 量化

**影响**：显著改善自动调色板提取（`quantize: "auto_k"` 模式）对皮肤色、大地色的聚类质量，减少量化误差。  
**工作量**：中。需修改 `quantizer.gd` 的聚类逻辑，将距离计算从 RGB 改为 OKLab（需引入 `rgb_to_oklab` / `oklab_to_rgb`，约30行）。量化结果回存为 sRGB。  
**注意**：`palette.gd` 中的 `DISTANCE_OKLAB` 已支持最近色查找用 OKLab，聚类和查找统一到同一色空间后一致性更好。

---

### P3（低优先级）— 架构改进，影响长期可维护性

#### 5.5 管线步骤链重构

**影响**：提升代码可维护性，为 M2 的锐化/去噪步骤预留扩展点。对用户可见功能无直接变化。  
**工作量**：中。需重构 `pipeline.gd` 的 `apply()` 函数，拆分为步骤对象数组（见章节3.2）。参数字典格式可渐进迁移（先支持命名空间子字典，保持顶层 key 兼容）。  
**推荐时机**：M2 开发前做，否则 M2 增加预处理步骤时仍需手动在 `apply()` 中插入条件分支。

#### 5.6 M2 锐化/去噪预处理步骤

**影响**：对扫描图像或低质量源图有明显改善，减少量化后的噪点。  
**工作量**：中（去噪：3×3中值滤波约30行；锐化：Unsharp Mask 约40行）。  
**推荐实现**：先实现简单版（中值去噪 + 简单锐化），嵌入管线，参数默认关闭（`enabled: false`）。  
**依赖**：建议在5.5完成后实现，以便干净地插入步骤链。

#### 5.7 网格线精修（refine_grids 完整版）

**影响**：改善网格检测精度，减少非整数 scale 情况下的边缘采样误差。  
**工作量**：中。在 `grid_detector.gd` 中为每条网格线做局部梯度峰值搜索（±半格范围），替代当前全局统一偏移。  
**注意**：当前 `_find_offset()` 已是简化版实现，升级为逐线优化可获得更好的精度，但对用户感知的改善依赖源图质量。

---

### 改进项总览

| 优先级 | 改进项 | 影响 | 工作量 | 破坏性 |
|--------|--------|------|--------|--------|
| P1 | 色度抖动 | 高 | 小 | 无（向后兼容） |
| P1 | 边缘感知重采样 | 高 | 小 | 无（新模式） |
| P2 | 补充调色板 | 中 | 小 | 无 |
| P2 | OKLab K-means | 中 | 中 | 低（auto_k 模式结果变化）|
| P3 | 管线步骤链 | 维护性 | 中 | 低（需回归测试）|
| P3 | 锐化/去噪 | 中 | 中 | 无（默认关闭）|
| P3 | 网格线精修 | 低-中 | 中 | 无 |

---

*文档生成时间：2026-06-13。基于 resampler.gd / ditherer.gd / pipeline.gd / grid_detector.gd / palette.gd 的当前实现分析。*
