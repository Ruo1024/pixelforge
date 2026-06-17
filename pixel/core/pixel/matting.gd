class_name PFMatting
extends RefCounted

## 色键抠图算法。
## contract: 03-milestones/M2-matting-slicing.md §M2-1
## 两种策略：flood（默认，BFS 泛洪仅清外部连通区，保留物体内同色高光）；
##            global（全图色键，含物体内部同色区）。
## 容差使用 OKLab 欧氏距离（阈值范围 0–100，内部映射为 [0,1] 的平方距离）。

const ColorSpace := preload("res://core/pixel/color_space.gd")
const ImageMath := preload("res://core/util/image_math.gd")

const MODE_FLOOD := "flood"
const MODE_GLOBAL := "global"

## 默认 OKLab 容差（0–100 用户单位）
const DEFAULT_TOLERANCE := 15.0
## 边缘羽化宽度（像素），0 = 关闭
const DEFAULT_FEATHER := 1
## 非纯色底边界占比阈值
const BOUNDARY_COVERAGE_MIN := 0.6
const _DIRS_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## 主入口。
## params 键：
##   "mode"       : String  — "flood"（默认）/ "global"
##   "tolerance"  : float   — 0–100（默认 15）
##   "feather"    : int     — 羽化像素宽（默认 1，0 关闭）
##   "bg_color"   : Color   — 若给定则跳过推断，直接使用
## 返回 Dictionary：
##   "image"      : Image   — 结果 RGBA8
##   "bg_color"   : Color   — 使用的背景色
##   "is_flat_bg" : bool    — 是否判断为纯色底
##   "mode_used"  : String  — 实际使用的模式
static func matte(source: Image, params: Dictionary = {}) -> Dictionary:
	var image := ImageMath.duplicate_rgba8(source)
	var mode := String(params.get("mode", MODE_FLOOD))
	var tolerance := float(params.get("tolerance", DEFAULT_TOLERANCE))
	var feather := int(params.get("feather", DEFAULT_FEATHER))

	# 背景色推断或使用给定值
	var bg_color: Color
	var is_flat_bg := true
	if params.has("bg_color"):
		bg_color = params["bg_color"]
	else:
		var infer := _infer_background(image)
		bg_color = infer["color"]
		is_flat_bg = infer["is_flat"]

	# 非纯色底时直接返回（不修改图像）
	if not is_flat_bg and not params.has("bg_color"):
		return {
			"image": image,
			"bg_color": bg_color,
			"is_flat_bg": false,
			"mode_used": mode,
			"warning": "non_flat_background",
		}

	var sq_threshold := _tolerance_to_sq_threshold(tolerance)

	match mode:
		MODE_GLOBAL:
			_remove_global(image, bg_color, sq_threshold, feather)
		_:
			_remove_flood(image, bg_color, sq_threshold, feather)

	return {"image": image, "bg_color": bg_color, "is_flat_bg": is_flat_bg, "mode_used": mode}


## 推断背景色：8 个边界采样点各取 3×3 均值，聚类（容差内合并），
## 最大簇为背景色候选，占边界比 < BOUNDARY_COVERAGE_MIN 时报非纯色底。
static func _infer_background(image: Image) -> Dictionary:
	var w := image.get_width()
	var h := image.get_height()
	if w < 2 or h < 2:
		return {"color": Color.WHITE, "is_flat": false}

	# 8 个采样位置
	var positions: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(w / 2, 0),
		Vector2i(w - 1, 0),
		Vector2i(w - 1, h / 2),
		Vector2i(w - 1, h - 1),
		Vector2i(w / 2, h - 1),
		Vector2i(0, h - 1),
		Vector2i(0, h / 2),
	]

	var samples: Array[Color] = []
	for pos in positions:
		samples.append(_sample_3x3_avg(image, pos))

	# 简单聚类：贪心合并（容差 15 固定，仅用于推断阶段）
	var infer_threshold := _tolerance_to_sq_threshold(DEFAULT_TOLERANCE)
	var clusters: Array = []  # [{color, count}]
	for s in samples:
		var s_lab := ColorSpace.color_to_oklab(s)
		var merged := false
		for i in range(clusters.size()):
			var c_lab := ColorSpace.color_to_oklab(clusters[i]["color"])
			if ColorSpace.oklab_distance(s_lab, c_lab) <= infer_threshold:
				# 加权平均更新簇中心
				var old_count: float = float(clusters[i]["count"])
				clusters[i]["color"] = clusters[i]["color"].lerp(s, 1.0 / (old_count + 1.0))
				clusters[i]["count"] += 1
				merged = true
				break
		if not merged:
			clusters.append({"color": s, "count": 1})

	# 找最大簇
	var best_idx := 0
	for i in range(1, clusters.size()):
		if clusters[i]["count"] > clusters[best_idx]["count"]:
			best_idx = i
	var bg: Color = clusters[best_idx]["color"]
	var coverage := _boundary_coverage(image, bg, infer_threshold)

	return {"color": bg, "is_flat": coverage >= BOUNDARY_COVERAGE_MIN}


## 全图色键：所有与背景色（OKLab 距离 <= 阈值）的像素清透明。
static func _remove_global(image: Image, bg: Color, sq_threshold: float, feather: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var bg_lab := ColorSpace.color_to_oklab(bg)

	for y in range(h):
		for x in range(w):
			var c := image.get_pixel(x, y)
			if c.a < 0.004:
				continue
			var dist := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(c), bg_lab)
			if feather > 0 and sq_threshold > 0.0 and dist <= sq_threshold * 4.0:
				# 平滑过渡：在 [0, sq_threshold*4] 范围内线性映射 alpha
				var t := clampf(dist / (sq_threshold * 4.0), 0.0, 1.0)
				var new_alpha := c.a * t
				# 二值化：低于 0.5 直接清零
				if new_alpha < 0.5:
					new_alpha = 0.0
				image.set_pixel(x, y, Color(c.r, c.g, c.b, new_alpha))
			elif dist <= sq_threshold:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))


## BFS 泛洪：只清边界连通的背景区，保留物体内部同色区（如白色高光）。
static func _remove_flood(image: Image, bg: Color, sq_threshold: float, feather: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	var bg_lab := ColorSpace.color_to_oklab(bg)

	# 标记矩阵：0=未访问，1=背景（已访问），2=前景（已访问）
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)

	# 边界种子：四条边上所有与背景色相近的像素
	var queue: Array[Vector2i] = []
	for x in range(w):
		_flood_seed(image, x, 0, bg_lab, sq_threshold, visited, queue, w)
		_flood_seed(image, x, h - 1, bg_lab, sq_threshold, visited, queue, w)
	for y in range(1, h - 1):
		_flood_seed(image, 0, y, bg_lab, sq_threshold, visited, queue, w)
		_flood_seed(image, w - 1, y, bg_lab, sq_threshold, visited, queue, w)

	# BFS
	var idx := 0
	while idx < queue.size():
		var pos := queue[idx]
		idx += 1
		for delta in _DIRS_4:
			var nx := pos.x + delta.x
			var ny := pos.y + delta.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nidx := ny * w + nx
			if visited[nidx] != 0:
				continue
			var nc := image.get_pixel(nx, ny)
			var nd := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(nc), bg_lab)
			if nd <= sq_threshold:
				visited[nidx] = 1
				queue.append(Vector2i(nx, ny))
			else:
				visited[nidx] = 2

	# 应用结果：只清 visited==1 的像素
	if feather > 0:
		_apply_flood_with_feather(image, visited, bg_lab, sq_threshold, w, h)
	else:
		_apply_flood_hard(image, visited, w, h)


static func _flood_seed(
	image: Image,
	x: int,
	y: int,
	bg_lab: Vector3,
	sq_threshold: float,
	visited: PackedByteArray,
	queue: Array,
	w: int
) -> void:
	var vi := y * w + x
	if visited[vi] != 0:
		return
	var c := image.get_pixel(x, y)
	if c.a < 0.004:
		visited[vi] = 1
		return
	var dist := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(c), bg_lab)
	if dist <= sq_threshold:
		visited[vi] = 1
		queue.append(Vector2i(x, y))
	else:
		visited[vi] = 2


static func _apply_flood_hard(image: Image, visited: PackedByteArray, w: int, h: int) -> void:
	for y in range(h):
		for x in range(w):
			if visited[y * w + x] == 1:
				var c := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))


static func _apply_flood_with_feather(
	image: Image, visited: PackedByteArray, bg_lab: Vector3, sq_threshold: float, w: int, h: int
) -> void:
	if sq_threshold <= 0.0:
		_apply_flood_hard(image, visited, w, h)
		return

	# 找边界像素（visited==1 且 4-邻域有 visited==2）
	var border_mask := PackedByteArray()
	border_mask.resize(w * h)
	border_mask.fill(0)
	for y in range(h):
		for x in range(w):
			if visited[y * w + x] != 1:
				continue
			for delta in _DIRS_4:
				var nx := x + delta.x
				var ny := y + delta.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if visited[ny * w + nx] == 2:
					border_mask[y * w + x] = 1
					break

	for y in range(h):
		for x in range(w):
			var vi := y * w + x
			if visited[vi] != 1:
				continue
			var c := image.get_pixel(x, y)
			if border_mask[vi] == 1:
				# 边界处：OKLab 距离决定 alpha
				var dist := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(c), bg_lab)
				var t := clampf(dist / (sq_threshold * 4.0), 0.0, 1.0)
				var new_alpha := c.a * t
				if new_alpha < 0.5:
					new_alpha = 0.0
				image.set_pixel(x, y, Color(c.r, c.g, c.b, new_alpha))
			else:
				image.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))


## 3×3 区域均值采样（边界自动 clamp）。
static func _sample_3x3_avg(image: Image, center: Vector2i) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px := clampi(center.x + dx, 0, w - 1)
			var py := clampi(center.y + dy, 0, h - 1)
			var c := image.get_pixel(px, py)
			r += c.r
			g += c.g
			b += c.b
			count += 1
	var inv := 1.0 / float(count)
	return Color(r * inv, g * inv, b * inv, 1.0)


## 候选背景色在整条图像边界上的覆盖率。只看 8 个采样点会把部分渐变
## 或边缘装饰误判为纯色底；整边统计是 M2 任务卡的实际验收口径。
static func _boundary_coverage(image: Image, bg: Color, sq_threshold: float) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var bg_lab := ColorSpace.color_to_oklab(bg)
	var total := 0
	var matched := 0

	for x in range(w):
		total += 1
		if _matches_background(image.get_pixel(x, 0), bg_lab, sq_threshold):
			matched += 1
		if h > 1:
			total += 1
			if _matches_background(image.get_pixel(x, h - 1), bg_lab, sq_threshold):
				matched += 1

	for y in range(1, h - 1):
		total += 1
		if _matches_background(image.get_pixel(0, y), bg_lab, sq_threshold):
			matched += 1
		if w > 1:
			total += 1
			if _matches_background(image.get_pixel(w - 1, y), bg_lab, sq_threshold):
				matched += 1

	if total <= 0:
		return 0.0
	return float(matched) / float(total)


static func _matches_background(color: Color, bg_lab: Vector3, sq_threshold: float) -> bool:
	if color.a < 0.004:
		return true
	var dist := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(color), bg_lab)
	return dist <= sq_threshold


## 用户单位 (0–100) → OKLab 平方距离阈值。
## OKLab 距离满量程约 1.0（向量长度），100 单位 = 全域，线性映射。
static func _tolerance_to_sq_threshold(tolerance: float) -> float:
	var linear := clampf(tolerance, 0.0, 100.0) / 100.0
	# 乘以 0.25：OKLab 实际颜色空间中直径约 0.5，平方 0.25
	return linear * linear * 0.25
