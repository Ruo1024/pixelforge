class_name PFColorSpace
extends RefCounted

## 颜色空间与编码工具。
## 职责：集中处理 sRGB/OKLab/rgba32/hex，避免算法模块互相借用私有实现。

const OPAQUE_ALPHA := 255


static func byte_from_unit(value: float) -> int:
	return clampi(int(round(value * 255.0)), 0, 255)


static func color_to_rgba32(color: Color, force_opaque: bool = false) -> int:
	var alpha := OPAQUE_ALPHA if force_opaque else byte_from_unit(color.a)
	return (
		(byte_from_unit(color.r) << 24)
		| (byte_from_unit(color.g) << 16)
		| (byte_from_unit(color.b) << 8)
		| alpha
	)


static func rgba32_to_color(value: int) -> Color:
	return Color8((value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff)


static func color_to_hex(color: Color) -> String:
	return (
		"#%02X%02X%02X"
		% [byte_from_unit(color.r), byte_from_unit(color.g), byte_from_unit(color.b)]
	)


static func hex_to_color(hex_text: String) -> Color:
	var normalized := hex_text.strip_edges().trim_prefix("#")
	if normalized.length() == 3:
		normalized = (
			normalized.substr(0, 1)
			+ normalized.substr(0, 1)
			+ normalized.substr(1, 1)
			+ normalized.substr(1, 1)
			+ normalized.substr(2, 1)
			+ normalized.substr(2, 1)
		)

	var r := normalized.substr(0, 2).hex_to_int()
	var g := normalized.substr(2, 2).hex_to_int()
	var b := normalized.substr(4, 2).hex_to_int()
	var a := OPAQUE_ALPHA
	if normalized.length() >= 8:
		a = normalized.substr(6, 2).hex_to_int()
	return Color8(r, g, b, a)


static func rgb_distance(left: Color, right: Color) -> float:
	var dr := left.r - right.r
	var dg := left.g - right.g
	var db := left.b - right.b
	return dr * dr + dg * dg + db * db


static func color_to_oklab(color: Color) -> Vector3:
	var r := _srgb_to_linear(color.r)
	var g := _srgb_to_linear(color.g)
	var b := _srgb_to_linear(color.b)

	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

	var l_root := pow(maxf(l, 0.0), 1.0 / 3.0)
	var m_root := pow(maxf(m, 0.0), 1.0 / 3.0)
	var s_root := pow(maxf(s, 0.0), 1.0 / 3.0)

	return Vector3(
		0.2104542553 * l_root + 0.7936177850 * m_root - 0.0040720468 * s_root,
		1.9779984951 * l_root - 2.4285922050 * m_root + 0.4505937099 * s_root,
		0.0259040371 * l_root + 0.7827717662 * m_root - 0.8086757660 * s_root
	)


static func oklab_to_color(lab: Vector3, alpha: float = 1.0) -> Color:
	var l_root := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m_root := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s_root := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z

	var l := l_root * l_root * l_root
	var m := m_root * m_root * m_root
	var s := s_root * s_root * s_root

	var r_linear := 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	var g_linear := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	var b_linear := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	return Color(
		_linear_to_srgb(r_linear),
		_linear_to_srgb(g_linear),
		_linear_to_srgb(b_linear),
		clampf(alpha, 0.0, 1.0)
	)


static func oklab_distance(left: Vector3, right: Vector3) -> float:
	var delta := left - right
	return delta.x * delta.x + delta.y * delta.y + delta.z * delta.z


static func _srgb_to_linear(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


static func _linear_to_srgb(value: float) -> float:
	var clamped := maxf(value, 0.0)
	if clamped <= 0.0031308:
		return clampf(clamped * 12.92, 0.0, 1.0)
	return clampf(1.055 * pow(clamped, 1.0 / 2.4) - 0.055, 0.0, 1.0)
