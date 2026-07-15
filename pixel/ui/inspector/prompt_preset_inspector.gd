class_name PFPromptPresetInspector
extends Control

## Right-side editor for one prompt-preset node. The canvas card stays a compact selector.

signal params_commit_requested(graph_id: String, node_id: String, params: Dictionary)

const PromptPresetCardViewScript := preload("res://ui/canvas/prompt_preset_card_view.gd")
const Strings := preload("res://ui/shell/strings.gd")

var _graph_id := ""
var _node_id := ""
var _view: Control = null
var _hint: Label = null


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.name = "PromptPresetInspectorRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_hint = Label.new()
	_hint.name = "PromptPresetInspectorHint"
	_hint.text = Strings.text("STYLE_PROMPT_INSPECTOR_HINT")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)
	_view = PromptPresetCardViewScript.new()
	_view.name = "PromptPresetEditor"
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.preset_commit_requested.connect(_on_preset_committed)
	root.add_child(_view)
	LocalizationService.language_changed.connect(_on_language_changed)


func configure_node(
	graph_id: String, node_id: String, params: Dictionary, intent: String = ""
) -> void:
	_graph_id = graph_id
	_node_id = node_id
	var preset_value: Variant = params.get("preset", {})
	var preset: Dictionary = preset_value if preset_value is Dictionary else {}
	_view.configure(preset)
	if not intent.is_empty():
		_view.call_deferred("begin_action", intent)


func get_editor_view() -> Control:
	return _view


func _on_preset_committed(preset: Dictionary) -> void:
	if _graph_id.is_empty() or _node_id.is_empty():
		return
	params_commit_requested.emit(_graph_id, _node_id, {"preset": preset.duplicate(true)})


func _on_language_changed(_preference: String, _locale: String) -> void:
	_hint.text = Strings.text("STYLE_PROMPT_INSPECTOR_HINT")
