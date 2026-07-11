class_name PFV1OnboardingDialog
extends ConfirmationDialog

## First-launch v1 setup for style choice, optional Provider setup, and sample content.

signal setup_completed(open_provider_settings: bool, create_sample: bool)

const Strings := preload("res://ui/shell/strings.gd")

const PRESETS := [
	["16-bit / DB32", "res://assets/presets/preset_16bit_db32.json"],
	["Game Boy", "res://assets/presets/preset_gb.json"],
	["NES", "res://assets/presets/preset_nes.json"],
	["Hi-bit", "res://assets/presets/preset_hibit.json"],
	["1-bit", "res://assets/presets/preset_1bit.json"],
	["HD-2D Prop", "res://assets/presets/preset_hd2d_prop.json"],
]

var _preset: OptionButton = null
var _provider_setup: CheckButton = null
var _sample: CheckButton = null


func _ready() -> void:
	title = Strings.DIALOG_V1_ONBOARDING
	ok_button_text = Strings.V1_ONBOARDING_START
	_build_ui()
	confirmed.connect(_apply)


func show_setup() -> void:
	popup_centered()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Content"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var intro := Label.new()
	intro.name = "Intro"
	intro.text = Strings.V1_ONBOARDING_INTRO
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(intro)
	var preset_label := Label.new()
	preset_label.name = "PresetLabel"
	preset_label.text = Strings.V1_ONBOARDING_STYLE
	root.add_child(preset_label)
	_preset = OptionButton.new()
	_preset.name = "Preset"
	for spec in PRESETS:
		_preset.add_item(String(spec[0]))
		_preset.set_item_metadata(_preset.item_count - 1, spec[1])
	root.add_child(_preset)
	_provider_setup = CheckButton.new()
	_provider_setup.name = "ProviderSetup"
	_provider_setup.text = Strings.V1_ONBOARDING_PROVIDER
	root.add_child(_provider_setup)
	_sample = CheckButton.new()
	_sample.name = "CreateSample"
	_sample.text = Strings.V1_ONBOARDING_SAMPLE
	_sample.button_pressed = true
	root.add_child(_sample)


func _apply() -> void:
	var path := String(_preset.get_item_metadata(_preset.selected))
	var preset: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if preset is Dictionary:
		ProjectService.current_project.manifest["style_preset"] = preset
		ProjectService.mark_dirty()
	SettingsService.set_setting("onboarding", "v1_complete", true)
	setup_completed.emit(_provider_setup.button_pressed, _sample.button_pressed)
