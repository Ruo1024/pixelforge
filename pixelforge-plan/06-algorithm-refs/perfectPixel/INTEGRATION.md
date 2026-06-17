# perfectPixel → PixelForge 整合分析

> 本文档对比 perfectPixel 的算法实现与 PixelForge 当前已有的 `core/pixel/` 模块，
> 明确哪些思路可以直接吸收、哪些差异需要决策、在哪个里程碑引入。

---

## 一、算法对比矩阵

| 环节 | perfectPixel 做法 | PixelForge 当前做法 | 差异与结论 |
|------|-------------------|---------------------|------------|
| **网格检测主路径** | FFT 频谱峰值 | 自相关（autocorrelation） | 两种方法殊途同归，都是检测空间周期性。FFT 更快（O(n log n)），自相关实现更简单且无需 fftshift 等频域处理。**当前 GDScript 实现保留自相关即可**，FFT 在 GDScript 中没有原生实现。 |
| **网格检测备用路径** | Sobel 梯度投影 + 中位数间距 | 无备用路径 | ⚠ **缺口**：当前代码在 `confidence < threshold` 时只返回 `status: "low_confidence"`，没有自动降级。perfectPixel 的梯度备用路径值得补充（M1-2 后续迭代）。 |
| **网格线精修** | Sobel 梯度吸附（`refine_grids`） | **无精修步骤** | ⚠ **重要缺口**：perfectPixel 的精修是其"perfect"的核心——估计网格线在真实边缘上浮动对齐。当前 resampler 直接用 `offset + i * scale` 等距分割，遇到畸变的 AI 图会有格错位。 |
| **采样：中心点** | `sample_center` | `MODE_CENTER` | ✅ 一致 |
| **采样：中位数** | `sample_median` | `MODE_MEDIAN` | ✅ 一致 |
| **采样：众数/主色** | `sample_majority`（k-means k=2） | `_sample_mode`（频率计数 + 最近中心） | 策略相近但实现不同。perfectPixel 用 k-means 聚类（更抗渐变噪声），PixelForge 用精确颜色计数（更快，逻辑更清晰）。**PixelForge 的实现更适合 GDScript，且对已量化图更优；保留现有实现。** |
| **透明度处理** | 无（只处理 RGB） | 独立计票，alpha < 128 透明 | ✅ PixelForge 更完善 |
| **方形修正** | `fix_square`（差 1 行/列时补齐） | 无 | 低优先级，AI 生成图大多非正方形；暂不引入，作为 M1-5 检查器的可选参数 |

---

## 二、最重要的缺口：网格线精修

perfectPixel 与 PixelForge 当前实现最本质的差异在于**精修步骤**的有无。

**问题复现场景**：AI 生成的"像素图"（如 512×512 的 32×32 内容图）实际网格并不等距——AI 生成过程中的模糊/变形导致部分像素块比其他块稍宽或稍窄。

- 当前 PixelForge：`offset + i * scale` 等距切分 → 累积偏差 → 边缘格错位
- perfectPixel：以梯度能量峰值为锚点，每条网格线独立吸附 → 无累积误差

### 精修逻辑（GDScript 伪代码）

```
# 已知：估计 scale，起始锚点从图像中心向两侧扩展
func refine_grid_coords(grad_proj: PackedFloat32Array, scale: float) -> PackedFloat32Array:
    var coords = PackedFloat32Array()
    var search_range = scale * refine_intensity  # 例如 0.25 * scale
    
    # 从中心出发向右/向左各扩展一条网格线
    var x = find_gradient_peak(W / 2, search_range, grad_proj)  # 中心锚点
    while x < W:
        coords.append(x)
        x = find_gradient_peak(x + scale, search_range, grad_proj)
    # 反向同理...
    
    return coords.sorted()

func find_gradient_peak(estimate: float, range: float, grad: PackedFloat32Array) -> float:
    # 在 [estimate - range, estimate + range] 内找梯度最大值位置
    # 若无峰则返回 estimate（不强制吸附）
```

---

## 三、引入阶段建议

### M1-2（当前里程碑）— 补充备用检测路径

**在 `grid_detector.gd` 中增加梯度间距法作为低置信度降级**：

```gdscript
# 在 detect() 末尾，当 confidence < threshold 时
if result.status == "low_confidence":
    var fallback = _estimate_by_gradient_intervals(gray, width, height)
    if fallback > 0:
        # 用 fallback scale 重算 offset 和 confidence
        ...
```

参照 perfectPixel `estimate_grid_gradient`：Sobel 投影 → 找局部峰 → 中位数间距。

---

### M1-3（当前里程碑）— 引入网格线精修（核心改动）

在 `resampler.gd` 中，`resample()` 调用前先做精修，将等距 `x_coords` 替换为精修后的非等距 `x_coords`：

```gdscript
static func resample(source: Image, params: Dictionary = {}) -> Image:
    # ... 现有参数解析 ...
    
    # 新增：用梯度精修网格线坐标
    var x_coords := _refine_grid_coords(image, target_size.x, scale, offset.x, Direction.X)
    var y_coords := _refine_grid_coords(image, target_size.y, scale, offset.y, Direction.Y)
    
    # 后续用 x_coords[i], x_coords[i+1] 替代原来的等距计算
    for y in range(target_size.y):
        for x in range(target_size.x):
            var cell := Rect2i(x_coords[x], y_coords[y], 
                               x_coords[x+1]-x_coords[x], y_coords[y+1]-y_coords[y])
            output.set_pixel(x, y, _sample_cell(image, cell, mode, keep_alpha_gradient))
```

精修函数需要读取梯度列/行投影（复用 `grid_detector.gd` 已有的 `_sobel_magnitude` + `_project_columns/rows`）。

**建议将梯度投影计算提取到 `image_math.gd` 中共用**，避免 resampler 重复计算一次 Sobel。

---

### M1-5（检查器 UI）— 暴露精修参数

在 `PFCleanupParams` 中新增：

```gdscript
{
    ...,
    "refine_intensity": 0.25,   # 精修搜索范围，0 = 禁用精修（等距切分）
    "fix_square": false          # 差 1 行列时自动补齐
}
```

检查器面板可以显示"精修强度"滑块（0–0.5），让用户对比开关效果。

---

## 四、不引入的内容

| perfectPixel 功能 | 不引入原因 |
|-------------------|------------|
| FFT 检测主路径 | GDScript 无原生 FFT，实现代价高；自相关已覆盖同等能力 |
| `sample_majority`（k-means） | OpenCV 依赖；PixelForge 的频率计数在 GDScript 下更快且对已量化图同等有效 |
| `fix_square` 自动补齐 | 低价值；AI 图通常明确非方形，此逻辑反而可能产生意外裁剪 |

---

## 五、行动项

| 优先级 | 行动 | 对应模块 |
|--------|------|----------|
| 🔴 高 | 在 `resampler.gd` 实现网格线精修（吸附到梯度峰） | M1-3 |
| 🟡 中 | 在 `grid_detector.gd` 添加梯度间距备用路径 | M1-2 后续 |
| 🟡 中 | 将 Sobel 投影提取到 `image_math.gd` 共用 | M1-2/3 重构 |
| 🟢 低 | 在检查器暴露 `refine_intensity` 参数 | M1-5 |
