class_name PFContractErrorText
extends RefCounted

## Localizes the six Beta 0.7 hard-cut version errors without exposing raw error codes.

const KEY_BY_CODE := {
	"unsupported_project_version": "CONTRACT_ERROR_UNSUPPORTED_PROJECT_VERSION",
	"unsupported_graph_version": "CONTRACT_ERROR_UNSUPPORTED_GRAPH_VERSION",
	"unsupported_provider_api_version": "CONTRACT_ERROR_UNSUPPORTED_PROVIDER_VERSION",
	"unsupported_plugin_api_version": "CONTRACT_ERROR_UNSUPPORTED_PLUGIN_VERSION",
	"unsupported_template_version": "CONTRACT_ERROR_UNSUPPORTED_TEMPLATE_VERSION",
	"unsupported_clipboard_version": "CONTRACT_ERROR_UNSUPPORTED_CLIPBOARD_VERSION",
}


static func text(code: String, fallback: String = "") -> String:
	match code:
		"unsupported_project_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_PROJECT_VERSION")
		"unsupported_graph_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_GRAPH_VERSION")
		"unsupported_provider_api_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_PROVIDER_VERSION")
		"unsupported_plugin_api_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_PLUGIN_VERSION")
		"unsupported_template_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_TEMPLATE_VERSION")
		"unsupported_clipboard_version":
			return LocalizationService.text("CONTRACT_ERROR_UNSUPPORTED_CLIPBOARD_VERSION")
		_:
			return fallback
