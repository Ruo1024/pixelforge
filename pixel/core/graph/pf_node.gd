class_name PFNode
extends RefCounted

## 节点领域基类。
## contract: 02-contracts/GRAPH-SCHEMA.md §3；只描述端口、参数、执行入口，不依赖场景树。

const Log := preload("res://core/util/log_util.gd")

const KIND_INT := "int"
const KIND_FLOAT := "float"
const KIND_BOOL := "bool"
const KIND_TEXT := "text"
const KIND_TEXT_MULTILINE := "text_multiline"
const KIND_ENUM := "enum"
const KIND_PALETTE := "palette"
const KIND_PROVIDER := "provider"
const KIND_SEED := "seed"
const KIND_ASSET_REF := "asset_ref"

var _ghost_type := ""
var _ghost_json := {}


static func create_ghost(type_name: String, source_json: Dictionary) -> PFNode:
	var node := PFNode.new()
	node._ghost_type = type_name
	node._ghost_json = source_json.duplicate(true)
	return node


func get_type() -> String:
	if is_ghost():
		return _ghost_type
	return "base"


func get_display_name() -> String:
	if is_ghost():
		return "Missing: %s" % _ghost_type
	return "Base Node"


func get_category() -> String:
	return "input"


func get_input_ports() -> Array[Dictionary]:
	return []


func get_output_ports() -> Array[Dictionary]:
	return []


func get_param_schema() -> Array[Dictionary]:
	return []


func execute(_inputs: Dictionary, _params: Dictionary, _ctx: Variant) -> Dictionary:
	return {}


func get_execution_policy() -> String:
	return "automatic"


func is_async() -> bool:
	return false


func handles_list() -> bool:
	return false


func is_canvas_resident() -> bool:
	return false


func get_canvas_actions() -> Array[Dictionary]:
	return []


func is_ghost() -> bool:
	return not _ghost_type.is_empty()


func get_ghost_json() -> Dictionary:
	return _ghost_json.duplicate(true)


func get_input_port(port_name: String) -> Dictionary:
	return _find_port(get_input_ports(), port_name)


func get_output_port(port_name: String) -> Dictionary:
	return _find_port(get_output_ports(), port_name)


func validate_params(params: Dictionary) -> Dictionary:
	var validated := params.duplicate(true)
	for entry in get_param_schema():
		var key := String(entry.get("key", ""))
		if key.is_empty():
			continue
		var fallback: Variant = entry.get("default", null)
		var raw_value: Variant = validated.get(key, fallback)
		var value: Variant = _coerce_param_value(raw_value, entry, fallback)
		if not _param_value_matches(raw_value, value):
			Log.warn(
				"Graph node parameter fell back to a safe value",
				{"type": get_type(), "key": key, "value": raw_value, "fallback": value}
			)
		validated[key] = value
	return validated


func _coerce_param_value(value: Variant, schema: Dictionary, fallback: Variant) -> Variant:
	var kind := String(schema.get("kind", ""))
	match kind:
		KIND_INT, KIND_SEED:
			return _clamp_number(int(value), schema, int(fallback) if fallback != null else 0)
		KIND_FLOAT:
			return _clamp_float(float(value), schema, float(fallback) if fallback != null else 0.0)
		KIND_BOOL:
			return bool(value)
		KIND_TEXT, KIND_TEXT_MULTILINE, KIND_PALETTE, KIND_PROVIDER, KIND_ASSET_REF:
			return _coerce_string_param(value, fallback, kind == KIND_ASSET_REF)
		KIND_ENUM:
			return _coerce_enum(String(value), schema, String(fallback))
		_:
			return value


func _coerce_string_param(value: Variant, fallback: Variant, accepts_scalar: bool) -> String:
	if value == null:
		return String(fallback)
	if accepts_scalar:
		return str(value)
	return value if value is String else String(fallback)


func _clamp_number(value: int, schema: Dictionary, fallback: int) -> int:
	var result := value
	if schema.has("min"):
		result = maxi(result, int(schema["min"]))
	if schema.has("max"):
		result = mini(result, int(schema["max"]))
	if schema.has("options") and not schema["options"].has(result):
		result = fallback
	return result


func _clamp_float(value: float, schema: Dictionary, fallback: float) -> float:
	var result := value
	if schema.has("min"):
		result = maxf(result, float(schema["min"]))
	if schema.has("max"):
		result = minf(result, float(schema["max"]))
	if schema.has("options") and not schema["options"].has(result):
		result = fallback
	return result


func _coerce_enum(value: String, schema: Dictionary, fallback: String) -> String:
	var options: Array = schema.get("options", [])
	if options.is_empty() or options.has(value):
		return value
	return fallback


func _find_port(ports: Array[Dictionary], port_name: String) -> Dictionary:
	for port in ports:
		if String(port.get("name", "")) == port_name:
			return port.duplicate(true)
	return {}


func _param_value_matches(left: Variant, right: Variant) -> bool:
	return var_to_str(left) == var_to_str(right)
