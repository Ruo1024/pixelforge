class_name PFSegmenter
extends RefCounted

## 连通域切分算法（M2-3）。
## contract: 03-milestones/M2-matting-slicing.md §M2-3
## 8-连通 BFS，alpha > 0 为前景；merge_distance 合并近邻组件；min_area 过滤噪点。
## 输出按 top-left 栅格顺序（先行后列）排序。

const ImageMath := preload("res://core/util/image_math.gd")

## 默认合并距离（px，bbox 间距 ≤ 此值的组件合并）
const DEFAULT_MERGE_DISTANCE := 2
## 默认最小面积过滤（px²，低于此值为噪点）
const DEFAULT_MIN_AREA := 4
## alpha 前景阈值（< 此值视为透明背景）
const ALPHA_THRESHOLD := 0.004
const _DIRS_8: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1),
]


## 主入口。
## params 键：
##   "merge_distance" : int   — 合并距离（默认 2）
##   "min_area"       : int   — 最小面积（默认 4）
## 返回 Array[Dictionary]，每项：
##   "rect"    : Rect2i  — 组件 bbox（在原图坐标）
##   "image"   : Image   — 裁剪后含透明背景的 RGBA8 图（尺寸=rect.size）
##   "pixels"  : int     — 前景像素数
##   "index"   : int     — 0-based 栅格顺序编号
static func segment(source: Image, params: Dictionary = {}) -> Array:
	var image := ImageMath.duplicate_rgba8(source)
	var merge_distance := int(params.get("merge_distance", DEFAULT_MERGE_DISTANCE))
	var min_area := int(params.get("min_area", DEFAULT_MIN_AREA))

	var w := image.get_width()
	var h := image.get_height()

	# --- 1. BFS 8-连通标记 ---
	var label_map := PackedInt32Array()
	label_map.resize(w * h)
	label_map.fill(-1)

	var components: Array = []  # [{pixels: Array[Vector2i], bbox: Rect2i}]

	for y in range(h):
		for x in range(w):
			if label_map[y * w + x] >= 0:
				continue
			var c := image.get_pixel(x, y)
			if c.a < ALPHA_THRESHOLD:
				label_map[y * w + x] = -2  # 背景，不需重访
				continue

			# 新前景种子 → BFS
			var label := components.size()
			var comp_pixels: Array[Vector2i] = []
			var bbox := Rect2i(x, y, 1, 1)

			var queue: Array[Vector2i] = [Vector2i(x, y)]
			label_map[y * w + x] = label
			var qi := 0
			while qi < queue.size():
				var pos := queue[qi]
				qi += 1
				comp_pixels.append(pos)
				bbox = _expanded_bbox(bbox, pos)

				for delta in _DIRS_8:
					var nx := pos.x + delta.x
					var ny := pos.y + delta.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if label_map[ny * w + nx] >= 0 or label_map[ny * w + nx] == -2:
						continue
					var nc := image.get_pixel(nx, ny)
					if nc.a < ALPHA_THRESHOLD:
						label_map[ny * w + nx] = -2
						continue
					label_map[ny * w + nx] = label
					queue.append(Vector2i(nx, ny))

			components.append({"pixels": comp_pixels, "bbox": bbox})

	# --- 2. min_area 过滤 ---
	var filtered: Array = []
	for comp in components:
		if comp["pixels"].size() >= min_area:
			filtered.append(comp)

	# --- 3. merge_distance 合并 ---
	var merged := _merge_by_distance(filtered, merge_distance)

	# --- 4. 按 top-left 栅格排序（先 y 后 x） ---
	merged.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ar: Rect2i = a["bbox"]
			var br: Rect2i = b["bbox"]
			if ar.position.y != br.position.y:
				return ar.position.y < br.position.y
			return ar.position.x < br.position.x
	)

	# --- 5. 裁剪出子图，附编号 ---
	var result: Array = []
	for i in range(merged.size()):
		var comp: Dictionary = merged[i]
		var bbox: Rect2i = comp["bbox"]
		var sub := ImageMath.snapshot_region(image, bbox)
		(
			result
			. append(
				{
					"rect": bbox,
					"image": sub,
					"pixels": comp["pixels"].size(),
					"index": i,
				}
			)
		)

	return result


## 合并 bbox 间距 <= merge_distance 的组件（Union-Find）。
static func _merge_by_distance(components: Array, merge_distance: int) -> Array:
	var n := components.size()
	if n <= 1:
		return components

	# Union-Find
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in range(n):
		parent[i] = i

	for i in range(n):
		for j in range(i + 1, n):
			var bi: Rect2i = components[i]["bbox"]
			var bj: Rect2i = components[j]["bbox"]
			if _bbox_distance(bi, bj) <= merge_distance:
				_union(parent, i, j)

	# 按根分组
	var groups: Dictionary = {}
	for i in range(n):
		var root := _find(parent, i)
		if not groups.has(root):
			groups[root] = []
		groups[root].append(i)

	# 合并像素和 bbox
	var result: Array = []
	for root in groups.keys():
		var indices: Array = groups[root]
		var all_pixels: Array[Vector2i] = []
		var bbox: Rect2i = components[indices[0]]["bbox"]
		for idx in indices:
			all_pixels.append_array(components[idx]["pixels"])
			var other: Rect2i = components[idx]["bbox"]
			bbox = bbox.merge(other)
		result.append({"pixels": all_pixels, "bbox": bbox})

	return result


## 两个 bbox 之间的 Chebyshev 距离（不重叠时的最近边距离）。
static func _bbox_distance(a: Rect2i, b: Rect2i) -> int:
	# 水平方向间距
	var ax1 := a.position.x
	var ax2 := a.position.x + a.size.x - 1
	var bx1 := b.position.x
	var bx2 := b.position.x + b.size.x - 1
	var dx := maxi(0, maxi(ax1 - bx2, bx1 - ax2))

	# 垂直方向间距
	var ay1 := a.position.y
	var ay2 := a.position.y + a.size.y - 1
	var by1 := b.position.y
	var by2 := b.position.y + b.size.y - 1
	var dy := maxi(0, maxi(ay1 - by2, by1 - ay2))

	return maxi(dx, dy)


## 返回展开后的 bbox。Rect2i 是值类型，不能依赖函数内“就地修改”传回调用方。
static func _expanded_bbox(bbox: Rect2i, pos: Vector2i) -> Rect2i:
	var end_x := bbox.position.x + bbox.size.x
	var end_y := bbox.position.y + bbox.size.y
	if pos.x < bbox.position.x:
		bbox.size.x += bbox.position.x - pos.x
		bbox.position.x = pos.x
	elif pos.x >= end_x:
		bbox.size.x = pos.x - bbox.position.x + 1
	if pos.y < bbox.position.y:
		bbox.size.y += bbox.position.y - pos.y
		bbox.position.y = pos.y
	elif pos.y >= end_y:
		bbox.size.y = pos.y - bbox.position.y + 1
	return bbox


static func _find(parent: PackedInt32Array, i: int) -> int:
	if parent[i] != i:
		parent[i] = _find(parent, parent[i])
	return parent[i]


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb
