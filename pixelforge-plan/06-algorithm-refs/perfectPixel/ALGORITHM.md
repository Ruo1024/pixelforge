# perfectPixel 算法提炼

> 源码：https://github.com/theamusing/perfectPixel （MIT License）  
> 语言：Python + NumPy/OpenCV  
> 核心文件：`src/perfect_pixel/perfect_pixel.py`

---

## 总体流程

```
输入图像
  ↓
① 检测网格尺寸（grid_w × grid_h）
     主路径：FFT 频谱分析
     备用路径：Sobel 梯度投影
  ↓
② 网格线精修（Sobel 对齐）
  ↓
③ 网格采样 → 缩小图像
     mode="center" / "median" / "majority"
  ↓
④ 方形修正（可选）
  ↓
输出：精确像素图
```

---

## ① 网格尺寸检测

### 主路径：FFT 频谱峰值法（`estimate_grid_fft`）

```
灰度化
  → np.fft.fft2 + fftshift → 取绝对值
  → 对数压缩：1 - log1p(|F|)，归一化到 [0,1]
  → 沿水平/垂直方向带内求和投影（band = W/2 宽度）
  → Gaussian 平滑（σ = k/6, k=17）
  → 检测投影中心两侧的最强峰
     · 判断条件：局部极大值 + 高于 max*35% + peak_width 个点单调
     · 取左/右各最强峰，峰距 / 2 = 该轴像素尺寸
  → grid_w = round(W / pixel_size_x)
```

**特点**：直接分析空间频率，对规则周期性纹理非常鲁棒，但对非均匀或极小网格（<4px）不稳定。

### 备用路径：梯度间距中位数法（`estimate_grid_gradient`）

```
Sobel x + y 梯度
  → 沿列/行方向求和投影
  → 找投影中的局部极大值（阈值 = max * 20%，最小间距 4px）
  → 相邻峰间距的中位数 = 该轴逻辑像素尺寸
  → grid_w = round(W / median_interval_x)
```

### 降级判断逻辑（`detect_grid_scale`）

FFT 结果失效条件：
- 检测失败（返回 None）
- 像素尺寸 < min_size（默认 4px）
- 像素尺寸 > 20px
- x/y 轴尺寸比 > 1.5（即非方形像素）

以上任一条件满足 → 降级到梯度法。

---

## ② 网格线精修（`refine_grids`）

这是 perfectPixel 相比纯等距分割的关键差异点。

```
已知估计网格尺寸（cell_w, cell_h）
  → Sobel 梯度 → 沿列/行求和 → 得到梯度能量曲线 grad_x_sum / grad_y_sum

从图像中心向左右/上下扩展：
  for 每条估计网格线位置 x_estimate:
    在 [x_estimate ± cell_w * refine_intensity] 区间内
    找梯度曲线的局部最强峰
    → 该峰就是精修后的网格线
```

`refine_intensity=0.25` 表示允许网格线在估计位置 ±25% 内浮动，吸附到真实物理边缘。

结果：x_coords / y_coords = 每条网格线的实际像素坐标（不等间距）。

---

## ③ 采样策略

三种策略针对不同噪声场景：

### center（中心点取样）
```
每格中心坐标 (cx, cy) = ((x[i]+x[i+1])//2, (y[j]+y[j+1])//2)
output[j][i] = image[cy][cx]
```
速度最快，对格内颜色均一的图效果好，对有噪声或边缘渗透的格效果差。

### median（通道中位数）
```
取每格所有像素，各通道分别排序取中位数
output[j][i] = (median_R, median_G, median_B)
```
抗孤立噪声点，但对双色格（背景色 + 填充色同格）会产生中间混色。

### majority（多数派 k-means，默认最优）
```
每格像素集（最多采样 128 个）
  → cv2.kmeans(k=2, iters=6)
  → 取成员数更多的聚类的中心
```
本质是：格内如果有两种颜色（内容色 + 背景/噪声色），取"主色"。  
比频率计数的 mode 更平滑（聚类中心而非离散颜色），对 JPEG 压缩/渐变噪声格外有效。

---

## ④ 方形修正（`fix_square`）

当 `|grid_w - grid_h| == 1` 时（即 AI 生成了"几乎是方形"的图但差一行/列），自动补齐：
- 差的那边是奇数 → 裁掉最后一行/列
- 差的那边是偶数 → 复制第一行/列补齐

---

## 关键参数

| 参数 | 默认值 | 含义 |
|------|--------|------|
| `sample_method` | `"center"` | 采样策略（majority 质量最好） |
| `min_size` | `4.0` | 最小逻辑像素尺寸（px），防误检 |
| `peak_width` | `6` | FFT 峰值检测宽度 |
| `refine_intensity` | `0.25` | 网格精修搜索范围（相对 cell 宽度） |
| `fix_square` | `True` | 差 1 行/列时自动补齐 |
| `grid_size` | `None` | 手动指定 (grid_w, grid_h)，跳过检测 |
