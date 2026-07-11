class_name PFLanguageSelector
extends VBoxContainer

## Reusable language preference control. Consumers can embed it in any settings surface.

const Strings := preload("res://ui/shell/strings.gd")

var _label := Label.new()
var _options := OptionButton.new()
var _note := Label.new()


func _ready() -> void:
	add_child(_label)
	add_child(_options)
	add_child(_note)
	_options.item_selected.connect(_on_item_selected)
	LocalizationService.language_changed.connect(_on_language_changed)
	_rebuild(LocalizationService.current_preference)


func _rebuild(preference: String) -> void:
	_label.text = Strings.text("LANGUAGE_LABEL")
	_note.text = Strings.text("LANGUAGE_APPLY_NOTE")
	_options.clear()
	_add_option(Strings.text("LANGUAGE_AUTO"), "auto")
	_add_option(Strings.text("LANGUAGE_ENGLISH"), "en")
	_add_option(Strings.text("LANGUAGE_SIMPLIFIED_CHINESE"), "zh_CN")
	for index in range(_options.item_count):
		if String(_options.get_item_metadata(index)) == preference:
			_options.select(index)
			break


func _add_option(label: String, preference: String) -> void:
	_options.add_item(label)
	_options.set_item_metadata(_options.item_count - 1, preference)


func _on_item_selected(index: int) -> void:
	LocalizationService.set_language(String(_options.get_item_metadata(index)))


func _on_language_changed(preference: String, _locale: String) -> void:
	_rebuild(preference)
