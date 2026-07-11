class_name PFWorkspaceContextInspector
extends PanelContainer

## 工作区右栏宿主：图节点显示核心摘要，素材与批次继续使用既有清洗检查器。

const CleanupInspectorScript := preload("res://ui/inspector/cleanup_inspector.gd")
const Strings := preload("res://ui/shell/strings.gd")
const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")

const PANEL_WIDTH := 420
const CONTENT_GAP := 8

var cleanup_inspector: Control = null

var _title_label: Label = null
var _kind_label: Label = null
var _summary_label: Label = null
var _graph_summary: VBoxContainer = null
var _canvas: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var root := VBoxContainer.new()
	root.name = "ContextRoot"
	root.add_theme_constant_override("separation", CONTENT_GAP)
	add_child(root)

	_title_label = Label.new()
	_title_label.name = "ContextTitle"
	_title_label.text = Strings.INSPECTOR_TITLE
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
	cleanup_inspector.visible = kind in ["sprite", "batch", "multiple"]

	_title_label.text = String(context.get("title", Strings.text("INSPECTOR_TITLE")))
	_kind_label.text = String(context.get("type", Strings.text("INSPECTOR_NO_SELECTION")))
	_summary_label.text = String(context.get("summary", Strings.text("INSPECTOR_SELECT_HINT")))


func show_canvas_selection(canvas: Control) -> void:
	_canvas = canvas
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
		show_context(
			{
				"kind": "batch",
				"title": item.label,
				"type": Strings.text("BATCH_DEFAULT_LABEL"),
				"summary": Strings.text("INSPECTOR_BATCH_SUMMARY_FORMAT") % item.asset_ids.size(),
			}
		)
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


func _on_language_changed(_preference: String, _locale: String) -> void:
	if _canvas == null:
		show_context({})
	else:
		show_canvas_selection(_canvas)
