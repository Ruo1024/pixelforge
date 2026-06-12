class_name PFDitherer
extends RefCounted

## 抖动阈值工具。
## contract: 03-milestones/M1-cleanup-pipeline.md §M1-4；只提供纯函数，量化器负责最近色映射。

const ColorSpace := preload("res://core/pixel/color_space.gd")

const MODE_NONE := "none"
const MODE_BAYER2 := "bayer2"
const MODE_BAYER4 := "bayer4"
const MODE_BAYER8 := "bayer8"
const MODE_ERROR_DIFFUSION := "error_diffusion"
const MODE_CHROMATIC := "chromatic"
const ORDERED_AMPLITUDE := 0.22

const BAYER2 := [
	[0, 2],
	[3, 1],
]
const BAYER4 := [
	[0, 8, 2, 10],
	[12, 4, 14, 6],
	[3, 11, 1, 9],
	[15, 7, 13, 5],
]
const BAYER8 := [
	[0, 32, 8, 40, 2, 34, 10, 42],
	[48, 16, 56, 24, 50, 18, 58, 26],
	[12, 44, 4, 36, 14, 46, 6, 38],
	[60, 28, 52, 20, 62, 30, 54, 22],
	[3, 35, 11, 43, 1, 33, 9, 41],
	[51, 19, 59, 27, 49, 17, 57, 25],
	[15, 47, 7, 39, 13, 45, 5, 37],
	[63, 31, 55, 23, 61, 29, 53, 21],
]


static func ordered_adjust(color: Color, x: int, y: int, mode: String, strength: float) -> Color:
	if mode == MODE_NONE or strength <= 0.0:
		return color

	var threshold := ordered_threshold(x, y, mode)
	var offset := (threshold - 0.5) * clampf(strength, 0.0, 1.0) * ORDERED_AMPLITUDE
	return Color(
		clampf(color.r + offset, 0.0, 1.0),
		clampf(color.g + offset, 0.0, 1.0),
		clampf(color.b + offset, 0.0, 1.0),
		color.a
	)


static func chromatic_adjust(
	color: Color, x: int, y: int, bayer_mode: String, contrast: float, chroma: float, density: float
) -> Color:
	var threshold := ordered_threshold(x, y, bayer_mode)
	if threshold > clampf(density, 0.0, 1.0):
		return color

	var lab := ColorSpace.color_to_oklab(color)
	var l_offset := (threshold - 0.5) * clampf(contrast, 0.0, 1.0) * ORDERED_AMPLITUDE
	var angle := threshold * TAU
	var adjusted := Vector3(
		clampf(lab.x + l_offset, 0.0, 1.0),
		lab.y + clampf(chroma, 0.0, 1.0) * cos(angle),
		lab.z + clampf(chroma, 0.0, 1.0) * sin(angle)
	)
	return ColorSpace.oklab_to_color(adjusted, color.a)


static func ordered_threshold(x: int, y: int, mode: String) -> float:
	var matrix := _matrix_for_mode(mode)
	var size := matrix.size()
	if size == 0:
		return 0.5

	var raw_value := int(matrix[posmod(y, size)][posmod(x, size)])
	return (float(raw_value) + 0.5) / float(size * size)


static func is_ordered(mode: String) -> bool:
	return (
		mode == MODE_BAYER2 or mode == MODE_BAYER4 or mode == MODE_BAYER8 or mode == MODE_CHROMATIC
	)


static func _matrix_for_mode(mode: String) -> Array:
	match mode:
		MODE_BAYER2:
			return BAYER2
		MODE_BAYER4:
			return BAYER4
		MODE_BAYER8:
			return BAYER8
		_:
			return []
