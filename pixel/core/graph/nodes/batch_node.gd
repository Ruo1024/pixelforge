class_name PFBatchNode
extends PFNode

## Output 领域容器。素材真相只存在 result_slots；asset_ids 已硬切删除。

const ProviderContractV2 := preload("res://core/provider/pf_provider_contract_v2.gd")

const PARAM_KEYS := [
	"label",
	"source_node_id",
	"source_run_id",
	"role",
	"input_snapshots",
	"request_records",
	"result_slots",
]
const SLOT_KEYS := [
	"slot_id",
	"run_id",
	"request_id",
	"source_row_id",
	"source_asset_id",
	"input_snapshot_id",
	"planned_size",
	"status",
	"detached",
	"unexpected",
	"error",
]
const SLOT_STATES := ["queued", "running", "succeeded", "failed", "canceled"]


func get_type() -> String:
	return "batch"


func get_display_name() -> String:
	return "Output"


func get_category() -> String:
	return "container"


func get_input_ports() -> Array[Dictionary]:
	return [{"name": "in", "type": "asset_list", "required": false}]


func get_output_ports() -> Array[Dictionary]:
	return [{"name": "assets", "type": "asset_list"}]


func get_param_schema() -> Array[Dictionary]:
	return []


func is_canvas_resident() -> bool:
	return true


func validate_params(params: Dictionary) -> Dictionary:
	return {
		"label": String(params.get("label", "")),
		"source_node_id": String(params.get("source_node_id", "")),
		"source_run_id": String(params.get("source_run_id", "")),
		"role": _valid_role(String(params.get("role", "standalone"))),
		"input_snapshots":
		(
			Dictionary(params.get("input_snapshots", {})).duplicate(true)
			if params.get("input_snapshots", {}) is Dictionary
			else {}
		),
		"request_records":
		(
			Array(params.get("request_records", [])).duplicate(true)
			if params.get("request_records", []) is Array
			else []
		),
		"result_slots":
		(
			Array(params.get("result_slots", [])).duplicate(true)
			if params.get("result_slots", []) is Array
			else []
		),
	}


func execute(_inputs: Dictionary, params: Dictionary, _ctx: Variant) -> Dictionary:
	return {"assets": get_visible_asset_ids(params)}


static func get_visible_asset_ids(batch_params: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var slots: Variant = batch_params.get("result_slots", [])
	if not (slots is Array):
		return result
	for raw_slot in slots:
		if not (raw_slot is Dictionary):
			continue
		if (
			String(raw_slot.get("status", "")) != "succeeded"
			or bool(raw_slot.get("detached", false))
		):
			continue
		var asset_id := String(raw_slot.get("asset_id", ""))
		if not asset_id.is_empty():
			result.append(asset_id)
	return result


static func validate_v2_domain(params: Dictionary) -> Dictionary:
	if not _has_exact_keys(params, PARAM_KEYS):
		return _issue("params")
	if (
		not (params["label"] is String)
		or not (params["source_node_id"] is String)
		or not (params["source_run_id"] is String)
		or not (params["role"] is String)
		or not (params["input_snapshots"] is Dictionary)
		or not (params["request_records"] is Array)
		or not (params["result_slots"] is Array)
	):
		return _issue("params")
	var role := String(params["role"])
	var source_node_id := String(params["source_node_id"])
	var source_run_id := String(params["source_run_id"])
	if role not in ["current", "history", "standalone"]:
		return _issue("params.role")
	if role == "standalone" and not source_node_id.is_empty():
		return _issue("params.source_node_id")
	if role in ["current", "history"] and (source_node_id.is_empty() or source_run_id.is_empty()):
		return _issue("params.source_node_id")

	var snapshots: Dictionary = params["input_snapshots"]
	for snapshot_id in snapshots:
		if String(snapshot_id).is_empty() or not (snapshots[snapshot_id] is Dictionary):
			return _issue("params.input_snapshots")
		if not _snapshot_is_valid(snapshots[snapshot_id]):
			return _issue("params.input_snapshots.%s" % String(snapshot_id))

	var record_ids := {}
	var records: Array = params["request_records"]
	for index in range(records.size()):
		if not (records[index] is Dictionary) or not _record_is_valid(records[index]):
			return _issue("params.request_records[%d]" % index)
		var request_id := String(records[index]["request_id"])
		if request_id.is_empty() or record_ids.has(request_id):
			return _issue("params.request_records[%d].request_id" % index)
		record_ids[request_id] = records[index]

	var slot_ids := {}
	var slots: Array = params["result_slots"]
	for index in range(slots.size()):
		if not (slots[index] is Dictionary):
			return _issue("params.result_slots[%d]" % index)
		var slot: Dictionary = slots[index]
		if not _slot_is_valid(slot):
			return _issue("params.result_slots[%d]" % index)
		var slot_id := String(slot["slot_id"])
		if slot_ids.has(slot_id):
			return _issue("params.result_slots[%d].slot_id" % index)
		slot_ids[slot_id] = true
		var snapshot_id := String(slot["input_snapshot_id"])
		if not snapshot_id.is_empty() and not snapshots.has(snapshot_id):
			return _issue("params.result_slots[%d].input_snapshot_id" % index)
		var request_id := String(slot["request_id"])
		if not request_id.is_empty() and not record_ids.has(request_id):
			return _issue("params.result_slots[%d].request_id" % index)

	for record_index in range(records.size()):
		var record: Dictionary = records[record_index]
		var referenced_slots := {}
		for raw_slot_id in record["slot_ids"]:
			if not (raw_slot_id is String):
				return _issue("params.request_records[%d].slot_ids" % record_index)
			var referenced_slot_id := String(raw_slot_id)
			if (
				referenced_slot_id.is_empty()
				or referenced_slots.has(referenced_slot_id)
				or not slot_ids.has(referenced_slot_id)
			):
				return _issue("params.request_records[%d].slot_ids" % record_index)
			referenced_slots[referenced_slot_id] = true
		if int(record["requested_count"]) > referenced_slots.size():
			return _issue("params.request_records[%d].requested_count" % record_index)
		var successful_count := 0
		for slot in slots:
			if (
				referenced_slots.has(String(slot["slot_id"]))
				and String(slot["status"]) == "succeeded"
			):
				successful_count += 1
		if int(record["received_count"]) != successful_count:
			return _issue("params.request_records[%d].received_count" % record_index)
	for slot_index in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		var slot_request_id := String(slot["request_id"])
		if slot_request_id.is_empty():
			continue
		var matched_record: Dictionary = record_ids[slot_request_id]
		if not Array(matched_record["slot_ids"]).has(String(slot["slot_id"])):
			return _issue("params.result_slots[%d].request_id" % slot_index)

	if records.is_empty():
		if role == "standalone" and not source_run_id.is_empty():
			return _issue("params.source_run_id")
		for slot in slots:
			if (
				not String(slot["run_id"]).is_empty()
				or not String(slot["request_id"]).is_empty()
				or not String(slot["input_snapshot_id"]).is_empty()
			):
				return _issue("params.result_slots")
	return {"ok": true}


static func _slot_is_valid(slot: Dictionary) -> bool:
	var expected_keys := SLOT_KEYS.duplicate()
	var status_value: Variant = slot.get("status", null)
	if status_value == "succeeded":
		expected_keys.append("asset_id")
	if not _has_exact_keys(slot, expected_keys):
		return false
	for key in [
		"slot_id", "run_id", "request_id", "source_row_id", "source_asset_id", "input_snapshot_id"
	]:
		if not (slot[key] is String):
			return false
	if String(slot["slot_id"]).is_empty() or not (slot["status"] is String):
		return false
	var status := String(slot["status"])
	if (
		status not in SLOT_STATES
		or not (slot["detached"] is bool)
		or not (slot["unexpected"] is bool)
	):
		return false
	if (bool(slot["detached"]) or bool(slot["unexpected"])) and status != "succeeded":
		return false
	if not _positive_size(slot["planned_size"]):
		return false
	if status == "succeeded":
		return (
			slot["asset_id"] is String
			and not String(slot["asset_id"]).is_empty()
			and slot["error"] == null
		)
	if status == "failed":
		return (
			slot["error"] is Dictionary
			and ProviderContractV2.validate_pf_error(slot["error"]) == null
		)
	return slot["error"] == null


static func _record_is_valid(record: Dictionary) -> bool:
	var keys := [
		"kind",
		"provider_id",
		"run_id",
		"request_id",
		"source_row_id",
		"slot_ids",
		"requested_count",
		"received_count",
		"attempts",
		"state",
		"actual_cost_usd",
		"charge_id",
		"provider_meta",
		"remote_cancel_confirmed",
		"error",
	]
	if not _has_exact_keys(record, keys):
		return false
	for key in [
		"kind", "provider_id", "run_id", "request_id", "source_row_id", "state", "charge_id"
	]:
		if not (record[key] is String):
			return false
	var kind := String(record["kind"])
	var state := String(record["state"])
	if (
		kind not in ["provider", "cleanup"]
		or state not in ["queued", "running", "succeeded", "partial", "failed", "canceled"]
	):
		return false
	if kind == "provider" and String(record["provider_id"]).is_empty():
		return false
	if kind == "cleanup" and (not String(record["provider_id"]).is_empty() or state == "partial"):
		return false
	if String(record["run_id"]).is_empty() or String(record["request_id"]).is_empty():
		return false
	if (
		not (record["slot_ids"] is Array)
		or not (record["requested_count"] is int)
		or not (record["received_count"] is int)
		or not (record["attempts"] is int)
	):
		return false
	if (
		int(record["requested_count"]) < 1
		or int(record["received_count"]) < 0
		or int(record["attempts"]) < 0
		or int(record["attempts"]) > 3
	):
		return false
	if not (record["provider_meta"] is Dictionary) or not (record["charge_id"] is String):
		return false
	if not _valid_cost(record["actual_cost_usd"]):
		return false
	if not _valid_charge_id(String(record["charge_id"])):
		return false
	if not _valid_provider_meta(record["provider_meta"]):
		return false
	if (
		kind == "cleanup"
		and (
			record["actual_cost_usd"] != null
			or not String(record["charge_id"]).is_empty()
			or not Dictionary(record["provider_meta"]).is_empty()
		)
	):
		return false
	if state == "canceled":
		if not (record["remote_cancel_confirmed"] is bool):
			return false
	elif record["remote_cancel_confirmed"] != null:
		return false
	if state in ["partial", "failed"]:
		return (
			record["error"] is Dictionary
			and ProviderContractV2.validate_pf_error(record["error"]) == null
		)
	return record["error"] == null


static func _snapshot_is_valid(snapshot: Dictionary) -> bool:
	if not (snapshot.get("kind", null) is String):
		return false
	if String(snapshot["kind"]) == "generation":
		var keys := [
			"kind",
			"graph_id",
			"source_node_id",
			"provider_id",
			"model_id",
			"mode",
			"prompt",
			"source_row_id",
			"prompt_preset_id",
			"prompt_prefix",
			"reference_asset_ids",
			"reference_content_sha256s",
			"target_width",
			"target_height",
			"provider_output_size",
			"requested_seed",
			"extra",
		]
		if not _has_exact_keys(snapshot, keys):
			return false
		for key in [
			"graph_id",
			"source_node_id",
			"provider_id",
			"model_id",
			"mode",
			"prompt",
			"source_row_id",
			"prompt_preset_id",
			"prompt_prefix"
		]:
			if not (snapshot[key] is String):
				return false
		if (
			String(snapshot["graph_id"]).is_empty()
			or String(snapshot["source_node_id"]).is_empty()
			or String(snapshot["provider_id"]).is_empty()
			or String(snapshot["model_id"]).is_empty()
		):
			return false
		if String(snapshot["mode"]) not in ["txt2img", "img2img"]:
			return false
		if (
			not (snapshot["reference_asset_ids"] is Array)
			or not (snapshot["reference_content_sha256s"] is Array)
			or (
				Array(snapshot["reference_asset_ids"]).size()
				!= Array(snapshot["reference_content_sha256s"]).size()
			)
		):
			return false
		if (
			not (snapshot["target_width"] is int)
			or not (snapshot["target_height"] is int)
			or int(snapshot["target_width"]) < 1
			or int(snapshot["target_height"]) < 1
		):
			return false
		if (
			not _positive_size(snapshot["provider_output_size"])
			or not (snapshot["requested_seed"] is int)
			or int(snapshot["requested_seed"]) < -1
			or int(snapshot["requested_seed"]) > 2147483647
		):
			return false
		return snapshot["extra"] is Dictionary
	return false


static func _positive_size(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value[0] is int
		and value[1] is int
		and int(value[0]) > 0
		and int(value[1]) > 0
	)


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _valid_cost(value: Variant) -> bool:
	if value == null:
		return true
	if not (value is String):
		return false
	var regex := RegEx.new()
	return (
		regex.compile("^(0|[1-9][0-9]{0,8})[.][0-9]{6}$") == OK
		and regex.search(String(value)) != null
	)


static func _valid_charge_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[A-Za-z0-9._:-]{0,128}$") == OK and regex.search(value) != null


static func _valid_provider_meta(value: Dictionary) -> bool:
	if value.is_empty():
		return true
	if value.size() != 1 or not value.has("remote_task_id"):
		return false
	if not (value["remote_task_id"] is String):
		return false
	var regex := RegEx.new()
	return (
		regex.compile("^[A-Za-z0-9._:-]{1,128}$") == OK
		and regex.search(String(value["remote_task_id"])) != null
	)


static func _issue(path: String) -> Dictionary:
	return {"ok": false, "path": path}


func _valid_role(value: String) -> String:
	return value if value in ["current", "history", "standalone"] else "standalone"
