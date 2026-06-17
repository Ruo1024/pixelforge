class_name PFOutliner
extends RefCounted

## 描边工具（M2-4）。
## contract: 03-milestones/M2-matting-slicing.md §M2-4
##
## add_outline  — 添加外/内描边（形态学膨胀/腐蚀）；素材尺寸自动 +2（外描边）
## remove_outline — 启发式移除 1px 描边（beta，有损）
##
## 约定：函数均不修改入参，返回新 Image。

const ImageMath := preload("res://core/util/image_math.gd")
const ColorSpace := preload("res://core/pixel/color_space.gd")

const TYPE_OUTER := "outer"  ## 外描边
const TYPE_INNER := "inner"  ## 内描边

const CORNER_CROSS := "cross"  ## 十字核（4-连通）
const CORNER_SQUARE := "square"  ## 方核（8-连通，含角）

## alpha 前景阈值。
## AI 图常带低 alpha 抗锯齿边缘；描边前把它们当透明，避免噪点外壳被继续膨胀。
const ALPHA_THRESHOLD := 0.5


## 添加描边。
## params 键：
##   "type"       : String  — "outer"（默认）/ "inner"
##   "color"      : Color   — 描边颜色（默认 Color.BLACK）；"colored" 时此值被忽略
##   "colored"    : bool    — true = 彩色描边（取相邻内部像素色加深 30%）
##   "corner"     : String  — "cross"（默认）/ "square"
##   "mask"       : PackedByteArray（可选，尺寸=w*h）— selective 模式：仅在 mask==1 处描边
## 返回 Image（外描边时尺寸 = 原始 +2，内描边时尺寸不变）。
static func add_outline(source: Image, params: Dictionary = {}) -> Image:
	var image := _with_binary_alpha(ImageMath.duplicate_rgba8(source))
	var outline_type := String(params.get("type", TYPE_OUTER))
	var base_color: Color = params.get("color", Color.BLACK)
	var colored := bool(params.get("colored", false))
	var corner := String(params.get("corner", CORNER_CROSS))
	var mask: PackedByteArray = params.get("mask", PackedByteArray())

	if outline_type == TYPE_INNER:
		return _add_inner(image, base_color, colored, corner, mask)
	return _add_outer(image, base_color, colored, corner, mask)


## 启发式移除 1px 描边（beta）。
## params 键：
##   "color"     : Color   — 推断时的参考色（若已知）
##   "corner"    : String  — "cross" / "square"
## 返回 Image（尺寸缩小 -2，等于移除外描边后的原始尺寸）。
static func remove_outline(source: Image, params: Dictionary = {}) -> Image:
	var image := _with_binary_alpha(ImageMath.duplicate_rgba8(source))
	var corner := String(params.get("corner", CORNER_CROSS))
	var has_reference_color := params.has("color")
	var reference_color: Color = params.get("color", Color.BLACK)
	return _remove_outer(image, corner, reference_color, has_reference_color)


# ---------------------------------------------------------------------------
# 外描边实现
# ---------------------------------------------------------------------------


static func _add_outer(
	source: Image, base_color: Color, colored: bool, corner: String, sel_mask: PackedByteArray
) -> Image:
	var sw := source.get_width()
	var sh := source.get_height()
	# 输出尺寸 +2（每边各 1px）
	var out_w := sw + 2
	var out_h := sh + 2
	var output := Image.create(out_w, out_h, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)

	# 将原图像素平移 (1,1) 拷贝到输出
	output.blit_rect(source, Rect2i(0, 0, sw, sh), Vector2i(1, 1))

	# 原图 alpha 掩码（在输出坐标系，已偏移 +1,+1）
	var dirs := _get_dirs(corner)

	for oy in range(out_h):
		for ox in range(out_w):
			# 对应原图坐标
			var sx := ox - 1
			var sy := oy - 1
			var in_bounds := sx >= 0 and sy >= 0 and sx < sw and sy < sh
			# 已有前景像素则跳过
			if in_bounds:
				var c := source.get_pixel(sx, sy)
				if c.a >= ALPHA_THRESHOLD:
					continue

			# 检查是否与某个前景像素相邻
			var found := false
			var neighbor_color := Color.TRANSPARENT
			for d in dirs:
				var nx := sx + d.x
				var ny := sy + d.y
				if nx < 0 or ny < 0 or nx >= sw or ny >= sh:
					continue
				var nc := source.get_pixel(nx, ny)
				if nc.a >= ALPHA_THRESHOLD:
					# 检查 selective mask
					if sel_mask.size() == sw * sh and sel_mask[ny * sw + nx] == 0:
						continue
					found = true
					neighbor_color = nc
					break

			if found:
				var stroke := _compute_stroke_color(base_color, colored, neighbor_color)
				output.set_pixel(ox, oy, stroke)

	return output


# ---------------------------------------------------------------------------
# 内描边实现
# ---------------------------------------------------------------------------


static func _add_inner(
	source: Image, base_color: Color, colored: bool, corner: String, sel_mask: PackedByteArray
) -> Image:
	var w := source.get_width()
	var h := source.get_height()
	var output := ImageMath.duplicate_rgba8(source)
	var dirs := _get_dirs(corner)

	for y in range(h):
		for x in range(w):
			var c := source.get_pixel(x, y)
			if c.a < ALPHA_THRESHOLD:
				continue
			# 判断是否是前景边界（4/8 邻域有透明像素）
			var is_border := false
			for d in dirs:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					is_border = true
					break
				if source.get_pixel(nx, ny).a < ALPHA_THRESHOLD:
					is_border = true
					break
			if not is_border:
				continue
			if sel_mask.size() == w * h and sel_mask[y * w + x] == 0:
				continue
			var stroke := _compute_stroke_color(base_color, colored, c)
			output.set_pixel(x, y, stroke)

	return output


# ---------------------------------------------------------------------------
# 移除外描边（腐蚀：收缩前景，返回缩小后的图）
# ---------------------------------------------------------------------------


static func _remove_outer(
	source: Image, corner: String, reference_color: Color, has_reference_color: bool
) -> Image:
	var w := source.get_width()
	var h := source.get_height()
	var dirs := _get_dirs(corner)

	# 找所有前景边界像素（疑似描边）
	var border := PackedByteArray()
	border.resize(w * h)
	border.fill(0)

	for y in range(h):
		for x in range(w):
			var c := source.get_pixel(x, y)
			if c.a < ALPHA_THRESHOLD:
				continue
			# 若有任一邻域透明则视为边界
			for d in dirs:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					if _is_removable_outline_color(c, reference_color, has_reference_color):
						border[y * w + x] = 1
					break
				if source.get_pixel(nx, ny).a < ALPHA_THRESHOLD:
					if _is_removable_outline_color(c, reference_color, has_reference_color):
						border[y * w + x] = 1
					break

	# 输出缩小 2（每边各 -1），对应外描边尺寸逻辑
	# 若图像较小则保持原尺寸
	var out_w := maxi(1, w - 2)
	var out_h := maxi(1, h - 2)
	var output := Image.create(out_w, out_h, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)

	for oy in range(out_h):
		for ox in range(out_w):
			var sx := ox + 1
			var sy := oy + 1
			if border[sy * w + sx] == 1:
				continue  # 剥除描边层
			var c := source.get_pixel(sx, sy)
			output.set_pixel(ox, oy, c)

	return output


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------


## 彩色描边：邻居色在 HSL 空间 L 通道加深 30%。
static func _compute_stroke_color(base: Color, colored: bool, neighbor: Color) -> Color:
	if not colored:
		return base
	var h := neighbor.h
	var s := neighbor.s
	var l := clampf(neighbor.v * 0.7, 0.0, 1.0)  # 用 Value 近似 L，加深 30%
	return Color.from_hsv(h, s, l, 1.0)


## 已知描边色时按 OKLab 近似匹配；未知时只剥离非常暗的外壳，避免把亮色主体边缘误删。
static func _is_removable_outline_color(
	color: Color, reference_color: Color, has_reference_color: bool
) -> bool:
	if color.a < ALPHA_THRESHOLD:
		return false
	if has_reference_color:
		var distance := ColorSpace.oklab_distance(
			ColorSpace.color_to_oklab(color), ColorSpace.color_to_oklab(reference_color)
		)
		return distance <= 0.01
	return color.v <= 0.35 and color.a >= 0.5


static func _get_dirs(corner: String) -> Array[Vector2i]:
	if corner == CORNER_SQUARE:
		return [
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1),
			Vector2i(1, 1),
			Vector2i(-1, 1),
			Vector2i(1, -1),
			Vector2i(-1, -1),
		]
	# 默认 cross（十字核）
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func _with_binary_alpha(source: Image) -> Image:
	var output := ImageMath.duplicate_rgba8(source)
	for y in range(output.get_height()):
		for x in range(output.get_width()):
			var color := output.get_pixel(x, y)
			if color.a < ALPHA_THRESHOLD:
				output.set_pixel(x, y, Color.TRANSPARENT)
			else:
				color.a = 1.0
				output.set_pixel(x, y, color)
	return output
