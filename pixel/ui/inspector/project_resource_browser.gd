class_name PFProjectResourceBrowser
extends VBoxContainer

## Searchable project-local asset and built-in style entry point for canvas drops.

signal resource_activated(resource: Dictionary)

const Catalog := preload("res://services/project_resource_catalog.gd")
const Strings := preload("res://ui/shell/strings.gd")

const KIND_ASSET := "project_asset"
const KIND_STYLE := "style_preset"

var _kind_option: OptionButton = null
var _search: LineEdit = null
var _category: OptionButton = null
var _list: ResourceItemList = null
var _empty_label: Label = null


class ResourceItemList:
	extends ItemList

	func _get_drag_data(at_position: Vector2) -> Variant:
		var index := get_item_at_position(at_position, true)
		if index < 0:
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
	_kind_option.add_item(Strings.text("RESOURCE_KIND_STYLES"))
	_kind_option.set_item_metadata(1, KIND_STYLE)
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
	add_child(_list)
	_empty_label = Label.new()
	_empty_label.name = "ResourceEmpty"
	_empty_label.text = Strings.text("RESOURCE_EMPTY")
	add_child(_empty_label)
	ProjectService.project_loaded.connect(func(_project: Variant) -> void: _refresh())
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
	var categories := (
		["8bit", "16bit", "hibit", "hd2d", "1bit", "gb"]
		if kind == KIND_STYLE
		else ["imported", "generated"]
	)
	for category in categories:
		var key_prefix := "RESOURCE_TIER_" if kind == KIND_STYLE else "RESOURCE_ORIGIN_"
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
	if kind == KIND_STYLE:
		resources = Catalog.search_styles(_search.text, category)
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
