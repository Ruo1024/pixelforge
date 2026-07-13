class_name PFCanvasLODProfile
extends RefCounted

## Semantic canvas LOD thresholds shared by canvas-resident items.

const PROFILE_MAP := "map"
const PROFILE_BROWSE := "browse"
const PROFILE_SUMMARY := "summary"
const PROFILE_EDIT := "edit"
const PROFILE_INSPECT := "inspect"
const BROWSE_MIN_CAMERA_ZOOM := 0.25
const SUMMARY_MIN_CAMERA_ZOOM := 0.5
const EDIT_MIN_CAMERA_ZOOM := 0.75
const INSPECT_MIN_CAMERA_ZOOM := 4.0
const PIXEL_GRID_MIN_PHYSICAL_CELL := 4.0


static func profile_for_camera_zoom(camera_zoom: float) -> String:
	var safe_zoom := maxf(camera_zoom, 0.0)
	if safe_zoom >= INSPECT_MIN_CAMERA_ZOOM:
		return PROFILE_INSPECT
	if safe_zoom >= EDIT_MIN_CAMERA_ZOOM:
		return PROFILE_EDIT
	if safe_zoom >= SUMMARY_MIN_CAMERA_ZOOM:
		return PROFILE_SUMMARY
	if safe_zoom >= BROWSE_MIN_CAMERA_ZOOM:
		return PROFILE_BROWSE
	return PROFILE_MAP


static func should_draw_pixel_grid(camera_zoom: float, local_cell_size: float) -> bool:
	return maxf(camera_zoom, 0.0) * maxf(local_cell_size, 0.0) >= PIXEL_GRID_MIN_PHYSICAL_CELL
