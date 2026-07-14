class_name PFV1OnboardingDialog
extends ConfirmationDialog

## First-launch setup for optional Provider configuration and sample content.

signal setup_completed(open_provider_settings: bool, create_sample: bool)

const Strings := preload("res://ui/shell/strings.gd")
var _provider_setup: CheckButton = null
var _sample: CheckButton = null


func _ready() -> void:
	_build_ui()
	_refresh_text("", "")
	confirmed.connect(_apply)
	LocalizationService.language_changed.connect(_refresh_text)


func show_setup() -> void:
	reset_size()
	popup_centered()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "Content"
	root.custom_minimum_size.x = 440
	root.size.x = 440
	get_label().get_parent().add_child(root)
	var intro := Label.new()
	intro.name = "Intro"
	intro.text = Strings.V1_ONBOARDING_INTRO
	root.add_child(intro)
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
	SettingsService.set_setting("onboarding", "v1_complete", true)
	setup_completed.emit(_provider_setup.button_pressed, _sample.button_pressed)


func _refresh_text(_preference: String, _locale: String) -> void:
	title = Strings.text("ONBOARDING_TITLE")
	ok_button_text = Strings.text("ONBOARDING_START")
	cancel_button_text = Strings.text("ACTION_CANCEL")
	get_node("Content/Intro").text = Strings.text("ONBOARDING_INTRO")
	_provider_setup.text = Strings.text("ONBOARDING_PROVIDER")
	_sample.text = Strings.text("ONBOARDING_SAMPLE")
