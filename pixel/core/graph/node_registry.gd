class_name PFNodeRegistry
extends RefCounted

## 节点类型注册表。
## contract: 02-contracts/GRAPH-SCHEMA.md §7；插件与内置节点共用此入口，后注册不得覆盖已注册类型。

const Log := preload("res://core/util/log_util.gd")
const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
const ImageInputNodeScript := preload("res://core/graph/nodes/image_input_node.gd")
const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
const ReferenceSetNodeScript := preload("res://core/graph/nodes/reference_set_node.gd")
const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
const StylePresetNodeScript := preload("res://core/graph/nodes/style_preset_node.gd")
const TextPromptNodeScript := preload("res://core/graph/nodes/text_prompt_node.gd")

static var _plugin_scripts := {}
var _scripts := {}


func _init(register_builtins: bool = true) -> void:
	if register_builtins:
		register("text_prompt", TextPromptNodeScript)
		register("object_list", ObjectListNodeScript)
		register("style_preset", StylePresetNodeScript)
		register("size_spec", SizeSpecNodeScript)
		register("image_input", ImageInputNodeScript)
		register("reference_set", ReferenceSetNodeScript)
		register("ai_generate", AiGenerateNodeScript)
		register("batch", BatchNodeScript)
	for type_name in _plugin_scripts:
		register(String(type_name), _plugin_scripts[type_name])


static func register_plugin_type(type_name: String, node_script: Script) -> bool:
	if type_name.is_empty() or node_script == null or _plugin_scripts.has(type_name):
		return false
	var node: Variant = node_script.new()
	if not (node is PFNode) or node.get_type() != type_name:
		return false
	_plugin_scripts[type_name] = node_script
	return true


static func unregister_plugin_type(type_name: String) -> bool:
	return _plugin_scripts.erase(type_name)


static func clear_plugin_types() -> void:
	_plugin_scripts.clear()


func register(type_name: String, node_script: Script) -> bool:
	if type_name.is_empty():
		Log.error("Graph node registration failed: empty type")
		return false
	if _scripts.has(type_name):
		Log.error("Graph node registration failed: duplicate type", {"type": type_name})
		return false

	var node: Variant = node_script.new()
	if not (node is PFNode):
		Log.error(
			"Graph node registration failed: script does not extend PFNode", {"type": type_name}
		)
		return false
	if node.get_type() != type_name:
		Log.error(
			"Graph node registration failed: type mismatch",
			{"requested": type_name, "actual": node.get_type()}
		)
		return false

	_scripts[type_name] = node_script
	return true


func create(type_name: String) -> PFNode:
	if not _scripts.has(type_name):
		return null
	return _scripts[type_name].new()


func has_type(type_name: String) -> bool:
	return _scripts.has(type_name)


func list_by_category() -> Dictionary:
	var grouped := {}
	var type_names := _scripts.keys()
	type_names.sort()
	for type_name in type_names:
		var node: PFNode = create(String(type_name))
		var category := node.get_category()
		if not grouped.has(category):
			grouped[category] = []
		grouped[category].append(
			{"type": node.get_type(), "display_name": node.get_display_name(), "category": category}
		)
	return grouped


func get_registered_types() -> Array:
	var type_names := _scripts.keys()
	type_names.sort()
	return type_names
