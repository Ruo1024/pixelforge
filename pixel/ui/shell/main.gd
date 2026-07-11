class_name PFMain
extends Control

## 应用主窗口。
## UI 只负责命令分发和状态展示；项目状态由 ProjectService 管，画布状态由 PFInfiniteCanvas 管。

const Strings := preload("res://ui/shell/strings.gd")
const InfiniteCanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const CleanupInspectorScript := preload("res://ui/inspector/cleanup_inspector.gd")
const TaskScript := preload("res://services/pf_task.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const IdUtil := preload("res://core/util/id_util.gd")
const Log := preload("res://core/util/log_util.gd")
const Pipeline := preload("res://core/pixel/pipeline.gd")
const M2ActionController := preload("res://ui/shell/m2_action_controller.gd")
const M21UiControllerScript := preload("res://ui/shell/m2_1_ui_controller.gd")
const ZoomOverlayControllerScript := preload("res://ui/shell/canvas_zoom_overlay_controller.gd")
const ProjectLifecycleGuardScript := preload("res://ui/shell/project_lifecycle_guard.gd")
const ExportFlowControllerScript := preload("res://ui/shell/export_flow_controller.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const ScaleAudit := preload("res://ui/shell/scale_audit.gd")
const ViewportFillPolicy := preload("res://ui/shell/viewport_fill_policy.gd")
const WindowScalePolicy := preload("res://ui/shell/window_scale_policy.gd")

const DEFAULT_WINDOW_WIDTH := 1440
const DEFAULT_WINDOW_HEIGHT := 900
const MIN_WINDOW_WIDTH := 1080
const MIN_WINDOW_HEIGHT := 560
const WINDOW_SCREEN_MARGIN := 80
const UI_FONT_SIZE := 16
const UI_SMALL_FONT_SIZE := 14
const TOP_BAR_HEIGHT := 48
const BOTTOM_BAR_HEIGHT := 32
const TOOLBAR_BUTTON_WIDTH := 96
const TOOLBAR_BUTTON_HEIGHT := 34
const ZOOM_CONTROL_MARGIN := 12
const FLEXIBLE_WIDTH := 0
const CLEANUP_RESULT_GAP := 8
const PREVIEW_OPACITY := 0.56
const SCALE_MONITOR_INTERVAL_SECONDS := 0.25
const SCALE_RESOLVE_DEBOUNCE_SECONDS := 0.35

var _project_filters := PackedStringArray(["*.pxproj ; PixelForge Project"])
var _interface_scale := 1.0
var _window_pixel_scale := 1.0
var _canvas: Control = null
var _cleanup_inspector: Control = null
var _title_label: Label = null
var _status_label: Label = null
var _cost_label: Label = null
var _save_dialog: FileDialog = null
var _open_dialog: FileDialog = null
var _recovery_dialog: ConfirmationDialog = null
var _pending_recovery_path := ""
var _cleanup_task_id := ""
var _preview_task_id := ""
var _preview_token := 0
var _m2_actions: Variant = null
var _m2_1_ui: Variant = null
var _zoom_overlay: RefCounted = null
var _lifecycle_guard: Node = null
var _export_flow: Node = null
var _live_rescale_enabled := true
var _scale_monitor_elapsed := 0.0
var _rescale_debounce_elapsed := 0.0
var _rescale_pending := false
var _rescale_in_progress := false
var _last_screen_snapshot := {}
var _pending_screen_snapshot := {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var startup_snapshot := InterfaceScalePolicy.read_current_screen_snapshot()
	_interface_scale = _resolve_interface_scale_from_snapshot(startup_snapshot, "startup")
	_live_rescale_enabled = bool(SettingsService.get_setting("ui", "live_rescale", true))
	_apply_window_defaults()
	_apply_viewport_scale_policy()
	_apply_runtime_theme()
	_build_ui()
	ViewportFillPolicy.apply(self, get_viewport_rect())
	_connect_services()
	_last_screen_snapshot = startup_snapshot
	set_process(DisplayServer.get_name() != "headless")
	_update_window_title()
	_m2_1_ui.show_onboarding_if_needed()
	if ScaleAudit.is_requested():
		call_deferred("_log_scale_audit")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _lifecycle_guard == null:
			return
		_lifecycle_guard.request_action(ProjectLifecycleGuardScript.ACTION_QUIT)


func _process(delta: float) -> void:
	ViewportFillPolicy.apply(self, get_viewport_rect())
	_poll_live_rescale(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	if event.is_command_or_control_pressed() and event.keycode == KEY_S:
		_save_current_project()
		get_viewport().set_input_as_handled()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_O:
		_show_open_dialog()
		get_viewport().set_input_as_handled()
	elif event.is_command_or_control_pressed() and event.keycode == KEY_N:
		_create_new_project()
		get_viewport().set_input_as_handled()
	elif _m2_1_ui != null and _m2_1_ui.handle_shortcut(event):
		get_viewport().set_input_as_handled()


func _resolve_interface_scale_from_snapshot(snapshot: Dictionary, reason: String) -> float:
	var configured_scale := float(SettingsService.get_setting("ui", "interface_scale", 0.0))
	var resolution := InterfaceScalePolicy.resolve_from_snapshot(
		snapshot, configured_scale, OS.get_name()
	)
	_window_pixel_scale = float(resolution["window_pixel_scale"])
	# M0 复盘：残留 interface_scale=1.0 会旁路自动检测；仅在 macOS 自动档明显更大时迁回 auto。
	if (
		OS.get_name() == "macOS"
		and is_equal_approx(configured_scale, 1.0)
		and float(resolution["detected_F"]) > configured_scale
	):
		Log.warn(
			"Stale interface_scale=1.0 override on a scaled display; resetting to auto.",
			{"auto_scale": float(resolution["detected_F"])}
		)
		SettingsService.set_setting("ui", "interface_scale", 0.0)
		configured_scale = 0.0
		resolution = InterfaceScalePolicy.resolve_from_snapshot(
			snapshot, configured_scale, OS.get_name()
		)
		_window_pixel_scale = float(resolution["window_pixel_scale"])

	var resolved := float(resolution["resolved"])
	var usable_size := Vector2i(resolution["usable_size"])
	var screen_size := Vector2i(snapshot.get("screen_size", Vector2i.ZERO))
	if bool(resolution["clamped"]):
		(
			Log
			. warn(
				"Interface scale clamped to fit startup screen.",
				{
					"before": float(resolution["before_clamp"]),
					"after": resolved,
					"usable_rect": [usable_size.x, usable_size.y],
				}
			)
		)

	# 决策链日志：mac 缩放问题排查的第一手证据（screen scale / usable rect / 来源）。
	(
		Log
		. info(
			"Interface scale resolved",
			{
				"reason": reason,
				"source": String(resolution["source"]),
				"resolved": resolved,
				"detected_F": float(resolution["detected_F"]),
				"applied_F": resolved,
				"window_pixel_scale": _window_pixel_scale,
				"configured": configured_scale,
				"reported_screen_scale": float(resolution["reported_screen_scale"]),
				"screen_dpi": int(resolution["screen_dpi"]),
				"usable_rect": [usable_size.x, usable_size.y],
				"screen_size": [screen_size.x, screen_size.y],
				"mac_retina_fallback": bool(resolution["mac_retina_fallback"]),
				"current_screen": int(snapshot.get("screen", -1)),
				"os": OS.get_name(),
			}
		)
	)
	return resolved


func _apply_viewport_scale_policy() -> void:
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, _interface_scale)


func _poll_live_rescale(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or not _live_rescale_enabled:
		return

	_scale_monitor_elapsed += delta
	if _scale_monitor_elapsed >= SCALE_MONITOR_INTERVAL_SECONDS:
		_scale_monitor_elapsed = 0.0
		var current_snapshot := InterfaceScalePolicy.read_current_screen_snapshot()
		if InterfaceScalePolicy.screen_scale_snapshot_changed(
			_last_screen_snapshot, current_snapshot
		):
			if InterfaceScalePolicy.screen_scale_snapshot_changed(
				_pending_screen_snapshot, current_snapshot
			):
				_pending_screen_snapshot = current_snapshot
				_rescale_debounce_elapsed = 0.0
			_rescale_pending = true

	if not _rescale_pending:
		return
	_rescale_debounce_elapsed += delta
	if _rescale_debounce_elapsed >= SCALE_RESOLVE_DEBOUNCE_SECONDS:
		_apply_live_rescale(_pending_screen_snapshot)


func _apply_live_rescale(screen_snapshot: Dictionary) -> void:
	if _rescale_in_progress or screen_snapshot.is_empty():
		return
	_rescale_in_progress = true

	var old_snapshot := _last_screen_snapshot.duplicate()
	var old_scale := _interface_scale
	var old_window_pixel_scale := _window_pixel_scale
	_interface_scale = _resolve_interface_scale_from_snapshot(screen_snapshot, "live_rescale")
	_apply_viewport_scale_policy()
	_apply_runtime_theme()
	_apply_window_minimum_size()
	if _canvas != null:
		_canvas.call("_update_layer_transform")
		_canvas.call("_update_item_visibility")

	_last_screen_snapshot = screen_snapshot
	_pending_screen_snapshot = {}
	_rescale_pending = false
	_rescale_debounce_elapsed = 0.0
	_rescale_in_progress = false

	(
		Log
		. info(
			"Interface scale reapplied",
			{
				"from_screen": int(old_snapshot.get("screen", -1)),
				"to_screen": int(screen_snapshot.get("screen", -1)),
				"from_F": old_scale,
				"to_F": _interface_scale,
				"from_window_pixel_scale": old_window_pixel_scale,
				"to_window_pixel_scale": _window_pixel_scale,
				"current_screen": int(screen_snapshot.get("screen", -1)),
			}
		)
	)
	if ScaleAudit.is_requested():
		_log_scale_audit()


func _log_scale_audit() -> void:
	var root_window := get_tree().root
	ScaleAudit.log_scale_audit(
		self,
		_canvas,
		_last_screen_snapshot,
		root_window.content_scale_factor if root_window != null else 1.0,
		_window_pixel_scale
	)


func _apply_runtime_theme() -> void:
	theme = _build_app_theme()


func _build_app_theme() -> Theme:
	var app_theme := Theme.new()
	app_theme.default_font_size = UI_FONT_SIZE

	for type_name in [
		"Button",
		"CheckBox",
		"ConfirmationDialog",
		"FileDialog",
		"ItemList",
		"Label",
		"LineEdit",
		"MenuButton",
		"OptionButton",
		"PopupMenu",
		"TabBar",
		"Tree",
		"Window",
	]:
		app_theme.set_font_size("font_size", type_name, UI_FONT_SIZE)

	app_theme.set_font_size("font_size", "Button", UI_SMALL_FONT_SIZE)
	app_theme.set_font_size("font_size", "PopupMenu", UI_SMALL_FONT_SIZE)
	app_theme.set_constant("h_separation", "HBoxContainer", 8)
	app_theme.set_constant("v_separation", "VBoxContainer", 0)
	return app_theme


func _apply_window_defaults() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return
	Log.info(
		"Window defaults applied",
		WindowScalePolicy.apply_startup_defaults(
			window,
			_interface_scale,
			_window_pixel_scale,
			Vector2i(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT),
			Vector2i(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT),
			WINDOW_SCREEN_MARGIN,
			OS.get_name()
		)
	)


func _apply_window_minimum_size() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return
	WindowScalePolicy.apply_minimum_size(
		window, Vector2i(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT), _interface_scale
	)


func _build_ui() -> void:
	custom_minimum_size = Vector2(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, TOP_BAR_HEIGHT)
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(top_bar)

	_title_label = Label.new()
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	top_bar.add_child(_title_label)

	_add_toolbar_button(top_bar, Strings.ACTION_NEW, _create_new_project)
	_add_toolbar_button(top_bar, Strings.ACTION_OPEN, _show_open_dialog)
	_add_toolbar_button(top_bar, Strings.ACTION_SAVE, _save_current_project)
	_add_toolbar_button(top_bar, Strings.ACTION_SAVE_AS, _show_save_dialog)
	_add_toolbar_button(top_bar, Strings.ACTION_EXPORT_PNG, _export_selected_png)

	var content := HSplitContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)

	_canvas = InfiniteCanvasScript.new()
	_canvas.name = "InfiniteCanvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_canvas)

	_cleanup_inspector = CleanupInspectorScript.new()
	_cleanup_inspector.name = "CleanupInspector"
	_cleanup_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_cleanup_inspector)

	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, BOTTOM_BAR_HEIGHT)
	root.add_child(bottom_bar)

	_status_label = Label.new()
	_status_label.text = Strings.STATUS_READY
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	bottom_bar.add_child(_status_label)
	_cost_label = Label.new()
	_cost_label.name = "CostLabel"
	_cost_label.text = Strings.COST_MONTH_FORMAT % CostService.get_month_total()
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	bottom_bar.add_child(_cost_label)

	_create_file_dialogs()
	_m2_actions = M2ActionController.new()
	_m2_actions.setup(_canvas, _cleanup_inspector, _status_label, self)
	_m2_1_ui = M21UiControllerScript.new()
	_m2_1_ui.name = "M21UiController"
	add_child(_m2_1_ui)
	_m2_1_ui.setup(
		_canvas,
		_cleanup_inspector,
		_status_label,
		_cost_label,
		_m2_actions,
		_create_new_project,
		_show_open_dialog,
		_save_current_project
	)
	_m2_1_ui.export_snapshots_requested.connect(_export_flow.request_export)
	_m2_1_ui.add_file_menu(top_bar)
	_m2_1_ui.add_tool_buttons(top_bar)
	_add_toolbar_button(top_bar, Strings.ACTION_BATCH, _m2_1_ui.batch_selected_sprites)
	_add_toolbar_button(top_bar, Strings.ACTION_MATTE, _m2_1_ui.open_matte_dialog)
	_add_toolbar_button(top_bar, Strings.ACTION_SLICE, _m2_1_ui.open_slice_dialog)
	_add_toolbar_button(top_bar, Strings.ACTION_OUTLINE, _m2_1_ui.open_outline_dialog)
	_zoom_overlay = ZoomOverlayControllerScript.new()
	_zoom_overlay.setup(_canvas, ZOOM_CONTROL_MARGIN)


func _add_toolbar_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(TOOLBAR_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	button.pressed.connect(callback)
	parent.add_child(button)


func _create_file_dialogs() -> void:
	_open_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_open_dialog)
	_open_dialog.title = Strings.DIALOG_OPEN_PROJECT
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = _project_filters
	_open_dialog.file_selected.connect(_open_project_path)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_save_dialog)
	_save_dialog.title = Strings.DIALOG_SAVE_PROJECT
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = _project_filters
	_save_dialog.file_selected.connect(_save_project_path)
	add_child(_save_dialog)

	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.name = "RecoveryDialog"
	_recovery_dialog.title = Strings.DIALOG_RECOVERY
	_recovery_dialog.confirmed.connect(_recover_pending_autosave)
	add_child(_recovery_dialog)

	_lifecycle_guard = ProjectLifecycleGuardScript.new()
	_lifecycle_guard.name = "ProjectLifecycleGuard"
	add_child(_lifecycle_guard)
	_lifecycle_guard.setup(ProjectService)
	_lifecycle_guard.action_ready.connect(_on_lifecycle_action_ready)
	_lifecycle_guard.save_requested.connect(_save_for_pending_lifecycle_action)
	_save_dialog.canceled.connect(_on_save_dialog_canceled)

	_export_flow = ExportFlowControllerScript.new()
	_export_flow.name = "ExportFlowController"
	add_child(_export_flow)
	_export_flow.setup(self, _status_label.get_parent(), _status_label)


func _connect_services() -> void:
	_canvas.canvas_changed.connect(_on_canvas_changed)
	_canvas.selection_changed.connect(_on_canvas_selection_changed)
	_canvas.cleanup_grid_changed.connect(_on_cleanup_grid_changed)
	_canvas.graph_connect_failed.connect(_on_canvas_graph_connect_failed)
	_canvas.graph_status.connect(_on_canvas_graph_status)
	_cleanup_inspector.apply_requested.connect(_apply_cleanup_to_selection)
	_cleanup_inspector.preview_requested.connect(_request_cleanup_preview)
	_cleanup_inspector.cancel_requested.connect(_cancel_cleanup_task)
	_cleanup_inspector.manual_grid_changed.connect(_on_manual_grid_changed)
	_cleanup_inspector.custom_palettes_changed.connect(_on_custom_palettes_changed)
	ProjectService.project_loaded.connect(_on_project_loaded)
	ProjectService.project_saved.connect(_on_project_saved)
	ProjectService.dirty_changed.connect(_on_dirty_changed)
	ProjectService.recovery_available.connect(_on_recovery_available)
	ProjectService.autosave_failed.connect(_on_autosave_failed)
	SettingsService.setting_changed.connect(_on_setting_changed)

	var window := get_window()
	if window != null:
		window.files_dropped.connect(_on_files_dropped)

	var pending_recovery: Array = ProjectService.get_pending_recovery_autosaves()
	if not pending_recovery.is_empty():
		call_deferred("_on_recovery_available", pending_recovery)


func _create_new_project() -> void:
	_lifecycle_guard.request_action(ProjectLifecycleGuardScript.ACTION_NEW)


func _perform_new_project() -> void:
	ProjectService.new_project("Untitled")
	_canvas.clear_canvas()
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _save_current_project() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	if ProjectService.current_project.project_path.is_empty():
		_show_save_dialog()
		return

	var error := ProjectService.save_project()
	if error != OK:
		Log.warn("Project save failed", {"error": error})
		_show_project_save_failed(ProjectService.current_project.project_path, error)


func _save_project_path(path: String) -> void:
	var target_path := path
	if not target_path.ends_with(".pxproj"):
		target_path += ".pxproj"

	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	var error := ProjectService.save_project(target_path)
	if error != OK:
		Log.warn("Project save failed", {"path": target_path, "error": error})
		_show_project_save_failed(target_path, error)
	if _lifecycle_guard.has_pending_action():
		_lifecycle_guard.notify_save_result(error)


func _open_project_path(path: String) -> void:
	_lifecycle_guard.request_action(ProjectLifecycleGuardScript.ACTION_OPEN, path)


func _perform_open_project(path: String) -> void:
	var error := ProjectService.open_project(path)
	if error != OK:
		Log.warn("Project open failed", {"path": path, "error": error})
		_show_project_open_failed(path, error)


func _show_open_dialog() -> void:
	_open_dialog.popup_centered_ratio(0.7)


func _show_save_dialog() -> void:
	var project_name: String = ProjectService.current_project.get_name()
	if not ProjectService.current_project.recovered_from_path.is_empty():
		project_name += "_recovered"
	_save_dialog.current_file = "%s.pxproj" % project_name
	_save_dialog.popup_centered_ratio(0.7)


func _save_for_pending_lifecycle_action() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), false)
	if ProjectService.current_project.project_path.is_empty():
		_show_save_dialog()
		return

	var target_path: String = ProjectService.current_project.project_path
	var error := ProjectService.save_project()
	if error != OK:
		Log.warn(
			"Project save failed before destructive action", {"path": target_path, "error": error}
		)
		_show_project_save_failed(target_path, error)
	_lifecycle_guard.notify_save_result(error)


func _on_save_dialog_canceled() -> void:
	if _lifecycle_guard.has_pending_action():
		_lifecycle_guard.cancel_pending()


func _on_lifecycle_action_ready(action_id: String, payload: Variant) -> void:
	match action_id:
		ProjectLifecycleGuardScript.ACTION_NEW:
			_perform_new_project()
		ProjectLifecycleGuardScript.ACTION_OPEN:
			_perform_open_project(String(payload))
		ProjectLifecycleGuardScript.ACTION_QUIT:
			ProjectService.mark_clean_shutdown()
			get_tree().quit()
		ProjectLifecycleGuardScript.ACTION_RECOVER:
			_perform_recovery(String(payload))


func _on_project_loaded(project: Variant) -> void:
	_canvas.load_canvas_data(project.canvas)
	_sync_cleanup_inspector_with_project(project)
	_status_label.text = Strings.STATUS_READY
	_update_window_title()


func _on_project_saved(_path: String) -> void:
	_status_label.text = Strings.STATUS_SAVED
	_update_window_title()


func _on_dirty_changed(is_dirty: bool) -> void:
	_status_label.text = Strings.STATUS_DIRTY if is_dirty else Strings.STATUS_READY
	_update_window_title()


func _on_custom_palettes_changed() -> void:
	ProjectService.mark_dirty()
	_status_label.text = Strings.STATUS_DIRTY
	_update_window_title()


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section != "ui" or key != "live_rescale":
		return
	_live_rescale_enabled = bool(value)
	if not _live_rescale_enabled:
		_rescale_pending = false
		_pending_screen_snapshot = {}
		_rescale_debounce_elapsed = 0.0


func _sync_cleanup_inspector_with_project(project: Variant) -> void:
	if _cleanup_inspector == null:
		return
	var style_data: Variant = project.manifest.get("style_preset", {})
	var style_preset: Dictionary = style_data if style_data is Dictionary else {}
	_cleanup_inspector.refresh_palette_options()
	_cleanup_inspector.set_style_preset(style_preset)


func _on_canvas_changed() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), true)


func _on_canvas_selection_changed(selected_ids: Array) -> void:
	_cleanup_inspector.set_selection_count(selected_ids.size())
	if selected_ids.size() != 1:
		_canvas.clear_cleanup_preview()
	_cancel_preview_task()
	_sync_manual_grid_overlay()


func _on_canvas_graph_connect_failed(reason: String) -> void:
	_status_label.text = Strings.STATUS_GRAPH_CONNECT_FAILED % reason


func _on_canvas_graph_status(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	match event_type:
		"connect_succeeded":
			_status_label.text = (
				Strings.STATUS_GRAPH_CONNECT_DONE % _graph_edge_status_parts(event.get("edge", {}))
			)
		"edge_selected":
			_status_label.text = (
				Strings.STATUS_GRAPH_EDGE_SELECTED % _graph_edge_status_parts(event.get("edge", {}))
			)
		"edge_deleted":
			_status_label.text = (
				Strings.STATUS_GRAPH_EDGE_DELETED % _graph_edge_status_parts(event.get("edge", {}))
			)
		"nodes_deleted":
			_status_label.text = (
				Strings.STATUS_GRAPH_NODES_DELETED
				% [int(event.get("nodes", 0)), int(event.get("edges", 0))]
			)


func _graph_edge_status_parts(edge: Variant) -> Array:
	if not (edge is Dictionary):
		return ["", "", "", ""]
	var edge_data: Dictionary = edge
	var from_data := _graph_edge_endpoint(edge_data.get("from", []))
	var to_data := _graph_edge_endpoint(edge_data.get("to", []))
	return [String(from_data[0]), String(from_data[1]), String(to_data[0]), String(to_data[1])]


func _graph_edge_endpoint(value: Variant) -> Array:
	var endpoint := ["", ""]
	if not (value is Array):
		return endpoint
	var source: Array = value
	if source.size() >= 1:
		endpoint[0] = String(source[0])
	if source.size() >= 2:
		endpoint[1] = String(source[1])
	return endpoint


func _apply_cleanup_to_selection(params: Dictionary) -> void:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.is_empty():
		_status_label.text = Strings.STATUS_CLEANUP_EMPTY
		return

	var effective_params := _cleanup_params_with_project_style(params)
	var task := TaskScript.new(
		"pixel_cleanup", {"items": snapshots, "params": effective_params}, _cleanup_work
	)
	task.finished.connect(_on_cleanup_finished)
	task.canceled.connect(_on_cleanup_canceled)
	task.failed.connect(_on_cleanup_failed)
	task.progress_reported.connect(_on_cleanup_progress)
	_cleanup_task_id = TaskQueue.submit(task)
	_cleanup_inspector.set_cleanup_running(true)
	_status_label.text = Strings.STATUS_CLEANUP_QUEUED


func _cleanup_work(task_ref: Variant) -> Dictionary:
	var items: Array = task_ref.payload["items"]
	var params: Dictionary = task_ref.payload["params"]
	var results := []
	for index in range(items.size()):
		if task_ref.cancel_requested:
			return {"canceled": true, "items": results}

		var item: Dictionary = items[index]
		var pipeline_result := Pipeline.apply(item["image"], params)
		(
			results
			. append(
				{
					"source_data": item["data"],
					"image": pipeline_result["image"],
					"report": pipeline_result["report"],
					"params": params,
				}
			)
		)
		task_ref.report_progress(float(index + 1) / float(items.size()), "cleanup")
	return {"canceled": false, "items": results}


func _on_cleanup_finished(result: Variant) -> void:
	_cleanup_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_cleanup_inspector.set_selection_count(_canvas.get_selected_ids().size())
	if not (result is Dictionary):
		_status_label.text = Strings.STATUS_TASK_FAILED
		return
	if bool(result.get("canceled", false)):
		_status_label.text = Strings.STATUS_CLEANUP_CANCELED
		return

	var reports := []
	for item_result in result.get("items", []):
		var source_data: Dictionary = item_result["source_data"]
		var output: Image = item_result["image"]
		var source_position_data: Array = source_data.get("position", [0, 0])
		var source_position := Vector2(
			float(source_position_data[0]), float(source_position_data[1])
		)
		var source_width := output.get_width()
		if AssetLibrary.has_asset(String(source_data.get("asset_id", ""))):
			var source_image := AssetLibrary.get_image(String(source_data["asset_id"]))
			if source_image != null:
				source_width = source_image.get_width()

		var parent_asset_id := String(source_data.get("asset_id", ""))
		var asset_id := (
			AssetLibrary
			. register_image(
				output,
				"%s_clean" % parent_asset_id.left(8),
				{
					"origin": "edited",
					"tags": ["cleanup"],
					"provenance":
					{
						"provider": null,
						"model": null,
						"prompt": "",
						"seed": null,
						"parent_asset": parent_asset_id,
						"graph_id": null,
						"created_at": IdUtil.utc_now_iso(),
						"cleanup":
						{
							"source_asset": parent_asset_id,
							"params": _json_safe(item_result.get("params", {})),
							"report": _json_safe(item_result.get("report", {})),
						},
					},
				}
			)
		)
		_canvas.add_sprite_item(
			output, asset_id, source_position + Vector2(source_width + CLEANUP_RESULT_GAP, 0)
		)
		reports.append(item_result["report"])

	if not reports.is_empty():
		_cleanup_inspector.show_report(reports[0])
	_cleanup_inspector.cancel_pending_preview()
	_preview_token += 1
	_cancel_preview_task()
	_canvas.clear_cleanup_preview()
	_status_label.text = Strings.STATUS_CLEANUP_DONE


func _on_cleanup_progress(_task_id: String, ratio: float, _message: String) -> void:
	_status_label.text = (
		Strings.STATUS_TASK_RUNNING_FORMAT % [Strings.TASK_CLEANUP, int(round(ratio * 100.0))]
	)


func _on_cleanup_failed(_error: Dictionary) -> void:
	_cleanup_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_status_label.text = Strings.STATUS_TASK_FAILED


func _on_cleanup_canceled() -> void:
	_cleanup_task_id = ""
	_cleanup_inspector.set_cleanup_running(false)
	_cleanup_inspector.set_selection_count(_canvas.get_selected_ids().size())
	_status_label.text = Strings.STATUS_CLEANUP_CANCELED


func _cancel_cleanup_task() -> void:
	if not _cleanup_task_id.is_empty():
		TaskQueue.cancel(_cleanup_task_id)
		return
	if _m2_actions != null:
		_m2_actions.cancel_current_task()


func _request_cleanup_preview(params: Dictionary) -> void:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.size() != 1:
		_canvas.clear_cleanup_preview()
		return

	var effective_params := _cleanup_params_with_project_style(params)
	_cancel_preview_task()
	_preview_token += 1
	var preview_token := _preview_token
	var task := (
		TaskScript
		. new(
			"pixel_cleanup_preview",
			{
				"item": snapshots[0],
				"params": effective_params,
				"token": preview_token,
			},
			_cleanup_preview_work
		)
	)
	task.finished.connect(_on_cleanup_preview_finished)
	task.canceled.connect(func() -> void: _on_cleanup_preview_canceled(preview_token))
	task.progress_reported.connect(_on_cleanup_preview_progress)
	_preview_task_id = TaskQueue.submit(task)
	_status_label.text = Strings.STATUS_PREVIEW_QUEUED


func _cancel_preview_task() -> void:
	if _preview_task_id.is_empty():
		return
	TaskQueue.cancel(_preview_task_id)
	_preview_task_id = ""


func _cleanup_preview_work(task_ref: Variant) -> Dictionary:
	var item: Dictionary = task_ref.payload["item"]
	var params: Dictionary = task_ref.payload["params"]
	task_ref.report_progress(0.05, "preview")
	var pipeline_result := Pipeline.apply(item["image"], params)
	if task_ref.cancel_requested:
		return {"canceled": true, "token": int(task_ref.payload["token"])}

	var source_image: Image = item["image"]
	var preview_image: Image = pipeline_result["image"]
	var fitted_preview := _fit_preview_to_source(preview_image, source_image.get_size())
	task_ref.report_progress(1.0, "preview")
	return {
		"canceled": false,
		"token": int(task_ref.payload["token"]),
		"item_id": String(item["data"].get("id", "")),
		"image": fitted_preview,
		"report": pipeline_result["report"],
	}


func _on_cleanup_preview_finished(result: Variant) -> void:
	if not (result is Dictionary):
		_preview_task_id = ""
		_status_label.text = Strings.STATUS_TASK_FAILED
		return
	var token := int(result.get("token", -1))
	if token == _preview_token:
		_preview_task_id = ""
	if bool(result.get("canceled", false)) or token != _preview_token:
		return

	_canvas.show_cleanup_preview(
		String(result.get("item_id", "")), result["image"], PREVIEW_OPACITY
	)
	_cleanup_inspector.show_report(result.get("report", {}))
	_status_label.text = Strings.STATUS_PREVIEW_DONE


func _on_cleanup_preview_progress(_task_id: String, ratio: float, _message: String) -> void:
	_status_label.text = Strings.STATUS_PREVIEW_RUNNING_FORMAT % int(round(ratio * 100.0))


func _on_cleanup_preview_canceled(token: int) -> void:
	if token != _preview_token:
		return
	_preview_task_id = ""
	_status_label.text = Strings.STATUS_PREVIEW_CANCELED


func _on_manual_grid_changed(active: bool, scale: float, offset: Vector2) -> void:
	if active:
		_canvas.show_cleanup_grid_overlay(scale, offset)
	else:
		_canvas.hide_cleanup_grid_overlay()


func _on_cleanup_grid_changed(scale: float, offset: Vector2) -> void:
	_cleanup_inspector.set_manual_grid_from_overlay(scale, offset)


func _sync_manual_grid_overlay() -> void:
	var params: Dictionary = _cleanup_inspector.get_params()
	var detect: Dictionary = params.get(Pipeline.STEP_DETECT_GRID, {})
	var active := String(detect.get("mode", Pipeline.DETECT_AUTO)) == Pipeline.DETECT_MANUAL
	_on_manual_grid_changed(
		active, float(detect.get("scale", 4.0)), detect.get("offset", Vector2.ZERO)
	)


static func _fit_preview_to_source(preview: Image, source_size: Vector2i) -> Image:
	var fitted := preview.duplicate()
	if fitted.get_format() != Image.FORMAT_RGBA8:
		fitted.convert(Image.FORMAT_RGBA8)
	if fitted.get_size() != source_size:
		fitted.resize(source_size.x, source_size.y, Image.INTERPOLATE_NEAREST)
	return fitted


func _cleanup_params_with_project_style(params: Dictionary) -> Dictionary:
	var style_data: Variant = ProjectService.current_project.manifest.get("style_preset", {})
	var style_preset: Dictionary = style_data if style_data is Dictionary else {}
	return Pipeline.normalize_params(params, style_preset)


func _export_selected_png() -> void:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.is_empty():
		_show_status_notice(Strings.STATUS_EXPORT_EMPTY)
		return

	var data: Dictionary = snapshots[0]["data"]
	var default_name := (
		"spritesheet" if snapshots.size() > 1 else String(data.get("asset_id", "sprite")).left(8)
	)
	_export_flow.request_export(snapshots, "%s.png" % default_name)


func _on_files_dropped(files: PackedStringArray) -> void:
	if _m2_1_ui == null:
		return
	_m2_1_ui.import_files_at_mouse(files)


func _show_status_notice(message: String) -> void:
	_status_label.text = message
	if DisplayServer.get_name() != "headless":
		OS.alert(message, Strings.DIALOG_NOTICE)


func _show_project_save_failed(path: String, error: Error) -> void:
	_show_status_notice(Strings.STATUS_PROJECT_SAVE_FAILED_FORMAT % [path, error_string(error)])


func _show_project_open_failed(path: String, error: Error) -> void:
	_show_status_notice(Strings.STATUS_PROJECT_OPEN_FAILED_FORMAT % [path, error_string(error)])


func _on_autosave_failed(error: Error, path: String) -> void:
	_show_status_notice(Strings.STATUS_AUTOSAVE_FAILED_FORMAT % [path, error_string(error)])


func _on_recovery_available(autosaves: Array) -> void:
	if autosaves.is_empty():
		return

	_pending_recovery_path = String(autosaves.back())
	_recovery_dialog.dialog_text = Strings.DIALOG_RECOVERY_BODY_FORMAT % _pending_recovery_path
	_recovery_dialog.popup_centered()


func _recover_pending_autosave() -> void:
	if _pending_recovery_path.is_empty():
		return
	_lifecycle_guard.request_action(
		ProjectLifecycleGuardScript.ACTION_RECOVER, _pending_recovery_path
	)


func _perform_recovery(path: String) -> void:
	var error := ProjectService.recover_project(path)
	if error != OK:
		Log.warn("Project recovery failed", {"path": path, "error": error})
		_show_project_open_failed(path, error)
		return
	_pending_recovery_path = ""
	_show_status_notice(Strings.STATUS_RECOVERY_COMPLETE)


func _update_window_title() -> void:
	var dirty_marker := "*" if ProjectService.current_project.dirty else ""
	var project_name: String = ProjectService.current_project.get_name()
	var title := "%s%s - %s" % [dirty_marker, project_name, AppInfo.APP_NAME]
	_title_label.text = "%s  %s" % [AppInfo.APP_NAME, dirty_marker]

	var window := get_window()
	if window != null:
		window.title = title


static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var output := {}
			for key in Dictionary(value).keys():
				output[String(key)] = _json_safe(Dictionary(value)[key])
			return output
		TYPE_ARRAY:
			var output := []
			for item in Array(value):
				output.append(_json_safe(item))
			return output
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_COLOR:
			return Color(value).to_html(true)
		_:
			return value
