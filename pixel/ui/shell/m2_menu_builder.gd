class_name PFM2MenuBuilder
extends RefCounted

## M2 工作区菜单构建器；菜单 ID 仍由 controller 单点定义，本类只负责本地化呈现。


static func populate_file(
	button: MenuButton, popup: PopupMenu, controller: Node, add_graph_submenu: Callable
) -> void:
	LocalizationService.bind_control_text(button, "MENU_FILE")
	LocalizationService.add_popup_item(
		popup, "MENU_IMPORT_IMAGES", controller.FILE_MENU_IMPORT_IMAGES
	)
	LocalizationService.add_popup_item(
		popup, "ACTION_FOCUS_LAST_IMPORT", controller.FILE_MENU_FOCUS_LAST_IMPORT
	)
	LocalizationService.add_popup_item(
		popup, "ACTION_RETRY_IMPORT", controller.FILE_MENU_RETRY_IMPORT
	)
	popup.add_separator()
	LocalizationService.add_popup_item(
		popup, "MENU_GENERATE_MOCK_BATCH", controller.FILE_MENU_GENERATE_MOCK_BATCH
	)
	LocalizationService.add_popup_item(
		popup, "MENU_PROVIDER_SETTINGS", controller.FILE_MENU_PROVIDER_SETTINGS
	)
	LocalizationService.add_popup_item(
		popup, "MENU_CONFIGURE_OPENAI_SESSION", controller.FILE_MENU_CONFIGURE_OPENAI_SESSION
	)
	LocalizationService.add_popup_item(
		popup, "MENU_GENERATE_OPENAI_BATCH", controller.FILE_MENU_GENERATE_OPENAI_BATCH
	)
	LocalizationService.add_popup_item(
		popup, "MENU_RUN_SELECTED_GRAPH", controller.FILE_MENU_RUN_SELECTED_GRAPH
	)
	add_graph_submenu.call(popup)
	LocalizationService.add_popup_item(
		popup, "MENU_EDIT_SELECTED_GRAPH_NODE", controller.FILE_MENU_EDIT_SELECTED_GRAPH_NODE
	)
	LocalizationService.add_popup_item(popup, "MENU_OPEN_BOARD", controller.FILE_MENU_OPEN_BOARD)
	LocalizationService.add_popup_item(
		popup, "MENU_OPEN_PIXEL_EDITOR", controller.FILE_MENU_OPEN_PIXEL_EDITOR
	)
	LocalizationService.add_popup_item(
		popup, "MENU_PLUGIN_MANAGER", controller.FILE_MENU_PLUGIN_MANAGER
	)
	popup.add_separator()
	LocalizationService.add_popup_item(popup, "ACTION_NEW", controller.FILE_MENU_NEW)
	LocalizationService.add_popup_item(popup, "ACTION_OPEN", controller.FILE_MENU_OPEN)
	LocalizationService.add_popup_item(popup, "ACTION_SAVE", controller.FILE_MENU_SAVE)


static func populate_batch(popup: PopupMenu, controller: Node) -> void:
	_add_group(
		popup,
		[
			["BATCH_ACTION_CLEANUP", controller.BATCH_MENU_CLEANUP],
			["BATCH_ACTION_MATTE", controller.BATCH_MENU_MATTE],
			["BATCH_ACTION_OUTLINE", controller.BATCH_MENU_OUTLINE],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_MARK_KEEP", controller.BATCH_MENU_MARK_KEEP],
			["BATCH_ACTION_MARK_REJECT", controller.BATCH_MENU_MARK_REJECT],
			["BATCH_ACTION_MARK_FLAG", controller.BATCH_MENU_MARK_FLAG],
			["BATCH_ACTION_CLEAR_MARK", controller.BATCH_MENU_CLEAR_MARK],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_SHOW_ALL", controller.BATCH_MENU_FILTER_ALL],
			["BATCH_ACTION_SHOW_KEEP", controller.BATCH_MENU_FILTER_KEEP],
			["BATCH_ACTION_SHOW_PENDING", controller.BATCH_MENU_FILTER_PENDING],
			["BATCH_ACTION_SHOW_REJECT", controller.BATCH_MENU_FILTER_REJECT],
			["BATCH_ACTION_SHOW_FLAG", controller.BATCH_MENU_FILTER_FLAG],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_LAYOUT_CONTACT", controller.BATCH_MENU_LAYOUT_CONTACT],
			["BATCH_ACTION_LAYOUT_FOCUS", controller.BATCH_MENU_LAYOUT_FOCUS],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_COMPARE_CURRENT", controller.BATCH_MENU_COMPARE_CURRENT],
			["BATCH_ACTION_COMPARE_PREVIOUS", controller.BATCH_MENU_COMPARE_PREVIOUS],
			["BATCH_ACTION_COMPARE_SPLIT", controller.BATCH_MENU_COMPARE_SPLIT],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_SPLIT_KEEP", controller.BATCH_MENU_SPLIT_KEEP],
			["BATCH_ACTION_SPLIT", controller.BATCH_MENU_SPLIT],
		]
	)
	_add_group(
		popup,
		[
			["BATCH_ACTION_EXPORT", controller.BATCH_MENU_EXPORT],
			["BATCH_ACTION_EDIT", controller.BATCH_MENU_EDIT],
		],
		false
	)


static func _add_group(popup: PopupMenu, specs: Array, separator_after: bool = true) -> void:
	for spec in specs:
		LocalizationService.add_popup_item(popup, String(spec[0]), int(spec[1]))
	if separator_after:
		popup.add_separator()
