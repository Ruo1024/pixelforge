# gdlint: disable=max-returns
class_name PFGenerationCardPolicy
extends RefCounted

## Pure B7-4 generation-card presentation policy. It never writes run or Output state.

const Planner := preload("res://services/generation_request_planner.gd")

const GROUP_IDS := [
	"run_status", "provider", "input_summary", "core_params", "dynamic_params", "footer"
]
const TERMINAL_STATES := ["Complete", "Partial", "Failed", "Canceled"]
const NON_RETRYABLE_PRIORITY := [
	"cancel_failed",
	"auth_failed",
	"quota_exceeded",
	"content_policy",
	"invalid_request",
	"timeout",
	"ambiguous_result",
	"provider_internal",
]


func prompt_preview(snapshot: Dictionary) -> Dictionary:
	var params: Dictionary = snapshot.get("params", {})
	var descriptor: Dictionary = snapshot.get("descriptor", {})
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var prefix := String(snapshot.get("prefix", "")).strip_edges()
	var prompt := String(snapshot.get("prompt", "")).strip_edges()
	var width := int(params.get("target_width", 0))
	var height := int(params.get("target_height", 0))
	var rows := _valid_rows(snapshot.get("rows", []))
	var entries: Array[Dictionary] = []
	if rows.is_empty():
		var single := _final_prompt(prefix, prompt, "", capabilities, width, height)
		if not single.is_empty():
			entries.append(
				{"id": "", "label": "", "count": int(params.get("batch_size", 1)), "prompt": single}
			)
	else:
		for row in rows:
			(
				entries
				. append(
					{
						"id": String(row["id"]),
						"label": String(row["text"]),
						"count": int(row["count"]),
						"prompt":
						_final_prompt(
							prefix, prompt, String(row["text"]), capabilities, width, height
						),
					}
				)
			)
	var total := 0
	for entry in entries:
		total += int(entry["count"])
	return {
		"first": String(entries[0]["prompt"]) if not entries.is_empty() else "",
		"entries": entries,
		"row_count": rows.size(),
		"total_count": total,
		"uses_rows": not rows.is_empty(),
	}


func visible_dynamic_params(snapshot: Dictionary) -> Dictionary:
	var descriptor: Dictionary = snapshot.get("descriptor", {})
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	var mode := "img2img" if int(snapshot.get("reference_count", 0)) > 0 else "txt2img"
	var basic: Array[Dictionary] = []
	var advanced: Array[Dictionary] = []
	for value in descriptor.get("dynamic_params", []):
		if not (value is Dictionary):
			continue
		var spec: Dictionary = value
		if spec.has("visible_when") and String(spec["visible_when"].get("mode", "")) != mode:
			continue
		if bool(spec.get("advanced", false)):
			advanced.append(spec.duplicate(true))
		else:
			basic.append(spec.duplicate(true))
	return {
		"basic": basic,
		"advanced": advanced,
		"show_seed": bool(capabilities.get("seed", false)),
	}


func footer_action(context: Dictionary) -> Dictionary:
	var state := String(context.get("state", "Ready"))
	if state == "Ready":
		return _action("generate", "GEN_CARD_ACTION_GENERATE", "preflight_new_output")
	if state in ["Queued", "Running"]:
		return _action("cancel", "GEN_CARD_ACTION_CANCEL", "cancel")
	if state == "Canceling":
		return _action("", "GEN_CARD_ACTION_CANCELING", "none", true)
	if state in ["Complete", "Canceled"]:
		return _action("regenerate", "GEN_CARD_ACTION_REGENERATE", "preflight_new_output")

	var errors: Array = context.get("errors", [])
	if _has_code(errors, "cancel_failed"):
		return _action("cancel_failed", "GEN_CARD_ACTION_CANCEL_FAILED", "none", true)
	var retry_wait := _retry_wait_seconds(errors)
	if retry_wait > 0:
		return _action("retry_wait", "GEN_CARD_ACTION_RETRY_WAIT", "none", true, [retry_wait])
	if _has_available_retry(errors):
		return _action(
			"retry_failed", "GEN_CARD_ACTION_RETRY_FAILED", "preflight_retry_same_output"
		)
	var highest := _highest_non_retryable(errors)
	match highest:
		"auth_failed", "quota_exceeded":
			return _action(
				"provider_settings", "GEN_CARD_ACTION_PROVIDER_SETTINGS", "provider_settings"
			)
		"content_policy":
			return _action("edit_prompt", "GEN_CARD_ACTION_EDIT_PROMPT", "focus_prompt")
		"invalid_request":
			return _action(
				"focus_generation", "GEN_CARD_ACTION_RETURN_GENERATION", "focus_generation"
			)
		"timeout", "ambiguous_result":
			return _action(
				"regenerate_confirm", "GEN_CARD_ACTION_REGENERATE_CONFIRM", "preflight_new_output"
			)
		_:
			return _action("regenerate", "GEN_CARD_ACTION_REGENERATE", "preflight_new_output")


func provider_output_size(snapshot: Dictionary) -> Vector2i:
	var params: Dictionary = snapshot.get("params", {})
	var descriptor: Dictionary = snapshot.get("descriptor", {})
	var capabilities: Dictionary = descriptor.get("capabilities", {})
	if bool(capabilities.get("native_pixel", false)):
		return Vector2i(int(params.get("target_width", 0)), int(params.get("target_height", 0)))
	var sizes: Array = capabilities.get("provider_output_sizes", [])
	if sizes.is_empty():
		return Vector2i.ZERO
	var target_ratio := (
		float(params.get("target_width", 1)) / maxf(float(params.get("target_height", 1)), 1.0)
	)
	var selected := Vector2i(int(sizes[0][0]), int(sizes[0][1]))
	var best_error := absf(float(selected.x) / float(selected.y) - target_ratio)
	for value in sizes.slice(1):
		if not (value is Array) or value.size() != 2:
			continue
		var candidate := Vector2i(int(value[0]), int(value[1]))
		var error := absf(float(candidate.x) / float(candidate.y) - target_ratio)
		if error < best_error:
			selected = candidate
			best_error = error
	return selected


func _final_prompt(
	prefix: String,
	prompt: String,
	row_text: String,
	capabilities: Dictionary,
	width: int,
	height: int
) -> String:
	var parts := []
	for value in [prefix, prompt, row_text]:
		var normalized := String(value).strip_edges()
		if not normalized.is_empty():
			parts.append(normalized)
	var semantic := ", ".join(parts)
	if semantic.is_empty() or bool(capabilities.get("native_pixel", false)):
		return semantic
	return "%s, %s" % [semantic, Planner.TECHNICAL_SUFFIX % [width, height]]


func _valid_rows(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for row_value in value:
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value
		if (
			not bool(row.get("enabled", true))
			or String(row.get("id", "")).strip_edges().is_empty()
			or String(row.get("text", "")).strip_edges().is_empty()
			or int(row.get("count", 0)) < 1
		):
			continue
		result.append(row.duplicate(true))
	return result


func _highest_non_retryable(errors: Array) -> String:
	for code in NON_RETRYABLE_PRIORITY:
		if _has_code(errors, code):
			return code
	return ""


func _has_code(errors: Array, code: String) -> bool:
	for value in errors:
		if value is Dictionary and String(value.get("code", "")) == code:
			return true
	return false


func _has_available_retry(errors: Array) -> bool:
	for value in errors:
		if value is Dictionary and bool(value.get("retryable", false)):
			return true
	return false


func _retry_wait_seconds(errors: Array) -> int:
	var result := 0
	for value in errors:
		if value is Dictionary and bool(value.get("retryable", false)):
			result = maxi(result, int(value.get("wait_seconds", 0)))
	return result


func _action(
	action_id: String, text_key: String, route: String, disabled: bool = false, args: Array = []
) -> Dictionary:
	return {
		"action_id": action_id,
		"text_key": text_key,
		"route": route,
		"disabled": disabled,
		"args": args.duplicate(),
	}
