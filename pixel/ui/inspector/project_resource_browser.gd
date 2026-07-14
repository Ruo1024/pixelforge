class_name PFProjectResourceBrowser
extends VBoxContainer

## Searchable project asset, split preset, and workflow entry point for canvas drops.

signal resource_activated(resource: Dictionary)

const Catalog := preload("res://services/project_resource_catalog.gd")
const Strings := preload("res://ui/shell/strings.gd")
const WorkflowTemplateService := preload("res://services/workflow_template_service.gd")

const KIND_ASSET := "project_asset"
const KIND_PROMPT_PRESET := "prompt_preset"
const KIND_CLEANUP_PRESET := "cleanup_preset"
const KIND_WORKFLOW := "workflow_template"

var _kind_option: OptionButton = null
var _search: LineEdit = null
var _category: OptionButton = null
var _list: ResourceItemList = null
var _empty_label: Label = null
var _workflow_actions: HBoxContainer = null
var _rename_dialog: ConfirmationDialog = null
var _rename_edit: LineEdit = null
var _delete_dialog: ConfirmationDialog = null


class ResourceItemList:
	extends ItemList

	func _get_drag_data(at_position: Vector2) -> Variant:
		var index := get_item_at_position(at_position, true)
		return drag_payload_for_index(index)

	func drag_payload_for_index(index: int) -> Variant:
		if index < 0 or index >= item_count:
			return null
		var data: Variant = get_item_metadata(index)
		return data.duplicate(true) if data is Dictionary else null


func _ready() -> void:
	name = "ProjectResourceBrowser"
	custom_minimum_size.y = 210
	var title := Label.new()
	title.name = "ResourceTitle"
	title.text = Strings.text("RESOURCE_BROWSER_TITLE")
	add_child(title)
	var filters := HBoxContainer.new()
	_kind_option = OptionButton.new()
	_kind_option.name = "ResourceKind"
	_kind_option.add_item(Strings.text("RESOURCE_KIND_ASSETS"))
	_kind_option.set_item_metadata(0, KIND_ASSET)
	_kind_option.add_item(Strings.text("RESOURCE_KIND_PROMPT_PRESETS"))
	_kind_option.set_item_metadata(1, KIND_PROMPT_PRESET)
	_kind_option.add_item(Strings.text("RESOURCE_KIND_CLEANUP_PRESETS"))
	_kind_option.set_item_metadata(2, KIND_CLEANUP_PRESET)
	_kind_option.add_item(Strings.text("RESOURCE_KIND_WORKFLOWS"))
	_kind_option.set_item_metadata(3, KIND_WORKFLOW)
	_kind_option.item_selected.connect(_on_kind_selected)
	filters.add_child(_kind_option)
	_category = OptionButton.new()
	_category.name = "ResourceCategory"
	_category.item_selected.connect(func(_index: int) -> void: _refresh())
	filters.add_child(_category)
	add_child(filters)
	_search = LineEdit.new()
	_search.name = "ResourceSearch"
	_search.placeholder_text = Strings.text("RESOURCE_SEARCH_PLACEHOLDER")
	_search.text_changed.connect(func(_query: String) -> void: _refresh())
	add_child(_search)
	_list = ResourceItemList.new()
	_list.name = "ResourceList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(func(_index: int) -> void: _sync_workflow_actions())
	add_child(_list)
	_build_workflow_actions()
	_empty_label = Label.new()
	_empty_label.name = "ResourceEmpty"
	_empty_label.text = Strings.text("RESOURCE_EMPTY")
	add_child(_empty_label)
	ProjectService.project_loaded.connect(func(_project: Variant) -> void: _refresh())
	EventBus.workflow_templates_changed.connect(_refresh)
	_refresh_categories()
	_refresh()


func get_visible_resources() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_list.item_count):
		result.append(Dictionary(_list.get_item_metadata(index)).duplicate(true))
	return result


func _refresh_categories() -> void:
	_category.clear()
	_category.add_item(Strings.text("RESOURCE_CATEGORY_ALL"))
	_category.set_item_metadata(0, "")
	var kind := String(_kind_option.get_item_metadata(_kind_option.selected))
	var categories := ["builtin", "user"] if kind == KIND_WORKFLOW else []
	if kind == KIND_ASSET:
		categories = ["imported", "generated"]
	for category in categories:
		var key_prefix := "RESOURCE_SOURCE_" if kind == KIND_WORKFLOW else "RESOURCE_ORIGIN_"
		_category.add_item(Strings.text("%s%s" % [key_prefix, category.to_upper()]))
		_category.set_item_metadata(_category.item_count - 1, category)


func _on_kind_selected(_index: int) -> void:
	_refresh_categories()
	_refresh()


func _refresh() -> void:
	if _list == null:
		return
	_list.clear()
	var kind := String(_kind_option.get_item_metadata(_kind_option.selected))
	var category := String(_category.get_item_metadata(_category.selected))
	var resources: Array[Dictionary]
	if kind == KIND_WORKFLOW:
		resources = Catalog.search_workflows(_search.text, category)
	elif kind == KIND_PROMPT_PRESET:
		resources = Catalog.search_prompt_presets(_search.text)
	elif kind == KIND_CLEANUP_PRESET:
		resources = Catalog.search_cleanup_presets(_search.text)
	else:
		resources = Catalog.search_assets(_search.text, category)
	for resource in resources:
		var available := bool(resource.get("available", true))
		var label := String(resource.get("name", resource.get("id", "")))
		if not available:
			label = Strings.text("RESOURCE_UNAVAILABLE_FORMAT") % label
		_list.add_item(label)
		var data := resource.duplicate(true)
		data["kind"] = kind
		_list.set_item_metadata(_list.item_count - 1, data)
		_list.set_item_disabled(_list.item_count - 1, not available)
	_empty_label.visible = resources.is_empty()


func _on_item_activated(index: int) -> void:
	if index < 0 or _list.is_item_disabled(index):
		return
	var resource: Variant = _list.get_item_metadata(index)
	if resource is Dictionary:
		resource_activated.emit(resource.duplicate(true))


func _build_workflow_actions() -> void:
	_workflow_actions = HBoxContainer.new()
	_workflow_actions.name = "WorkflowActions"
	for spec in [
		["WorkflowRename", "ACTION_RENAME_WORKFLOW", _show_rename_workflow],
		["WorkflowDelete", "ACTION_DELETE_WORKFLOW", _show_delete_workflow],
	]:
		var button := Button.new()
		button.name = String(spec[0])
		button.text = Strings.text(String(spec[1]))
		button.pressed.connect(spec[2])
		_workflow_actions.add_child(button)
	add_child(_workflow_actions)
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.name = "WorkflowRenameDialog"
	_rename_dialog.title = Strings.text("DIALOG_RENAME_WORKFLOW")
	_rename_edit = LineEdit.new()
	_rename_edit.name = "WorkflowName"
	_rename_dialog.add_child(_rename_edit)
	_rename_dialog.confirmed.connect(_rename_selected_workflow)
	add_child(_rename_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.name = "WorkflowDeleteDialog"
	_delete_dialog.title = Strings.text("DIALOG_DELETE_WORKFLOW")
	_delete_dialog.confirmed.connect(_delete_selected_workflow)
	add_child(_delete_dialog)
	_sync_workflow_actions()


func _selected_user_workflow() -> Dictionary:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return {}
	var value: Variant = _list.get_item_metadata(selected[0])
	if not (value is Dictionary) or String(value.get("source", "")) != "user":
		return {}
	return value


func _sync_workflow_actions() -> void:
	if _workflow_actions != null:
		_workflow_actions.visible = not _selected_user_workflow().is_empty()


func _show_rename_workflow() -> void:
	var workflow := _selected_user_workflow()
	if workflow.is_empty():
		return
	_rename_edit.text = String(workflow.get("name", ""))
	_rename_dialog.popup_centered(Vector2i(420, 150))


func _rename_selected_workflow() -> void:
	var workflow := _selected_user_workflow()
	if workflow.is_empty() or _rename_edit.text.strip_edges().is_empty():
		return
	var result := WorkflowTemplateService.rename_template(
		String(workflow.get("id", "")), _rename_edit.text
	)
	if bool(result.get("ok", false)):
		EventBus.workflow_templates_changed.emit()


func _show_delete_workflow() -> void:
	var workflow := _selected_user_workflow()
	if workflow.is_empty():
		return
	_delete_dialog.dialog_text = (
		Strings.text("DIALOG_DELETE_WORKFLOW_FORMAT") % String(workflow.get("name", ""))
	)
	_delete_dialog.popup_centered(Vector2i(420, 180))


func _delete_selected_workflow() -> void:
	var workflow := _selected_user_workflow()
	if workflow.is_empty():
		return
	if WorkflowTemplateService.delete_template(String(workflow.get("id", ""))) == OK:
		EventBus.workflow_templates_changed.emit()
