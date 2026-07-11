class_name PFOpenAISessionDialog
extends ConfirmationDialog

## M4-V1 会话级凭据入口；关闭或提交后立即清空控件，不持久化。

signal session_configured(api_key: String)

const Strings := preload("res://ui/shell/strings.gd")
const DIALOG_WIDTH := 520
const DIALOG_HEIGHT := 220
const CONTROL_HEIGHT := 32
const ROOT_SEPARATION := 10

var _api_key_edit: LineEdit = null


func _ready() -> void:
	title = Strings.DIALOG_OPENAI_SESSION_TITLE
	ok_button_text = Strings.ACTION_USE_FOR_SESSION
	cancel_button_text = Strings.DIALOG_CANCEL
	min_size = Vector2i(DIALOG_WIDTH, DIALOG_HEIGHT)
	var root := VBoxContainer.new()
	root.name = "Content"
	root.add_theme_constant_override("separation", ROOT_SEPARATION)
	add_child(root)
	var explanation := Label.new()
	explanation.text = Strings.OPENAI_SESSION_EXPLANATION
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)
	_api_key_edit = LineEdit.new()
	_api_key_edit.name = "ApiKey"
	_api_key_edit.secret = true
	_api_key_edit.placeholder_text = Strings.OPENAI_SESSION_PLACEHOLDER
	_api_key_edit.custom_minimum_size = Vector2.DOWN * CONTROL_HEIGHT
	root.add_child(_api_key_edit)
	confirmed.connect(_submit)
	canceled.connect(clear_secret)
	close_requested.connect(clear_secret)


func popup_for_session() -> void:
	clear_secret()
	popup_centered()
	_api_key_edit.grab_focus.call_deferred()


func set_api_key_for_test(value: String) -> void:
	_api_key_edit.text = value


func is_secret_input() -> bool:
	return _api_key_edit.secret


func clear_secret() -> void:
	if _api_key_edit != null:
		_api_key_edit.text = ""


func _submit() -> void:
	var value := _api_key_edit.text.strip_edges()
	clear_secret()
	if not value.is_empty():
		session_configured.emit(value)
