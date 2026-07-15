extends "res://addons/gut/test.gd"

const InterfaceScalePolicy := preload("res://ui/shell/interface_scale_policy.gd")
const GenerationCardViewScript := preload("res://ui/canvas/generation_card_view.gd")
const OutputCardControllerScript := preload("res://ui/canvas/output_card_controller.gd")
const CleanupCardViewScript := preload("res://ui/canvas/cleanup_card_view.gd")

const MATRIX_LOCALES := ["en", "zh_CN"]
const MATRIX_WINDOWS := [Vector2(1080, 560), Vector2(1280, 720), Vector2(1440, 900)]
const MATRIX_SCALES := [1.0, 1.25, 1.5]


func before_each() -> void:
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, 1.0)
	LocalizationService.set_language("en")


func after_each() -> void:
	SettingsService.set_setting("ui", "interface_scale", 1.0, false)
	InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, 1.0)
	LocalizationService.apply_language("en", "en")


func test_eighteen_cases() -> void:
	var case_count := 0
	for locale in MATRIX_LOCALES:
		for window_size in MATRIX_WINDOWS:
			for interface_scale in MATRIX_SCALES:
				case_count += 1
				var case_label := "%s %s @ %.2f" % [locale, window_size, interface_scale]
				SettingsService.set_setting("ui", "interface_scale", interface_scale, false)
				InterfaceScalePolicy.apply_content_scale_policy(get_tree().root, interface_scale)
				LocalizationService.apply_language(locale, locale)
				var generation := _generation_view()
				var output := _output_view()
				var cleanup := _cleanup_view()
				add_child(generation)
				add_child(output)
				add_child(cleanup)
				generation.configure(_generation_snapshot())
				output.configure(_output_snapshot())
				cleanup.configure(_cleanup_snapshot())
				await wait_process_frames(2)
				assert_almost_eq(
					get_tree().root.content_scale_factor,
					interface_scale,
					0.001,
					case_label,
				)
				_assert_card_regions(generation, case_label + " Generation")
				_assert_card_regions(cleanup, case_label + " Cleanup")
				_assert_output_geometry(output, case_label + " Output")
				_assert_key_text_fits(generation, case_label + " Generation")
				_assert_key_text_fits(cleanup, case_label + " Cleanup")
				_assert_key_text_fits(output.get_node("TopRail"), case_label + " Output rail")
				generation.queue_free()
				output.queue_free()
				cleanup.queue_free()
				await wait_process_frames(1)
	assert_eq(case_count, 18)


func _assert_card_regions(card: Control, label: String) -> void:
	var status: Control = card.get_node("RunStatusGroup")
	var body: Control = (
		card.get_node("BodyGroups")
		if card.has_node("BodyGroups")
		else card.get_node("SummaryGroup")
	)
	var footer: Control = card.get_node("Footer")
	_assert_rect_inside(Rect2(status.position, status.size), Rect2(Vector2.ZERO, card.size), label)
	_assert_rect_inside(Rect2(body.position, body.size), Rect2(Vector2.ZERO, card.size), label)
	_assert_rect_inside(Rect2(footer.position, footer.size), Rect2(Vector2.ZERO, card.size), label)
	assert_lte(status.position.y + status.size.y, body.position.y + 0.5, label + " status/body")
	assert_lte(body.position.y + body.size.y, footer.position.y + 0.5, label + " body/footer")
	_assert_container_children_do_not_overlap(status, label + " status")
	_assert_container_children_do_not_overlap(footer, label + " footer")
	_assert_container_children_do_not_overlap(body, label + " body groups")
	assert_lte(body.size.x, card.size.x + 0.5, label + " body must not overflow sideways")


func _assert_output_geometry(output: Control, label: String) -> void:
	var rail: Control = output.get_node("TopRail")
	var grid: Control = output.get_node("SlotGrid")
	var card_rect := Rect2(Vector2.ZERO, output.size)
	_assert_rect_inside(Rect2(rail.position, rail.size), card_rect, label + " rail")
	_assert_rect_inside(Rect2(grid.position, grid.size), card_rect, label + " grid")
	assert_lte(rail.position.y + rail.size.y, grid.position.y + 0.5, label + " rail/grid")
	_assert_container_children_do_not_overlap(rail, label + " rail")
	var port: Control = rail.get_node("Port")
	assert_almost_eq(
		port.global_position.y + port.size.y * 0.5,
		rail.global_position.y + rail.size.y * 0.5,
		0.5,
		label + " port vertical alignment",
	)
	assert_almost_eq(
		port.global_position.x + port.size.x,
		output.global_position.x + output.size.x,
		0.5,
		label + " port right-edge alignment",
	)
	for index in range(12):
		var slot_rect: Rect2 = grid.slot_rect(index)
		assert_gte(slot_rect.position.x, 0.0, label + " slot %d left" % index)
		assert_lte(slot_rect.end.x, grid.size.x + 0.5, label + " slot %d right" % index)
		if index < 12:
			assert_gte(slot_rect.size.x, 176.0, label + " slot %d minimum" % index)


func _assert_key_text_fits(root: Node, label: String) -> void:
	var controls := _text_controls(root)
	assert_gt(controls.size(), 0, label)
	for control: Control in controls:
		if not control.is_visible_in_tree():
			continue
		var minimum := control.get_combined_minimum_size()
		assert_lte(minimum.x, control.size.x + 0.5, "%s %s width" % [label, control.name])
		assert_lte(minimum.y, control.size.y + 0.5, "%s %s height" % [label, control.name])


func _assert_container_children_do_not_overlap(container: Control, label: String) -> void:
	var children: Array[Control] = []
	for child in container.get_children():
		if child is Control and child.visible and child.size.x > 0.0 and child.size.y > 0.0:
			children.append(child)
	for left_index in range(children.size()):
		for right_index in range(left_index + 1, children.size()):
			var left := Rect2(children[left_index].position, children[left_index].size)
			var right := Rect2(children[right_index].position, children[right_index].size)
			var overlap := left.intersection(right)
			assert_true(
				overlap.size.x <= 0.5 or overlap.size.y <= 0.5,
				(
					"%s: %s overlaps %s"
					% [label, children[left_index].name, children[right_index].name]
				),
			)


func _assert_rect_inside(inner: Rect2, outer: Rect2, label: String) -> void:
	assert_gte(inner.position.x, outer.position.x - 0.5, label + " left")
	assert_gte(inner.position.y, outer.position.y - 0.5, label + " top")
	assert_lte(inner.end.x, outer.end.x + 0.5, label + " right")
	assert_lte(inner.end.y, outer.end.y + 0.5, label + " bottom")


func _text_controls(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	_collect_text_controls(root, result)
	return result


func _collect_text_controls(node: Node, result: Array[Control]) -> void:
	if node is Label or node is Button or node is LineEdit or node is OptionButton:
		result.append(node)
	for child in node.get_children():
		_collect_text_controls(child, result)


func _generation_view() -> Control:
	var view: Control = GenerationCardViewScript.new()
	view.size = Vector2(420, 520)
	return view


func _output_view() -> Control:
	var view: Control = OutputCardControllerScript.new()
	view.size = Vector2(720, 520)
	return view


func _cleanup_view() -> Control:
	var view: Control = CleanupCardViewScript.new()
	view.size = Vector2(420, 360)
	return view


func _generation_snapshot() -> Dictionary:
	var descriptor := {
		"provider_id": "openai_image",
		"model_id": "gpt-image-2",
		"display_name": "GPT Image 2",
		"capabilities":
		{
			"txt2img": true,
			"img2img": true,
			"native_pixel": false,
			"max_reference_images": 4,
			"max_batch": 4,
			"target_size_constraints":
			{
				"min_width": 1,
				"max_width": 4096,
				"width_step": 1,
				"min_height": 1,
				"max_height": 4096,
				"height_step": 1,
			},
			"supported_modes": ["txt2img", "img2img"],
			"supports_seed": true,
		},
		"dynamic_params": [],
		"is_default": true,
	}
	return {
		"params":
		{
			"provider_id": "openai_image",
			"model_id": "gpt-image-2",
			"resolution_preset": "1080p",
			"orientation": "square",
			"batch_size": 4,
			"seed": -1,
			"extra": {},
		},
		"descriptor": descriptor,
		"descriptors": [descriptor],
		"prompt": "forest shrine with a warm lantern",
		"prefix": "crisp pixel art",
		"rows": [],
		"input_sources": [{"id": "prompt", "summary": "forest shrine"}],
		"run":
		{
			"state": "Running",
			"errors": [],
			"progress":
			{
				"determinate": true,
				"completed_items": 2,
				"total_items": 4,
				"ratio": 0.5,
				"elapsed_ms": 3200
			},
		},
	}


func _output_snapshot() -> Dictionary:
	var slots := []
	for index in range(12):
		(
			slots
			. append(
				{
					"slot_id": "slot-%02d" % index,
					"status": "succeeded" if index % 3 != 2 else "failed",
					"asset_id": "asset-%02d" % index if index % 3 != 2 else null,
					"detached": false,
				}
			)
		)
	return {
		"state": "Partial",
		"role": "history",
		"source_node_id": "generate",
		"result_slots": slots,
	}


func _cleanup_snapshot() -> Dictionary:
	return {
		"params": {"preset_id": "cleanup-16bit-db32", "settings": {}},
		"run": {"state": "Running"},
		"input": {"kind": "Output", "count": 12, "target": "32×32"},
	}
