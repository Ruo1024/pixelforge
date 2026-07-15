extends "res://addons/gut/test.gd"

const Library := preload("res://services/prompt_preset_library.gd")
const ViewScript := preload("res://ui/canvas/prompt_preset_card_view.gd")
const CardScript := preload("res://ui/canvas/canvas_node_card.gd")
const Planner := preload("res://services/generation_request_planner.gd")
const PromptPresetNode := preload("res://core/graph/nodes/prompt_preset_node.gd")

const PLUGIN_ID := "b7f-plugin-prompt"
const PLUGIN_OWNER := "b7f_prompt_test"

var _original_user_presets: Variant


func before_each() -> void:
	LocalizationService.set_language("en")
	_original_user_presets = SettingsService.get_setting(
		Library.SETTINGS_SECTION, Library.SETTINGS_KEY, []
	)
	if _original_user_presets is Array:
		_original_user_presets = _original_user_presets.duplicate(true)
	SettingsService.set_setting(Library.SETTINGS_SECTION, Library.SETTINGS_KEY, [])
	PluginService.unregister_capability("prompt_preset", PLUGIN_ID, PLUGIN_OWNER)


func after_each() -> void:
	PluginService.unregister_capability("prompt_preset", PLUGIN_ID, PLUGIN_OWNER)
	SettingsService.set_setting(
		Library.SETTINGS_SECTION, Library.SETTINGS_KEY, _original_user_presets
	)


func test_library_lists_read_only_builtin_and_plugin_plus_persistent_user_crud() -> void:
	var plugin := _plugin_preset()
	assert_true(PluginService.register_capability("prompt_preset", PLUGIN_ID, plugin, PLUGIN_OWNER))
	var created := Library.create_user_preset("Forest props", "mossy pixel art")
	assert_true(created["ok"])
	var user: Dictionary = created["preset"]
	var entries := Library.list_entries()
	var builtin_count := 0
	var plugin_found := false
	var user_found := false
	for entry in entries:
		if entry["source"] == "builtin":
			builtin_count += 1
		if entry["id"] == PLUGIN_ID and entry["read_only"]:
			plugin_found = true
		if entry["id"] == user["id"] and not entry["read_only"]:
			user_found = true
	assert_eq(builtin_count, 6)
	assert_true(plugin_found)
	assert_true(user_found)

	user["name"] = "Renamed forest props"
	user["prefix"] = "saved user prefix\nwith two lines"
	assert_true(Library.save_user_preset(user)["ok"])
	SettingsService.load_settings()
	assert_eq(Library.user_presets(), [user], "user preset survives a settings reload")
	assert_true(Library.delete_user_preset(user["id"]))
	assert_true(Library.user_presets().is_empty())
	assert_eq(plugin, _plugin_preset(), "plugin preset remains an immutable detached snapshot")


func test_read_only_edit_copies_first_then_save_updates_user_library_and_node_snapshot() -> void:
	var view := await _view(_builtin_preset())
	var commits := []
	view.preset_commit_requested.connect(
		func(preset: Dictionary) -> void: commits.append(preset.duplicate(true))
	)
	assert_string_contains(
		view.get_node("PromptPresetScroll/PromptPresetBody/PresetSource").text, "read-only"
	)

	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetEdit") as Button)
		. pressed
		. emit()
	)
	assert_eq(commits.size(), 1, "editing a read-only preset first selects a user copy")
	assert_true(commits[0].has("name"))
	assert_false(commits[0].has("name_key"))
	assert_eq(commits[0]["prefix"], _builtin_preset()["prefix"])
	var name_edit: LineEdit = view.get_node("PromptPresetScroll/PromptPresetBody/PresetNameEdit")
	var prefix_edit: TextEdit = view.get_node(
		"PromptPresetScroll/PromptPresetBody/PresetPrefixEdit"
	)
	name_edit.text = "My edited style"
	name_edit.text_changed.emit(name_edit.text)
	prefix_edit.text = "custom prefix\nkept exactly"
	prefix_edit.text_changed.emit()
	assert_true(view.has_unsaved_changes())
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetSave") as Button)
		. pressed
		. emit()
	)

	assert_eq(commits.size(), 2)
	assert_eq(commits[-1]["name"], "My edited style")
	assert_eq(commits[-1]["prefix"], "custom prefix\nkept exactly")
	assert_eq(Library.user_presets(), [commits[-1]])
	assert_eq(view.get_current_preset(), commits[-1])
	assert_false(view.has_unsaved_changes())


func test_compact_canvas_card_routes_editing_to_the_right_inspector() -> void:
	var view := await _view(_builtin_preset())
	view.set_compact_mode(true)
	var intents := []
	view.inspector_requested.connect(func(intent: String) -> void: intents.append(intent))
	assert_false(view.find_child("PresetNameEdit", true, false).visible)
	assert_false(view.find_child("PresetPrefixEdit", true, false).visible)
	(view.find_child("PresetNew", true, false) as Button).pressed.emit()
	(view.find_child("PresetEdit", true, false) as Button).pressed.emit()
	assert_eq(intents, ["new", "edit"])
	assert_eq(view.get_current_preset(), _builtin_preset())


func test_user_new_copy_rename_copy_text_and_delete_keep_node_snapshot() -> void:
	var view := await _view(_builtin_preset())
	var commits := []
	var copied_texts := []
	view.preset_commit_requested.connect(
		func(preset: Dictionary) -> void: commits.append(preset.duplicate(true))
	)
	view.text_copy_requested.connect(func(text: String) -> void: copied_texts.append(text))
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetNew") as Button)
		. pressed
		. emit()
	)
	assert_true(view.has_unsaved_changes() == false)
	var new_snapshot: Dictionary = view.get_current_preset()
	assert_true(String(new_snapshot["id"]).begins_with("user-prompt-"))
	var name_edit: LineEdit = view.get_node("PromptPresetScroll/PromptPresetBody/PresetNameEdit")
	name_edit.text = "New style"
	name_edit.text_changed.emit(name_edit.text)
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetSave") as Button)
		. pressed
		. emit()
	)
	var saved_snapshot: Dictionary = view.get_current_preset()
	assert_eq(saved_snapshot["name"], "New style")

	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetRename") as Button)
		. pressed
		. emit()
	)
	name_edit.text = "Renamed style"
	name_edit.text_changed.emit(name_edit.text)
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetSave") as Button)
		. pressed
		. emit()
	)
	assert_eq(view.get_current_preset()["name"], "Renamed style")
	var renamed_snapshot: Dictionary = view.get_current_preset()
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetCopy") as Button)
		. pressed
		. emit()
	)
	assert_ne(view.get_current_preset()["id"], renamed_snapshot["id"])
	assert_eq(view.get_current_preset()["prefix"], renamed_snapshot["prefix"])
	(
		(
			view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetCopyText")
			as Button
		)
		. pressed
		. emit()
	)
	assert_eq(copied_texts, [String(view.get_current_preset()["prefix"])])

	var preserved_snapshot: Dictionary = view.get_current_preset()
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetDelete") as Button)
		. pressed
		. emit()
	)
	assert_false(_has_user_preset(String(preserved_snapshot["id"])))
	assert_eq(
		view.get_current_preset(),
		preserved_snapshot,
		"deleting library entry cannot damage node snapshot"
	)
	assert_string_contains(
		view.get_node("PromptPresetScroll/PromptPresetBody/PresetSource").text, "Project snapshot"
	)
	assert_eq(commits[-1], preserved_snapshot, "delete does not rewrite the node")


func test_unsaved_switch_save_discard_and_cancel_are_explicit_and_atomic() -> void:
	var first: Dictionary = Library.create_user_preset("First", "first prefix")["preset"]
	var second: Dictionary = Library.create_user_preset("Second", "second prefix")["preset"]
	var view := await _view(first)
	var commits := []
	view.preset_commit_requested.connect(
		func(preset: Dictionary) -> void: commits.append(preset.duplicate(true))
	)
	_enter_prefix_draft(view, "discarded draft")
	assert_true(view.request_selection_by_id(second["id"]))
	assert_true(view.has_unsaved_changes())
	view.resolve_unsaved_switch("cancel")
	await wait_process_frames(1)
	assert_eq(view.get_current_preset(), first)
	assert_true(view.has_unsaved_changes())
	assert_true(
		(
			(view.get_node("PromptPresetScroll/PromptPresetBody/PresetPrefixEdit") as TextEdit)
			. has_focus()
		)
	)
	assert_true(commits.is_empty())

	assert_true(view.request_selection_by_id(second["id"]))
	view.resolve_unsaved_switch("discard")
	assert_eq(view.get_current_preset(), second)
	assert_eq(commits, [second])
	assert_eq(Library.user_presets()[0]["prefix"], "first prefix")

	assert_true(view.request_selection_by_id(first["id"]))
	_enter_prefix_draft(view, "saved before switch")
	assert_true(view.request_selection_by_id(second["id"]))
	var count_before_resolution := commits.size()
	view.resolve_unsaved_switch("save")
	assert_eq(view.get_current_preset(), second)
	assert_eq(
		commits.size(),
		count_before_resolution + 1,
		"save-and-switch commits only target node snapshot"
	)
	assert_eq(commits[-1], second)
	assert_eq(Library.user_presets()[0]["prefix"], "saved before switch")


func test_plugin_selection_is_read_only_and_edit_derives_user_copy() -> void:
	var plugin := _plugin_preset()
	assert_true(PluginService.register_capability("prompt_preset", PLUGIN_ID, plugin, PLUGIN_OWNER))
	var view := await _view(_builtin_preset())
	var commits := []
	view.preset_commit_requested.connect(
		func(preset: Dictionary) -> void: commits.append(preset.duplicate(true))
	)
	assert_true(view.request_selection_by_id(PLUGIN_ID))
	assert_eq(commits[-1], plugin)
	assert_string_contains(
		view.get_node("PromptPresetScroll/PromptPresetBody/PresetSource").text, "Plugin"
	)
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetEdit") as Button)
		. pressed
		. emit()
	)
	assert_eq(commits[-1]["prefix"], plugin["prefix"])
	assert_true(commits[-1].has("name"))
	assert_false(commits[-1].has("name_key"))


func test_canvas_card_routes_user_preset_edit_to_inspector_and_keeps_same_lod_identity() -> void:
	var user: Dictionary = Library.create_user_preset("Card user", "stored prefix")["preset"]
	(
		ProjectService
		. set_graph_data(
			"style_graph",
			{
				"graph_version": 2,
				"id": "style_graph",
				"name": "Style",
				"nodes": [{"id": "style", "type": "prompt_preset", "params": {"preset": user}}],
				"edges": [],
			},
			false
		)
	)
	var card: Node = CardScript.new()
	(
		card
		. setup_from_data(
			{
				"id": "style_item",
				"type": "node",
				"graph_id": "style_graph",
				"node_id": "style",
				"position": [0, 0],
			}
		)
	)
	add_child_autofree(card)
	await wait_process_frames(2)
	var commits := []
	var actions := []
	card.params_commit_requested.connect(
		func(_graph_id: String, _node_id: String, params: Dictionary) -> void:
			commits.append(params.duplicate(true))
	)
	card.action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)
	var content: Control = card.get_node("Content")
	var view: Control = card.get_content_control("PromptPresetCardView")
	(card.get_content_control("PresetEdit") as Button).pressed.emit()
	var prefix_edit: TextEdit = card.get_content_control("PresetPrefixEdit")
	await wait_process_frames(1)
	assert_eq(actions, [["style_graph", "style", "open_prompt_settings:edit"]])
	assert_false(prefix_edit.visible)
	assert_false(prefix_edit.editable)
	card.set_lod_camera_zoom(1.5)
	assert_same(card.get_node("Content"), content)
	assert_same(card.get_content_control("PromptPresetCardView"), view)
	assert_same(card.get_content_control("PresetPrefixEdit"), prefix_edit)

	card.refresh_from_graph()
	await wait_process_frames(2)
	var replacement_view: Control = card.get_content_control("PromptPresetCardView")
	var replacement_prefix: TextEdit = card.get_content_control("PresetPrefixEdit")
	assert_ne(replacement_view, view)
	assert_false(replacement_view.has_unsaved_changes())
	assert_false(replacement_prefix.visible)
	assert_true(card.get_content_control("PromptPresetScroll").has_meta("_pf_scroll_owner_wired"))
	assert_true(commits.is_empty())


func test_read_only_canvas_card_opens_inspector_without_creating_hidden_copy() -> void:
	(
		ProjectService
		. set_graph_data(
			"style_refresh_graph",
			{
				"graph_version": 2,
				"id": "style_refresh_graph",
				"name": "Style refresh",
				"nodes":
				[
					{
						"id": "style",
						"type": "prompt_preset",
						"params": {"preset": _builtin_preset()},
					}
				],
				"edges": [],
			},
			false
		)
	)
	var card: Node = CardScript.new()
	(
		card
		. setup_from_data(
			{
				"id": "style_refresh_item",
				"type": "node",
				"graph_id": "style_refresh_graph",
				"node_id": "style",
				"position": [0, 0],
			}
		)
	)
	add_child_autofree(card)
	await wait_process_frames(2)
	var commits := []
	var actions := []
	card.params_commit_requested.connect(
		func(graph_id: String, node_id: String, params: Dictionary) -> void:
			commits.append(params.duplicate(true))
			var graph: Dictionary = ProjectService.get_graph_data(graph_id)
			for node_data in graph.get("nodes", []):
				if String(node_data.get("id", "")) == node_id:
					node_data["params"] = params.duplicate(true)
					break
			ProjectService.set_graph_data(graph_id, graph, true)
			card.refresh_from_graph()
	)
	card.action_requested.connect(
		func(graph_id: String, node_id: String, action_id: String) -> void:
			actions.append([graph_id, node_id, action_id])
	)

	(card.get_content_control("PresetEdit") as Button).pressed.emit()
	await wait_process_frames(2)

	assert_true(commits.is_empty())
	assert_eq(actions, [["style_refresh_graph", "style", "open_prompt_settings:edit"]])
	assert_false(card.get_content_control("PresetNameEdit").visible)
	assert_false(card.get_content_control("PresetPrefixEdit").visible)
	assert_true(card.get_content_control("PresetEdit").visible)


func test_runtime_injects_nonempty_snapshot_prefix_once_and_omits_empty_prefix() -> void:
	var final_prompt := Planner._semantic_prompt("STYLE_ONCE", "free prompt", "subject")
	assert_eq(final_prompt, "STYLE_ONCE, free prompt, subject")
	assert_eq(final_prompt.count("STYLE_ONCE"), 1)
	assert_eq(Planner._semantic_prompt("", "free prompt", "subject"), "free prompt, subject")
	var executed := PromptPresetNode.new().execute({}, {"preset": _builtin_preset()}, null)
	assert_eq(executed["prefix"]["prefix"], _builtin_preset()["prefix"])


func _view(preset: Dictionary) -> Control:
	var view: Control = ViewScript.new()
	view.size = Vector2(320, 280)
	view.configure(preset)
	add_child_autofree(view)
	await wait_process_frames(2)
	return view


func _enter_prefix_draft(view: Control, text: String) -> void:
	(
		(view.get_node("PromptPresetScroll/PromptPresetBody/PresetActions/PresetEdit") as Button)
		. pressed
		. emit()
	)
	var prefix_edit: TextEdit = view.get_node(
		"PromptPresetScroll/PromptPresetBody/PresetPrefixEdit"
	)
	prefix_edit.text = text
	prefix_edit.text_changed.emit()


func _builtin_preset() -> Dictionary:
	return {
		"prompt_preset_version": 1,
		"id": "prompt-hibit",
		"name_key": "PROMPT_PRESET_HIBIT",
		"prefix": "high detail pixel art, controlled palette, modern hi-bit game asset",
	}


func _plugin_preset() -> Dictionary:
	return {
		"prompt_preset_version": 1,
		"id": PLUGIN_ID,
		"name": "Plugin prompt",
		"prefix": "plugin-owned prefix",
	}


func _has_user_preset(preset_id: String) -> bool:
	for preset in Library.user_presets():
		if String(preset.get("id", "")) == preset_id:
			return true
	return false
