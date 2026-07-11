class_name PFComfyUIBridgePlugin
extends PFPlugin

const ProviderScript := preload("res://plugins/bridge_comfyui/comfyui_provider.gd")
const WorkflowNodeScript := preload("res://plugins/bridge_comfyui/comfyui_workflow_node.gd")


func _enter_app(api: Variant) -> void:
	api.register_provider(ProviderScript.new())
	api.register_node_type("comfyui.run_workflow", WorkflowNodeScript)
