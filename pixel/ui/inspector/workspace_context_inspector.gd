# gdlint: disable=max-returns
class_name PFWorkspaceContextInspector
extends PanelContainer

## 工作区右栏宿主：图节点显示核心摘要，素材与批次继续使用既有清洗检查器。

signal candidate_action_requested(action_id: String, context: Dictionary)
signal project_resource_activated(resource: Dictionary)

const CleanupInspectorScript := preload("res://ui/inspector/cleanup_inspector.gd")
const Strings := preload("res://ui/shell/strings.gd")
const AppTheme := preload("res://ui/shell/app_theme.gd")
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
const ProjectResourceBrowserScript := preload("res://ui/inspector/project_resource_browser.gd")
const GraphScript := preload("res://core/graph/pf_graph.gd")

const PANEL_WIDTH := 360
const CONTENT_GAP := 8
const GENERATION_SNAPSHOT_KEYS: Array[String] = [
	"provider_id",
	"model_id",
	"mode",
	"target_width",
	"target_height",
	"provider_output_size",
	"actual_width",
	"actual_height",
	"requested_seed",
	"actual_seed",
	"run_id",
	"request_id",
	"source_node_id",
	"source_row_id",
	"prompt_preset_id",
	"prompt_prefix",
	"prompt",
	"reference_asset_ids",
	"reference_content_sha256s",
	"extra",
]
const CANDIDATE_ACTIONS: Array[String] = [
	"copy_prompt", "copy_settings", "rerun", "as_reference", "continue_branch"
]
const SNAPSHOT_FORBIDDEN_KEY_PARTS: Array[String] = [
	"api_key", "authorization", "credential", "header", "password", "response", "secret", "token"
]

var cleanup_inspector: Control = null
var project_resource_browser: Control = null

var _title_label: Label = null
var _kind_label: Label = null
var _summary_label: Label = null
var _graph_summary: VBoxContainer = null
var _candidate_panel: VBoxContainer = null
var _candidate_summary: Label = null
var _candidate_rows := {}
var _candidate_action_buttons := {}
var _candidate_context := {}
var _canvas: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = AppTheme.ELEVATED
	panel_style.border_color = AppTheme.BORDER
	panel_style.border_width_left = 1
	add_theme_stylebox_override("panel", panel_style)

	var root := VBoxContainer.new()
	root.name = "ContextRoot"
	root.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(root)

	_title_label = Label.new()
	_title_label.name = "ContextTitle"
	_title_label.text = Strings.text("INSPECTOR_TITLE")
	root.add_child(_title_label)

	_graph_summary = VBoxContainer.new()
	_graph_summary.name = "GraphSummary"
	_graph_summary.add_theme_constant_override("separation", CONTENT_GAP)
	root.add_child(_graph_summary)

	_kind_label = Label.new()
	_kind_label.name = "NodeType"
	_graph_summary.add_child(_kind_label)

	_summary_label = Label.new()
	_summary_label.name = "NodeSummary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_graph_summary.add_child(_summary_label)

	_build_candidate_panel(root)
	project_resource_browser = ProjectResourceBrowserScript.new()
	project_resource_browser.resource_activated.connect(
		func(resource: Dictionary) -> void: project_resource_activated.emit(resource)
	)
	root.add_child(project_resource_browser)

	cleanup_inspector = CleanupInspectorScript.new()
	cleanup_inspector.name = "CleanupInspector"
	cleanup_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cleanup_inspector)

	show_context({})
	LocalizationService.language_changed.connect(_on_language_changed)


func show_context(context: Dictionary) -> void:
	if _title_label == null:
		return
	var kind := String(context.get("kind", "none"))
	var is_graph_node := kind == "node"
	_graph_summary.visible = is_graph_node or kind == "none"
	cleanup_inspector.visible = kind == "cleanup"
	_candidate_panel.visible = kind == "candidate"

	_title_label.text = String(context.get("title", Strings.text("INSPECTOR_TITLE")))
	_kind_label.text = String(context.get("type", Strings.text("INSPECTOR_NO_SELECTION")))
	_summary_label.text = String(context.get("summary", Strings.text("INSPECTOR_SELECT_HINT")))


func show_canvas_selection(canvas: Control) -> void:
	_set_canvas(canvas)
	var selected_ids: Array = canvas.get_selected_ids()
	if selected_ids.is_empty():
		show_context({})
		return
	if selected_ids.size() > 1:
		show_context(
			{
				"kind": "multiple",
				"title": Strings.text("INSPECTOR_TITLE"),
				"summary": Strings.text("INSPECTOR_MULTIPLE_FORMAT") % selected_ids.size(),
			}
		)
		return
	var item: Node = canvas._items_by_id.get(String(selected_ids[0]), null)
	if item == null:
		show_context({})
	elif item.get_script() == CanvasNodeCardScript and item._node_type == "pixel_cleanup":
		show_cleanup_node(String(item.graph_id), String(item.node_id), item)
	elif item.get_script() == CanvasNodeCardScript:
		show_context(
			{
				"kind": "node",
				"title": item._display_name,
				"type": item._node_type,
				"summary": item._summary,
			}
		)
	elif item.get_script() == CanvasBatchCardScript:
		_show_batch_context(item)
	elif item.get_script() == CanvasItemSpriteScript:
		show_context(_sprite_context(item))
	else:
		show_context({})


func _sprite_context(item: Node) -> Dictionary:
	var meta: Dictionary = AssetLibrary.get_asset_meta(item.asset_id)
	var display_name := String(meta.get("name", String(item.asset_id).left(8)))
	var image_size := Vector2i.ZERO
	if item.source_image != null:
		image_size = item.source_image.get_size()
	return {
		"kind": "sprite",
		"title": display_name,
		"type": Strings.text("INSPECTOR_SPRITE_TYPE"),
		"summary":
		(
			Strings.text("INSPECTOR_SPRITE_SUMMARY_FORMAT")
			% [display_name, image_size.x, image_size.y]
		),
	}


func get_cleanup_inspector() -> Control:
	return cleanup_inspector


func show_cleanup_node(graph_id: String, node_id: String, card: Node = null) -> bool:
	var graph_data := ProjectService.get_graph_data(graph_id)
	if graph_data.is_empty():
		return false
	var graph := GraphScript.from_json(graph_data)
	var node: PFNode = graph.get_node(node_id)
	if node == null or node.get_type() != "pixel_cleanup":
		return false
	show_context(
		{
			"kind": "cleanup",
			"title": Strings.text("CLEANUP_TITLE"),
			"type": "pixel_cleanup",
		}
	)
	var running := false
	if card == null and _canvas != null:
		for candidate in _canvas._items_by_id.values():
			if (
				candidate.get_script() == CanvasNodeCardScript
				and String(candidate.graph_id) == graph_id
				and String(candidate.node_id) == node_id
			):
				card = candidate
				break
	if card != null:
		running = String(card._generation_state()).to_lower() in ["queued", "running", "canceling"]
	cleanup_inspector.configure_node(graph_id, node_id, graph.get_node_params(node_id), running)
	return true


func _build_candidate_panel(root: VBoxContainer) -> void:
	_candidate_panel = VBoxContainer.new()
	_candidate_panel.name = "CandidatePanel"
	_candidate_panel.add_theme_constant_override("separation", CONTENT_GAP)
	root.add_child(_candidate_panel)

	_candidate_summary = Label.new()
	_candidate_summary.name = "CandidateSummary"
	_candidate_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_candidate_panel.add_child(_candidate_summary)

	for field_id in [
		"prompt", "model", "seed", "size", "references", "cost", "created_at", "source"
	]:
		_add_candidate_row(field_id)

	var actions := HFlowContainer.new()
	actions.name = "CandidateActions"
	actions.add_theme_constant_override("h_separation", CONTENT_GAP)
	actions.add_theme_constant_override("v_separation", CONTENT_GAP)
	_candidate_panel.add_child(actions)
	for action_id in CANDIDATE_ACTIONS:
		var button := Button.new()
		button.name = _action_button_name(action_id)
		button.pressed.connect(_on_candidate_action_pressed.bind(action_id))
		actions.add_child(button)
		_candidate_action_buttons[action_id] = button


func _add_candidate_row(field_id: String) -> void:
	var row := VBoxContainer.new()
	row.name = "%sRow" % field_id.to_pascal_case()
	row.add_theme_constant_override("separation", 2)
	_candidate_panel.add_child(row)
	var label := Label.new()
	label.name = "FieldLabel"
	row.add_child(label)
	var value := Label.new()
	value.name = "FieldValue"
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(value)
	_candidate_rows[field_id] = {"row": row, "label": label, "value": value}


func _show_batch_context(item: Node) -> void:
	var selected_asset_ids: Array[String] = item.get_selected_asset_ids()
	if selected_asset_ids.is_empty():
		show_context(
			{
				"kind": "batch",
				"title": item.label,
				"type": Strings.text("BATCH_DEFAULT_LABEL"),
				"summary": Strings.text("INSPECTOR_BATCH_SUMMARY_FORMAT") % item.asset_ids.size(),
			}
		)
		return
	show_context({"kind": "candidate", "title": item.label})
	_candidate_context = {
		"snapshot": _snapshot_for_asset(selected_asset_ids[0]),
		"asset_ids": selected_asset_ids.duplicate(),
		"graph_id": String(item.graph_id),
		"batch_node_id": String(item.node_id),
	}
	if selected_asset_ids.size() > 1:
		_show_multiple_candidates(selected_asset_ids.size())
		return
	var snapshot: Dictionary = _candidate_context["snapshot"]
	_show_single_candidate(snapshot, _created_at_for_asset(selected_asset_ids[0]))


func _show_single_candidate(snapshot: Dictionary, created_at: String) -> void:
	_candidate_summary.text = (
		Strings.text("INSPECTOR_CANDIDATE_DETAILS")
		if not snapshot.is_empty()
		else Strings.text("INSPECTOR_CANDIDATE_DETAILS_UNAVAILABLE")
	)
	_set_candidate_row("prompt", snapshot.get("prompt", ""))
	_set_candidate_row("model", snapshot.get("model_id", ""))
	var seed: Variant = snapshot.get("actual_seed", null)
	if seed == null:
		seed = snapshot.get("requested_seed", null)
	_set_candidate_row("seed", seed)
	var width := int(snapshot.get("actual_width", 0))
	var height := int(snapshot.get("actual_height", 0))
	_set_candidate_row("size", "%d×%d" % [width, height] if width > 0 and height > 0 else "")
	var references: Array = snapshot.get("reference_asset_ids", [])
	_set_candidate_row(
		"references",
		(
			(
				Strings.text("INSPECTOR_CANDIDATE_REFERENCES_FORMAT")
				% [references.size(), ", ".join(references)]
			)
			if not references.is_empty()
			else ""
		),
	)
	_set_candidate_row("cost", "")
	_set_candidate_row("created_at", created_at if not snapshot.is_empty() else "")
	_set_candidate_row("source", snapshot.get("source_node_id", ""))
	_set_action_visibility(false)
	_candidate_action_buttons["copy_prompt"].disabled = (
		String(snapshot.get("prompt", "")).is_empty()
	)
	_candidate_action_buttons["copy_settings"].disabled = snapshot.is_empty()
	_candidate_action_buttons["rerun"].disabled = snapshot.is_empty()
	_candidate_action_buttons["as_reference"].disabled = false
	_candidate_action_buttons["continue_branch"].disabled = snapshot.is_empty()


func _show_multiple_candidates(count: int) -> void:
	_candidate_summary.text = Strings.text("INSPECTOR_CANDIDATE_MULTIPLE_FORMAT") % count
	for field_id in _candidate_rows:
		_candidate_rows[field_id]["row"].visible = false
	_set_action_visibility(true)


func _set_candidate_row(field_id: String, raw_value: Variant) -> void:
	var entry: Dictionary = _candidate_rows[field_id]
	var value := str(raw_value) if raw_value != null else ""
	var visible := not value.is_empty()
	entry["row"].visible = visible
	entry["label"].text = _candidate_field_text(field_id)
	entry["value"].text = value if visible else ""


func _set_action_visibility(multiple: bool) -> void:
	for action_id in CANDIDATE_ACTIONS:
		var button: Button = _candidate_action_buttons[action_id]
		button.text = _candidate_action_text(action_id)
		button.visible = not multiple or action_id in ["as_reference", "continue_branch"]
		button.disabled = false


func _candidate_field_text(field_id: String) -> String:
	match field_id:
		"prompt":
			return Strings.text("INSPECTOR_CANDIDATE_PROMPT")
		"model":
			return Strings.text("INSPECTOR_CANDIDATE_MODEL")
		"seed":
			return Strings.text("INSPECTOR_CANDIDATE_SEED")
		"size":
			return Strings.text("INSPECTOR_CANDIDATE_SIZE")
		"references":
			return Strings.text("INSPECTOR_CANDIDATE_REFERENCES")
		"cost":
			return Strings.text("INSPECTOR_CANDIDATE_COST")
		"created_at":
			return Strings.text("INSPECTOR_CANDIDATE_CREATED_AT")
		_:
			return Strings.text("INSPECTOR_CANDIDATE_SOURCE")


func _candidate_action_text(action_id: String) -> String:
	match action_id:
		"copy_prompt":
			return Strings.text("INSPECTOR_CANDIDATE_ACTION_COPY_PROMPT")
		"copy_settings":
			return Strings.text("INSPECTOR_CANDIDATE_ACTION_COPY_SETTINGS")
		"rerun":
			return Strings.text("INSPECTOR_CANDIDATE_ACTION_RERUN")
		"as_reference":
			return Strings.text("INSPECTOR_CANDIDATE_ACTION_AS_REFERENCE")
		_:
			return Strings.text("INSPECTOR_CANDIDATE_ACTION_CONTINUE_BRANCH")


func _set_canvas(canvas: Control) -> void:
	if _canvas == canvas:
		return
	if _canvas != null and _canvas.canvas_changed.is_connected(_on_canvas_changed):
		_canvas.canvas_changed.disconnect(_on_canvas_changed)
	_canvas = canvas
	if _canvas != null and not _canvas.canvas_changed.is_connected(_on_canvas_changed):
		_canvas.canvas_changed.connect(_on_canvas_changed)


func _on_canvas_changed() -> void:
	if _canvas != null:
		show_canvas_selection(_canvas)


func _on_candidate_action_pressed(action_id: String) -> void:
	candidate_action_requested.emit(action_id, _candidate_context.duplicate(true))


func _safe_generation_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var source: Dictionary = value
	var safe := {}
	for key in GENERATION_SNAPSHOT_KEYS:
		if source.has(key):
			safe[key] = _sanitize_snapshot_value(source[key])
	return safe.duplicate(true)


func _snapshot_for_asset(asset_id: String) -> Dictionary:
	var meta: Dictionary = AssetLibrary.get_asset_meta(asset_id)
	var provenance: Dictionary = meta.get("provenance", {})
	return _safe_generation_snapshot(provenance.get("generation_snapshot", {}))


func _created_at_for_asset(asset_id: String) -> String:
	var meta: Dictionary = AssetLibrary.get_asset_meta(asset_id)
	var provenance: Dictionary = meta.get("provenance", {})
	return String(provenance.get("created_at", ""))


func _sanitize_snapshot_value(value: Variant) -> Variant:
	if value is Dictionary:
		var sanitized := {}
		for raw_key in value:
			var key := String(raw_key)
			var normalized := key.to_lower()
			var forbidden := false
			for forbidden_part in SNAPSHOT_FORBIDDEN_KEY_PARTS:
				if normalized.contains(forbidden_part):
					forbidden = true
					break
			if not forbidden:
				sanitized[key] = _sanitize_snapshot_value(value[raw_key])
		return sanitized
	if value is Array:
		var sanitized_array := []
		for item in value:
			sanitized_array.append(_sanitize_snapshot_value(item))
		return sanitized_array
	return value


func _action_button_name(action_id: String) -> String:
	return "%sButton" % action_id.to_pascal_case()


func _on_language_changed(_preference: String, _locale: String) -> void:
	if _canvas == null:
		show_context({})
	else:
		show_canvas_selection(_canvas)
