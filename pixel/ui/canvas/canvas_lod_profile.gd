class_name PFCanvasLODProfile
extends RefCounted

## 画布语义 LOD 策略。
## 输入：画布美术缩放倍率；输出：overview / review / inspect 三档显示语义。

const PROFILE_OVERVIEW := "overview"
const PROFILE_REVIEW := "review"
const PROFILE_INSPECT := "inspect"
const OVERVIEW_MAX_ART_SCALE := 0.25
const INSPECT_MIN_ART_SCALE := 4.0
const INSPECT_GRID_MAX_DIMENSION := 64
const INSPECT_GRID_MIN_CELL_SIZE := 4.0


static func profile_for_art_scale(art_scale: float) -> String:
	var safe_scale := maxf(art_scale, 0.0)
	if safe_scale <= OVERVIEW_MAX_ART_SCALE:
		return PROFILE_OVERVIEW
	if safe_scale >= INSPECT_MIN_ART_SCALE:
		return PROFILE_INSPECT
	return PROFILE_REVIEW


static func normalize_profile(lod_profile: String) -> String:
	match lod_profile:
		PROFILE_OVERVIEW, PROFILE_REVIEW, PROFILE_INSPECT:
			return lod_profile
		_:
			return PROFILE_REVIEW


static func should_draw_pixel_grid(
	lod_profile: String, pixel_size: Vector2i, draw_rect: Rect2
) -> bool:
	if normalize_profile(lod_profile) != PROFILE_INSPECT:
		return false
	if pixel_size.x <= 0 or pixel_size.y <= 0:
		return false
	if maxi(pixel_size.x, pixel_size.y) > INSPECT_GRID_MAX_DIMENSION:
		return false
	var cell_size := minf(
		draw_rect.size.x / float(pixel_size.x), draw_rect.size.y / float(pixel_size.y)
	)
	return cell_size >= INSPECT_GRID_MIN_CELL_SIZE
