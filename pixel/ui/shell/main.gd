# gdlint: disable=max-file-lines,max-returns
class_name PFMain
extends Control

const ContractErrorText := preload("res://services/contract_error_text.gd")

const Strings := preload("res://ui/shell/strings.gd")
const InfiniteCanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
const ContextInspectorScript := preload("res://ui/inspector/workspace_context_inspector.gd")
const AppInfo := preload("res://core/util/app_info.gd")
const Log := preload("res://core/util/log_util.gd")
const M2ActionController := preload("res://ui/shell/m2_action_controller.gd")
const M21UiControllerScript := preload("res://ui/shell/m2_1_ui_controller.gd")
const ZoomOverlayControllerScript := preload("res://ui/shell/canvas_zoom_overlay_controller.gd")
const WorkspaceNavigationScript := preload("res://ui/shell/workspace_navigation.gd")
const ResponsiveWorkspaceScript := preload("res://ui/shell/responsive_workspace.gd")
const ResponsiveTopBarScript := preload("res://ui/shell/responsive_top_bar.gd")
const MonoIconButtonScript := preload("res://ui/widgets/mono_icon_button.gd")
const AdaptiveToolbarButtonScript := preload("res://ui/widgets/adaptive_toolbar_button.gd")
const CanvasMinimapControllerScript := preload("res://ui/shell/canvas_minimap_controller.gd")
const WorkspaceStartControllerScript := preload("res://ui/shell/workspace_start_controller.gd")
const CanvasGraphStatusPresenter := preload("res://ui/shell/canvas_graph_status_presenter.gd")
const WorkspaceSettingsControllerScript := preload(
	"res://ui/shell/workspace_settings_controller.gd"
)
const ProjectLifecycleGuardScript := preload("res://ui/shell/project_lifecycle_guard.gd")
const ExportFlowControllerScript := preload("res://ui/shell/export_flow_controller.gd")
const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")
const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const ScaleAudit := preload("res://ui/shell/scale_audit.gd")
const WindowScalePolicy := preload("res://ui/shell/window_scale_policy.gd")

const DEFAULT_WINDOW_WIDTH := 1440
const DEFAULT_WINDOW_HEIGHT := 900
const MIN_WINDOW_WIDTH := 1080
const MIN_WINDOW_HEIGHT := 560
const WINDOW_SCREEN_MARGIN := 64
const UI_FONT_SIZE := 16
const UI_SMALL_FONT_SIZE := 14
const TOP_BAR_HEIGHT := 52
const BOTTOM_BAR_HEIGHT := 32
const TOOLBAR_BUTTON_WIDTH := 96
const COMPACT_BUTTON_WIDTH := 72
const TOOLBAR_BUTTON_HEIGHT := 34
const API_SETTINGS_BUTTON_WIDTH := 96
const API_SETTINGS_COMPACT_WIDTH := 52
const DEVELOPER_MODE_BUTTON_WIDTH := 124
const DEVELOPER_MODE_COMPACT_WIDTH := 68
const ZOOM_CONTROL_MARGIN := 12
const FLEXIBLE_WIDTH := 0

var _project_filters := PackedStringArray(["*.pxproj ; PixelForge Project"])
var _interface_scale := 1.0
var _window_pixel_scale := 1.0
var _canvas: Control = null
var _cleanup_inspector: Control = null
var _context_inspector: Control = null
var _title_label: Label = null
var _status_label: Label = null
var _cost_label: Label = null
var _save_dialog: FileDialog = null
var _open_dialog: FileDialog = null
var _recovery_dialog: ConfirmationDialog = null
var _pending_recovery_path := ""
var _m2_actions: Variant = null
var _m2_1_ui: Variant = null
var _zoom_overlay: RefCounted = null
var _minimap_controller: RefCounted = null
var _workspace_start: Node = null
var _lifecycle_guard: Node = null
var _export_flow: Node = null
var _last_screen_snapshot := {}
var _localized_toolbar_buttons: Array[Button] = []
var _responsive_top_bar: HBoxContainer = null
var _developer_mode_toggle: CheckButton = null


func _ready() -> void:
	get_tree().auto_accept_quit = false
	LocalizationService.language_changed.connect(_refresh_toolbar_text)
	var startup_snapshot := InterfaceScalePolicy.read_current_screen_snapshot()
	_interface_scale = _resolve_interface_scale_from_snapshot(startup_snapshot, "startup")
	_apply_window_defaults()
	_apply_viewport_scale_policy()
	_apply_runtime_theme()
	_build_ui()
	_connect_services()
	_last_screen_snapshot = startup_snapshot
	_update_window_title()
	_m2_1_ui.show_onboarding_if_needed(_recovery_dialog)
	if ScaleAudit.is_requested():
		call_deferred("_log_scale_audit")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _lifecycle_guard == null:
			return
		_lifecycle_guard.request_action(ProjectLifecycleGuardScript.ACTION_QUIT)


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
				"max_screen_scale": float(resolution["max_screen_scale"]),
				"screen_dpi": int(resolution["screen_dpi"]),
				"usable_rect": [usable_size.x, usable_size.y],
				"screen_size": [screen_size.x, screen_size.y],
				"mac_retina_fallback": bool(resolution["mac_retina_fallback"]),
				"current_screen": int(snapshot.get("screen", -1)),
				"display_server": String(resolution["display_server"]),
				"os": OS.get_name(),
			}
		)
	)
	return resolved


func _apply_viewport_scale_policy() -> void:
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, _interface_scale)


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
	return AppTheme.build(UI_FONT_SIZE, UI_SMALL_FONT_SIZE)


func _apply_window_defaults() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() in ["headless", "embedded"]:
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


func _build_ui() -> void:
	custom_minimum_size = Vector2(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top_bar: HBoxContainer = ResponsiveTopBarScript.new()
	_responsive_top_bar = top_bar
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, TOP_BAR_HEIGHT)
	top_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(top_bar)

	var global_actions := HBoxContainer.new()
	global_actions.name = "GlobalActions"
	top_bar.add_child(global_actions)

	_title_label = Label.new()
	_title_label.name = "ProjectTitle"
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.custom_minimum_size.x = 280
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	top_bar.add_child(_title_label)
	top_bar.call("setup_title", _title_label)
	top_bar.connect(
		"layout_mode_changed", func(_mode: String) -> void: _refresh_toolbar_text("", "")
	)

	var history_actions := HBoxContainer.new()
	history_actions.name = "HistoryActions"
	top_bar.add_child(history_actions)
	_add_toolbar_button(history_actions, "ACTION_UNDO", _undo_canvas_action, 44, "undo", "undo")
	_add_toolbar_button(history_actions, "ACTION_REDO", _redo_canvas_action, 44, "redo", "redo")
	var top_bar_spacer := Control.new()
	top_bar_spacer.name = "TopBarSpacer"
	top_bar_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_bar_spacer)

	var canvas_actions := HBoxContainer.new()
	canvas_actions.name = "CanvasActions"
	top_bar.add_child(canvas_actions)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 0)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var left_rail := VBoxContainer.new()
	left_rail.name = "LeftRail"
	left_rail.custom_minimum_size = Vector2(AppTheme.LEFT_RAIL_WIDTH, 0)
	content.add_child(left_rail)
	_add_rail_button(left_rail, "ACTION_ADD_INPUT", _workspace_add_input, "add_input")
	_add_rail_button(
		left_rail, "ACTION_IMPORT_REFERENCE", _workspace_import_reference, "import_reference"
	)
	_add_rail_button(left_rail, "ACTION_LIBRARY", _toggle_library, "library")

	var workspace := ResponsiveWorkspaceScript.new()
	workspace.name = "Workspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(workspace)

	_canvas = InfiniteCanvasScript.new()
	_canvas.name = "InfiniteCanvas"
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(_canvas)

	_context_inspector = ContextInspectorScript.new()
	_context_inspector.name = "ContextInspector"
	_context_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_context_inspector.custom_minimum_size = Vector2(AppTheme.INSPECTOR_MIN_WIDTH, 0)
	_context_inspector.visible = false
	workspace.add_child(_context_inspector)
	_cleanup_inspector = _context_inspector.get_cleanup_inspector()

	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.custom_minimum_size = Vector2(FLEXIBLE_WIDTH, BOTTOM_BAR_HEIGHT)
	root.add_child(bottom_bar)

	_status_label = Label.new()
	_status_label.text = Strings.text("STATUS_READY")
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	bottom_bar.add_child(_status_label)
	_cost_label = Label.new()
	_cost_label.name = "CostLabel"
	_cost_label.text = (
		Strings.text("COST_MONTH_FORMAT")
		% (float(CostService.get_month_total_micro_usd()) / 1000000.0)
	)
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
	_m2_1_ui.recent_project_requested.connect(_open_project_path)
	_workspace_start = WorkspaceStartControllerScript.new()
	_workspace_start.name = "WorkspaceStartController"
	add_child(_workspace_start)
	_workspace_start.setup(
		_canvas,
		_status_label,
		_m2_1_ui.get_node("ImportFlowController"),
		_m2_1_ui.generate_mock_batch,
		_m2_1_ui.add_graph_node_to_selected_graph
	)
	_m2_1_ui.export_snapshots_requested.connect(_export_flow.request_export)
	_m2_1_ui.add_file_menu(global_actions)
	_m2_1_ui.add_tool_buttons(canvas_actions)
	_add_api_toolbar_controls(canvas_actions)
	_add_toolbar_button(
		canvas_actions,
		"ACTION_RUN_SELECTION",
		_m2_1_ui.run_selected_mock_graph,
		76,
		"run_selection"
	)
	_add_toolbar_button(canvas_actions, "ACTION_EXPORT", _export_selected_png, 68, "export")
	_add_toolbar_button(
		canvas_actions, "ACTION_INSPECTOR", _toggle_inspector, 76, "inspector", "inspector"
	)
	var settings_controller := WorkspaceSettingsControllerScript.new()
	settings_controller.name = "WorkspaceSettingsController"
	add_child(settings_controller)
	settings_controller.setup(canvas_actions, "more")
	_responsive_top_bar.call("refresh_layout")
	_zoom_overlay = ZoomOverlayControllerScript.new()
	_zoom_overlay.setup(_canvas, ZOOM_CONTROL_MARGIN)
	_minimap_controller = CanvasMinimapControllerScript.new()
	_minimap_controller.setup(_canvas)
	var workspace_navigation := WorkspaceNavigationScript.new()
	workspace_navigation.setup(_canvas, _minimap_controller.minimap)
	_canvas.add_child(workspace_navigation)


func _add_toolbar_button(
	parent: Control,
	text_key: String,
	callback: Callable,
	button_width: int = TOOLBAR_BUTTON_WIDTH,
	action_id: String = "",
	compact_icon_id: String = ""
) -> void:
	var button: Button
	if compact_icon_id.is_empty():
		button = Button.new()
		button.text = _toolbar_text(text_key)
	else:
		button = AdaptiveToolbarButtonScript.new()
		button.call("setup", text_key, compact_icon_id, button_width, COMPACT_BUTTON_WIDTH)
		_responsive_top_bar.call("register_adaptive_button", button)
	button.custom_minimum_size = Vector2(button_width, TOOLBAR_BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	button.pressed.connect(callback)
	parent.add_child(button)
	button.set_meta("text_key", text_key)
	button.set_meta("adaptive_label", not compact_icon_id.is_empty())
	if not action_id.is_empty():
		button.set_meta("action_id", action_id)
	_localized_toolbar_buttons.append(button)


func _add_rail_button(
	parent: Control, text_key: String, callback: Callable, action_id: String
) -> void:
	var button := MonoIconButtonScript.new()
	button.name = action_id.to_pascal_case()
	button.setup(action_id)
	button.tooltip_text = _toolbar_text(text_key)
	button.custom_minimum_size = Vector2.ONE * AppTheme.RAIL_BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("text_key", text_key)
	button.set_meta("action_id", action_id)
	button.set_meta("icon_only", true)
	button.pressed.connect(callback)
	parent.add_child(button)
	_localized_toolbar_buttons.append(button)


func _add_api_toolbar_controls(parent: Control) -> void:
	var api_settings := Button.new()
	api_settings.name = "ApiSettingsButton"
	api_settings.custom_minimum_size = Vector2(API_SETTINGS_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT)
	api_settings.focus_mode = Control.FOCUS_NONE
	api_settings.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	api_settings.set_meta("text_key", "ACTION_API_SETTINGS")
	api_settings.set_meta("compact_text_key", "ACTION_API_SETTINGS_COMPACT")
	api_settings.set_meta("action_id", "api_settings")
	api_settings.pressed.connect(_open_api_settings)
	parent.add_child(api_settings)
	_responsive_top_bar.call(
		"register_compact_control",
		api_settings,
		float(API_SETTINGS_BUTTON_WIDTH),
		float(API_SETTINGS_COMPACT_WIDTH)
	)
	_localized_toolbar_buttons.append(api_settings)

	_developer_mode_toggle = CheckButton.new()
	_developer_mode_toggle.name = "DeveloperModeToggle"
	_developer_mode_toggle.custom_minimum_size = Vector2(
		DEVELOPER_MODE_BUTTON_WIDTH, TOOLBAR_BUTTON_HEIGHT
	)
	_developer_mode_toggle.focus_mode = Control.FOCUS_NONE
	_developer_mode_toggle.add_theme_font_size_override("font_size", UI_SMALL_FONT_SIZE)
	_developer_mode_toggle.set_meta("text_key", "ACTION_DEVELOPER_MODE")
	_developer_mode_toggle.set_meta("compact_text_key", "ACTION_DEVELOPER_MODE_COMPACT")
	_developer_mode_toggle.set_meta("action_id", "developer_mode")
	_developer_mode_toggle.button_pressed = SettingsService.is_developer_mode_enabled()
	_developer_mode_toggle.toggled.connect(SettingsService.set_developer_mode_enabled)
	SettingsService.developer_mode_changed.connect(_on_developer_mode_changed)
	parent.add_child(_developer_mode_toggle)
	_responsive_top_bar.call(
		"register_compact_control",
		_developer_mode_toggle,
		float(DEVELOPER_MODE_BUTTON_WIDTH),
		float(DEVELOPER_MODE_COMPACT_WIDTH)
	)
	_localized_toolbar_buttons.append(_developer_mode_toggle)
	_refresh_toolbar_text("", "")


func _open_api_settings() -> void:
	var dialog := get_node_or_null("M21UiController/ProviderSettingsDialog")
	if dialog != null:
		dialog.show_settings("openai_image")


func _on_developer_mode_changed(enabled: bool) -> void:
	if _developer_mode_toggle != null:
		_developer_mode_toggle.set_pressed_no_signal(enabled)


func _workspace_add_input() -> void:
	_workspace_start.create_input_workspace()


func _workspace_import_reference() -> void:
	_workspace_start.import_reference()


func _toggle_library() -> void:
	_context_inspector.visible = true
	_context_inspector.project_resource_browser.grab_focus()
	_context_inspector.get_parent().queue_sort()


func _toggle_inspector() -> void:
	_context_inspector.visible = not _context_inspector.visible
	_context_inspector.get_parent().queue_sort()


func _undo_canvas_action() -> void:
	UndoService.undo()


func _redo_canvas_action() -> void:
	UndoService.redo()


func _refresh_toolbar_text(_preference: String, _locale: String) -> void:
	for button in _localized_toolbar_buttons:
		if is_instance_valid(button):
			var text_key := String(button.get_meta("text_key", ""))
			if bool(button.get_meta("icon_only", false)):
				button.tooltip_text = _toolbar_text(text_key)
			elif bool(button.get_meta("adaptive_label", false)):
				button.call("refresh_text")
			else:
				var compact_key := String(button.get_meta("compact_text_key", ""))
				var use_compact: bool = (
					_responsive_top_bar != null
					and String(_responsive_top_bar.call("get_layout_mode")) == "compact"
					and not compact_key.is_empty()
				)
				button.text = _toolbar_text(compact_key if use_compact else text_key)
				button.tooltip_text = _toolbar_text(text_key)
	if _responsive_top_bar != null:
		_responsive_top_bar.call("refresh_layout")
	_recovery_dialog.title = Strings.text("DIALOG_RECOVERY_TITLE")
	_recovery_dialog.ok_button_text = Strings.text("ACTION_RECOVER")
	_recovery_dialog.cancel_button_text = Strings.text("ACTION_CANCEL")
	_cost_label.text = (
		Strings.text("COST_MONTH_FORMAT")
		% (float(CostService.get_month_total_micro_usd()) / 1000000.0)
	)


func _toolbar_text(key: String) -> String:
	match key:
		"ACTION_UNDO":
			return Strings.text("ACTION_UNDO")
		"ACTION_REDO":
			return Strings.text("ACTION_REDO")
		"ACTION_RUN_SELECTION":
			return Strings.text("ACTION_RUN_SELECTION")
		"ACTION_EXPORT":
			return Strings.text("ACTION_EXPORT")
		"ACTION_INSPECTOR":
			return Strings.text("ACTION_INSPECTOR")
		"ACTION_ADD_INPUT":
			return Strings.text("ACTION_ADD_INPUT")
		"ACTION_IMPORT_REFERENCE":
			return Strings.text("ACTION_IMPORT_REFERENCE")
		"ACTION_API_SETTINGS":
			return Strings.text("ACTION_API_SETTINGS")
		"ACTION_API_SETTINGS_COMPACT":
			return Strings.text("ACTION_API_SETTINGS_COMPACT")
		"ACTION_DEVELOPER_MODE":
			return Strings.text("ACTION_DEVELOPER_MODE")
		"ACTION_DEVELOPER_MODE_COMPACT":
			return Strings.text("ACTION_DEVELOPER_MODE_COMPACT")
		_:
			return Strings.text("ACTION_LIBRARY")


func _create_file_dialogs() -> void:
	_open_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_open_dialog)
	_open_dialog.title = Strings.text("DIALOG_OPEN_PROJECT")
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.filters = _project_filters
	_open_dialog.file_selected.connect(_open_project_path)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	DialogScalePolicy.configure_file_dialog(_save_dialog)
	_save_dialog.title = Strings.text("DIALOG_SAVE_PROJECT")
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.filters = _project_filters
	_save_dialog.file_selected.connect(_save_project_path)
	add_child(_save_dialog)

	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.name = "RecoveryDialog"
	_recovery_dialog.title = Strings.text("DIALOG_RECOVERY_TITLE")
	_recovery_dialog.ok_button_text = Strings.text("ACTION_RECOVER")
	_recovery_dialog.cancel_button_text = Strings.text("ACTION_CANCEL")
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
	_canvas.graph_connect_failed.connect(_on_canvas_graph_connect_failed)
	_canvas.graph_status.connect(_on_canvas_graph_status)
	_canvas.graph_node_params_commit_requested.connect(_m2_1_ui.apply_graph_node_params)
	_canvas.graph_node_action_requested.connect(_on_graph_node_action_requested)
	_cleanup_inspector.params_commit_requested.connect(_m2_1_ui.apply_graph_node_params)
	_canvas.batch_run_action_requested.connect(_m2_1_ui._handle_batch_run_action)
	_canvas.batch_face_action_requested.connect(_m2_1_ui.handle_batch_face_action)
	_canvas.project_resource_dropped.connect(_m2_1_ui._handle_project_resource_drop)
	_context_inspector.candidate_action_requested.connect(_m2_1_ui._handle_candidate_action)
	_context_inspector.project_resource_activated.connect(
		func(resource: Dictionary) -> void:
			_m2_1_ui._handle_project_resource_drop(resource, _canvas.get_mouse_world_position())
	)
	ProjectService.project_loaded.connect(_on_project_loaded)
	ProjectService.project_saved.connect(_on_project_saved)
	ProjectService.dirty_changed.connect(_on_dirty_changed)
	ProjectService.recovery_available.connect(_on_recovery_available)
	ProjectService.autosave_failed.connect(_on_autosave_failed)

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
	_status_label.text = Strings.text("STATUS_READY")
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
	_context_inspector.show_context({})
	_sync_cleanup_inspector_with_project(project)
	_status_label.text = Strings.text("STATUS_READY")
	_update_window_title()


func _on_project_saved(_path: String) -> void:
	_status_label.text = Strings.text("STATUS_SAVED")
	_update_window_title()


func _on_dirty_changed(is_dirty: bool) -> void:
	_status_label.text = Strings.text("STATUS_DIRTY") if is_dirty else Strings.text("STATUS_READY")
	_update_window_title()


func _on_custom_palettes_changed() -> void:
	ProjectService.mark_dirty()
	_status_label.text = Strings.text("STATUS_DIRTY")
	_update_window_title()


func _sync_cleanup_inspector_with_project(_project: Variant) -> void:
	if _cleanup_inspector == null:
		return
	_cleanup_inspector.refresh_palette_options()


func _on_canvas_changed() -> void:
	ProjectService.set_canvas_data(_canvas.export_canvas_data(), true)


func _on_canvas_selection_changed(selected_ids: Array) -> void:
	_cleanup_inspector.set_selection_count(selected_ids.size())
	_context_inspector.show_canvas_selection(_canvas)


func _on_canvas_graph_connect_failed(reason: String) -> void:
	_status_label.text = Strings.text("STATUS_GRAPH_CONNECT_FAILED") % reason


func _on_graph_node_action_requested(graph_id: String, node_id: String, action_id: String) -> void:
	if action_id == "open_settings":
		_context_inspector.show_cleanup_node(graph_id, node_id)
		return
	_m2_1_ui.handle_graph_node_action(graph_id, node_id, action_id)


func _on_canvas_graph_status(event: Dictionary) -> void:
	var status_text := CanvasGraphStatusPresenter.text(event)
	if not status_text.is_empty():
		_status_label.text = status_text


func _export_selected_png() -> void:
	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
	if snapshots.is_empty():
		_show_status_notice(Strings.text("STATUS_EXPORT_EMPTY"))
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
		OS.alert(message, Strings.text("DIALOG_NOTICE"))


func _show_project_save_failed(path: String, error: Error) -> void:
	_show_status_notice(
		Strings.text("STATUS_PROJECT_SAVE_FAILED_FORMAT") % [path, error_string(error)]
	)


func _show_project_open_failed(path: String, error: Error) -> void:
	var detail := ContractErrorText.text(
		String(ProjectService.last_load_error.get("code", "")), error_string(error)
	)
	_show_status_notice(Strings.text("STATUS_PROJECT_OPEN_FAILED_FORMAT") % [path, detail])


func _on_autosave_failed(error: Error, path: String) -> void:
	_show_status_notice(Strings.text("STATUS_AUTOSAVE_FAILED_FORMAT") % [path, error_string(error)])


func _on_recovery_available(autosaves: Array) -> void:
	if autosaves.is_empty():
		return

	_pending_recovery_path = String(autosaves.back())
	_recovery_dialog.dialog_text = (
		Strings.text("DIALOG_RECOVERY_BODY_FORMAT") % _pending_recovery_path
	)
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
	_show_status_notice(Strings.text("STATUS_RECOVERY_COMPLETE"))


func _update_window_title() -> void:
	var dirty_marker := "*" if ProjectService.current_project.dirty else ""
	var project_name: String = ProjectService.current_project.get_name()
	var title := "%s%s - %s" % [dirty_marker, project_name, AppInfo.APP_NAME]
	_title_label.text = "%s%s" % [project_name, dirty_marker]
	_title_label.tooltip_text = project_name

	var window := get_window()
	if window != null:
		window.title = title
