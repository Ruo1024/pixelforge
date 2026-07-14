class_name PFDetachOutputAssetCommand
extends RefCounted

## Pure detach transaction planner. The caller commits its slot/sprite snapshots as one Undo action.

const DRAG_THRESHOLD_SCREEN_PX := 8.0
const CARD_GAP := 24
const CARD_WIDTH := 176
const MAX_COLUMNS := 4
const CONFIRM_COUNT := 12


static func crossed_drag_threshold(start: Vector2, current: Vector2) -> bool:
	return start.distance_to(current) > DRAG_THRESHOLD_SCREEN_PX


static func detach_single(
	slots: Array, slot_id: String, origin: Dictionary, drop_position: Vector2
) -> Dictionary:
	var updated := slots.duplicate(true)
	for slot in updated:
		if (
			slot is Dictionary
			and String(slot.get("slot_id", "")) == slot_id
			and String(slot.get("status", "")) == "succeeded"
			and not bool(slot.get("detached", false))
		):
			slot["detached"] = true
			return {
				"ok": true,
				"slots": updated,
				"sprites": [_sprite(slot, origin, drop_position)],
				"undo_label": "Detach Output image",
			}
	return {"ok": false, "slots": slots.duplicate(true), "sprites": []}


static func detach_all(
	slots: Array, origin: Dictionary, start_position: Vector2, confirmed: bool
) -> Dictionary:
	var targets := []
	for slot in slots:
		if (
			slot is Dictionary
			and String(slot.get("status", "")) == "succeeded"
			and not bool(slot.get("detached", false))
		):
			targets.append(slot)
	if targets.size() > CONFIRM_COUNT and not confirmed:
		return {
			"ok": false,
			"confirmation_required": true,
			"slots": slots.duplicate(true),
			"sprites": [],
		}
	var updated := slots.duplicate(true)
	var sprites := []
	var target_ids := targets.map(func(slot: Dictionary) -> String: return String(slot["slot_id"]))
	for slot in updated:
		var index := target_ids.find(String(slot.get("slot_id", "")))
		if index < 0:
			continue
		slot["detached"] = true
		var position := (
			start_position
			+ Vector2(
				(index % MAX_COLUMNS) * (CARD_WIDTH + CARD_GAP),
				int(index / MAX_COLUMNS) * (CARD_WIDTH + CARD_GAP)
			)
		)
		sprites.append(_sprite(slot, origin, position))
	return {
		"ok": not sprites.is_empty(),
		"confirmation_required": false,
		"slots": updated,
		"sprites": sprites,
		"undo_label": "Detach all Output images",
	}


static func restore_all_detached(slots: Array) -> Array:
	var updated := slots.duplicate(true)
	for slot in updated:
		if slot is Dictionary and String(slot.get("status", "")) == "succeeded":
			slot["detached"] = false
	return updated


static func empty_action(slots: Array, existing_sprite_slot_ids: Array) -> String:
	if slots.is_empty():
		return ""
	for slot in slots:
		if (
			not (slot is Dictionary)
			or String(slot.get("status", "")) != "succeeded"
			or not bool(slot.get("detached", false))
		):
			return ""
	return "locate" if not existing_sprite_slot_ids.is_empty() else "restore"


static func cancel_preview(slots: Array) -> Dictionary:
	return {"ok": false, "slots": slots.duplicate(true), "sprites": []}


static func _sprite(slot: Dictionary, origin: Dictionary, position: Vector2) -> Dictionary:
	return {
		"type": "sprite",
		"asset_id": String(slot.get("asset_id", "")),
		"position": [int(round(position.x)), int(round(position.y))],
		"origin_graph_id": String(origin.get("origin_graph_id", "")),
		"origin_batch_node_id": String(origin.get("origin_batch_node_id", "")),
		"origin_slot_id": String(slot.get("slot_id", "")),
	}
