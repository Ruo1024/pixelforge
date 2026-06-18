class_name PFCanvasLODProfile
extends RefCounted

## Semantic canvas LOD thresholds shared by canvas-resident items.

const PROFILE_OVERVIEW := "overview"
const PROFILE_REVIEW := "review"
const PROFILE_INSPECT := "inspect"
const OVERVIEW_MAX_CAMERA_ZOOM := 0.25
const INSPECT_MIN_CAMERA_ZOOM := 4.0
const PIXEL_GRID_MIN_PHYSICAL_CELL := 4.0


static func profile_for_camera_zoom(camera_zoom: float) -> String:
	var safe_zoom := maxf(camera_zoom, 0.0)
	if safe_zoom <= OVERVIEW_MAX_CAMERA_ZOOM:
		return PROFILE_OVERVIEW
	if safe_zoom >= INSPECT_MIN_CAMERA_ZOOM:
		return PROFILE_INSPECT
	return PROFILE_REVIEW


static func should_draw_pixel_grid(camera_zoom: float, local_cell_size: float) -> bool:
	return maxf(camera_zoom, 0.0) * maxf(local_cell_size, 0.0) >= PIXEL_GRID_MIN_PHYSICAL_CELL
