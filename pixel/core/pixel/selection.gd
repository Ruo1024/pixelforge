class_name PFSelection
extends RefCounted

## 像素级选区模型。
## contract: 03-milestones/M2-matting-slicing.md §M2-2
## 输入输出契约：
## - mask 每个像素 1 字节，1=选中、0=未选中，尺寸始终等于 image_size.x * image_size.y。
## - bbox 缓存只覆盖选中像素；空选区返回 Rect2i()。
## - 所有布尔运算都会返回新 PFSelection，不修改参与运算的原对象，方便 undo/preview 复用。

const ColorSpace := preload("res://core/pixel/color_space.gd")
const ImageMath := preload("res://core/util/image_math.gd")

const DEFAULT_TOLERANCE := 12.0
const ALPHA_THRESHOLD := 0.004
const _DIRS_4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var image_size := Vector2i.ZERO
var mask := PackedByteArray()
var _bbox := Rect2i()
var _bbox_dirty := true
var _selected_count := 0


func _init(size: Vector2i = Vector2i.ZERO) -> void:
	resize(size)


func resize(size: Vector2i) -> void:
	image_size = Vector2i(maxi(0, size.x), maxi(0, size.y))
	mask.resize(image_size.x * image_size.y)
	mask.fill(0)
	_selected_count = 0
	_bbox = Rect2i()
	_bbox_dirty = false


func duplicate_selection() -> PFSelection:
	var copy := PFSelection.new(image_size)
	copy.mask = mask.duplicate()
	copy._selected_count = _selected_count
	copy._bbox = get_bbox()
	copy._bbox_dirty = false
	return copy


func is_empty() -> bool:
	return _selected_count <= 0


func get_selected_count() -> int:
	return _selected_count


func get_bbox() -> Rect2i:
	if _bbox_dirty:
		_rebuild_bbox()
	return _bbox


func contains(x: int, y: int) -> bool:
	if not _is_inside(x, y):
		return false
	return mask[_index(x, y)] != 0


func set_pixel(x: int, y: int, selected: bool) -> void:
	if not _is_inside(x, y):
		return
	var idx := _index(x, y)
	var next_value := 1 if selected else 0
	if mask[idx] == next_value:
		return
	mask[idx] = next_value
	_selected_count += 1 if selected else -1
	_bbox_dirty = true


func clear() -> void:
	mask.fill(0)
	_selected_count = 0
	_bbox = Rect2i()
	_bbox_dirty = false


func union_with(other: PFSelection) -> PFSelection:
	_require_same_size(other)
	var result := PFSelection.new(image_size)
	for i in range(mask.size()):
		if mask[i] != 0 or other.mask[i] != 0:
			result.mask[i] = 1
			result._selected_count += 1
	result._bbox_dirty = true
	return result


func subtract(other: PFSelection) -> PFSelection:
	_require_same_size(other)
	var result := PFSelection.new(image_size)
	for i in range(mask.size()):
		if mask[i] != 0 and other.mask[i] == 0:
			result.mask[i] = 1
			result._selected_count += 1
	result._bbox_dirty = true
	return result


func intersect(other: PFSelection) -> PFSelection:
	_require_same_size(other)
	var result := PFSelection.new(image_size)
	for i in range(mask.size()):
		if mask[i] != 0 and other.mask[i] != 0:
			result.mask[i] = 1
			result._selected_count += 1
	result._bbox_dirty = true
	return result


func extract_image(source: Image) -> Image:
	var rgba := ImageMath.duplicate_rgba8(source)
	var rect := get_bbox()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)

	var output := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
	output.fill(Color.TRANSPARENT)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if contains(x, y):
				output.set_pixel(x - rect.position.x, y - rect.position.y, rgba.get_pixel(x, y))
	return output


func clear_on_image(source: Image) -> Image:
	var output := ImageMath.duplicate_rgba8(source)
	for y in range(image_size.y):
		for x in range(image_size.x):
			if contains(x, y):
				var c := output.get_pixel(x, y)
				output.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	return output


static func from_mask(size: Vector2i, raw_mask: PackedByteArray) -> PFSelection:
	var selection := PFSelection.new(size)
	var limit := mini(selection.mask.size(), raw_mask.size())
	for i in range(limit):
		if raw_mask[i] != 0:
			selection.mask[i] = 1
			selection._selected_count += 1
	selection._bbox_dirty = true
	return selection


static func rectangle(size: Vector2i, rect: Rect2i) -> PFSelection:
	var selection := PFSelection.new(size)
	var bounds := Rect2i(Vector2i.ZERO, size)
	var clipped := rect.intersection(bounds)
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x):
			selection.set_pixel(x, y, true)
	return selection


static func magic_wand(source: Image, start: Vector2i, params: Dictionary = {}) -> PFSelection:
	var image := ImageMath.duplicate_rgba8(source)
	var size := image.get_size()
	var selection := PFSelection.new(size)
	if start.x < 0 or start.y < 0 or start.x >= size.x or start.y >= size.y:
		return selection

	var tolerance := float(params.get("tolerance", DEFAULT_TOLERANCE))
	var contiguous := bool(params.get("contiguous", true))
	var alpha_sensitive := bool(params.get("alpha_sensitive", true))
	var threshold := _tolerance_to_sq_threshold(tolerance)
	var target := image.get_pixel(start.x, start.y)
	if is_zero_approx(threshold) and alpha_sensitive:
		return _magic_wand_exact_rgba(image, start, contiguous)

	var target_lab := ColorSpace.color_to_oklab(target)

	if not contiguous:
		for y in range(size.y):
			for x in range(size.x):
				if _color_matches(
					image.get_pixel(x, y), target, target_lab, threshold, alpha_sensitive
				):
					var selected_idx := y * size.x + x
					selection.mask[selected_idx] = 1
					selection._selected_count += 1
		selection._bbox_dirty = true
		return selection

	var visited := PackedByteArray()
	visited.resize(size.x * size.y)
	visited.fill(0)
	var queue := PackedInt32Array()
	queue.append(start.y * size.x + start.x)
	visited[start.y * size.x + start.x] = 1
	var cursor := 0
	while cursor < queue.size():
		var pos_index := queue[cursor]
		cursor += 1
		var pos := Vector2i(pos_index % size.x, int(pos_index / size.x))
		if not _color_matches(
			image.get_pixel(pos.x, pos.y), target, target_lab, threshold, alpha_sensitive
		):
			continue
		selection.mask[pos_index] = 1
		selection._selected_count += 1
		for delta in _DIRS_4:
			var nx := pos.x + delta.x
			var ny := pos.y + delta.y
			if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y:
				continue
			var idx := ny * size.x + nx
			if visited[idx] != 0:
				continue
			visited[idx] = 1
			queue.append(idx)
	selection._bbox_dirty = true
	return selection


static func _magic_wand_exact_rgba(image: Image, start: Vector2i, contiguous: bool) -> PFSelection:
	var size := image.get_size()
	var selection := PFSelection.new(size)
	var data := image.get_data()
	var target_offset := (start.y * size.x + start.x) * 4
	var target_r := data[target_offset]
	var target_g := data[target_offset + 1]
	var target_b := data[target_offset + 2]
	var target_a := data[target_offset + 3]

	if not contiguous:
		for idx in range(size.x * size.y):
			var offset := idx * 4
			if _rgba_bytes_match(data, offset, target_r, target_g, target_b, target_a):
				selection.mask[idx] = 1
				selection._selected_count += 1
		selection._bbox_dirty = true
		return selection

	var visited := PackedByteArray()
	visited.resize(size.x * size.y)
	visited.fill(0)
	var queue := PackedInt32Array()
	queue.append(start.y * size.x + start.x)
	visited[start.y * size.x + start.x] = 1
	var cursor := 0
	while cursor < queue.size():
		var pos_index := queue[cursor]
		cursor += 1
		var offset := pos_index * 4
		if not _rgba_bytes_match(data, offset, target_r, target_g, target_b, target_a):
			continue
		selection.mask[pos_index] = 1
		selection._selected_count += 1
		var x := pos_index % size.x
		var y := int(pos_index / size.x)
		var left := pos_index - 1
		var right := pos_index + 1
		var up := pos_index - size.x
		var down := pos_index + size.x
		if x > 0 and visited[left] == 0:
			visited[left] = 1
			queue.append(left)
		if x < size.x - 1 and visited[right] == 0:
			visited[right] = 1
			queue.append(right)
		if y > 0 and visited[up] == 0:
			visited[up] = 1
			queue.append(up)
		if y < size.y - 1 and visited[down] == 0:
			visited[down] = 1
			queue.append(down)
	selection._bbox_dirty = true
	return selection


static func _rgba_bytes_match(
	data: PackedByteArray, offset: int, target_r: int, target_g: int, target_b: int, target_a: int
) -> bool:
	return (
		data[offset] == target_r
		and data[offset + 1] == target_g
		and data[offset + 2] == target_b
		and data[offset + 3] == target_a
	)


static func polygon(size: Vector2i, points: Array[Vector2i]) -> PFSelection:
	var selection := PFSelection.new(size)
	if points.size() < 3:
		return selection

	var min_y := points[0].y
	var max_y := points[0].y
	for point in points:
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	min_y = clampi(min_y, 0, size.y - 1)
	max_y = clampi(max_y, 0, size.y - 1)

	# 扫描线填充：对每一行求边交点，成对填充。像素中心使用 y + 0.5，
	# 可避免顶点被相邻两条边重复计算导致的细缝。
	for y in range(min_y, max_y + 1):
		var scan_y := float(y) + 0.5
		var intersections: Array[float] = []
		for i in range(points.size()):
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			if is_equal_approx(float(a.y), float(b.y)):
				continue
			var min_edge_y := minf(float(a.y), float(b.y))
			var max_edge_y := maxf(float(a.y), float(b.y))
			if scan_y < min_edge_y or scan_y >= max_edge_y:
				continue
			var t := (scan_y - float(a.y)) / float(b.y - a.y)
			intersections.append(float(a.x) + t * float(b.x - a.x))
		intersections.sort()
		for i in range(0, intersections.size() - 1, 2):
			var x_start := clampi(int(floor(intersections[i])), 0, size.x - 1)
			var x_end := clampi(int(ceil(intersections[i + 1])) - 1, 0, size.x - 1)
			for x in range(x_start, x_end + 1):
				selection.set_pixel(x, y, true)
	return selection


static func _color_matches(
	color: Color, target: Color, target_lab: Vector3, threshold: float, alpha_sensitive: bool
) -> bool:
	if alpha_sensitive and absf(color.a - target.a) > maxf(0.01, sqrt(threshold)):
		return false
	if color.a < ALPHA_THRESHOLD and target.a < ALPHA_THRESHOLD:
		return true
	var distance := ColorSpace.oklab_distance(ColorSpace.color_to_oklab(color), target_lab)
	return distance <= threshold


static func _tolerance_to_sq_threshold(tolerance: float) -> float:
	var linear := clampf(tolerance, 0.0, 100.0) / 100.0
	return linear * linear * 0.25


func _rebuild_bbox() -> void:
	if _selected_count <= 0:
		_bbox = Rect2i()
		_bbox_dirty = false
		return

	var min_x := image_size.x
	var min_y := image_size.y
	var max_x := -1
	var max_y := -1
	for y in range(image_size.y):
		for x in range(image_size.x):
			if mask[_index(x, y)] == 0:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	_bbox = Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	_bbox_dirty = false


func _require_same_size(other: PFSelection) -> void:
	assert(other != null)
	assert(other.image_size == image_size)


func _is_inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < image_size.x and y < image_size.y


func _index(x: int, y: int) -> int:
	return y * image_size.x + x
