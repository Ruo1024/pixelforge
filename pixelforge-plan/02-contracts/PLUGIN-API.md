# PLUGIN-API.md — 插件系统契约

> api_version = 1（M7 实现，但 M0 起所有内部模块按此设计——内置 provider 即插件）。

## 1. 插件形态

一个插件 = 一个目录（开发态）或一个 `.pck` 包（分发态）：

```
my_plugin/
├── plugin.json        # 清单（必须）
├── main.gd            # 入口（必须，实现 PFPlugin 接口）
└── ...                # 任意脚本/资源
```

```json
// plugin.json
{
  "id": "comfyui_bridge",          // 唯一，snake_case，作为节点前缀
  "name": "ComfyUI Bridge",
  "version": "1.0.0",
  "api_version": 1,                 // 目标主程序插件 API 版本
  "min_app_version": "0.9.0",
  "entry": "main.gd",
  "permissions": ["network", "filesystem_read"],   // 声明式权限（v1 仅展示给用户，不强制沙箱）
  "description": "...",
  "author": "..."
}
```

## 2. 入口接口

```gdscript
# 插件 main.gd 必须 extends PFPlugin
class_name MyPlugin extends PFPlugin

func _enter_app(api: PFPluginAPI) -> void:
    # 注册能力，全部通过 api 对象，禁止直接触碰主程序内部
    api.register_node_type("comfyui.run_workflow", RunWorkflowNode)
    api.register_provider(ComfyUIProvider.new())
    api.register_menu_item("扩展/ComfyUI 设置", _open_settings)
    api.register_pipeline_step("my_custom_filter", MyFilter)   # 清洗管线自定义步骤

func _exit_app() -> void:
    pass   # api 自动反注册本插件注册的一切；这里只清理插件自有资源
```

`PFPluginAPI` 暴露的注册面（v1 全集）：`register_node_type / register_provider / register_pipeline_step / register_palette / register_style_preset / register_menu_item / register_exporter`。每项注册自动记账，卸载时反向清理。

## 3. 加载机制（技术路线，2026-06 调研结论）

- **开发态**：`user://plugins/{id}/` 目录直接 `load("...gd")`。GDScript 运行时加载在导出后的程序中可用（与 EditorPlugin 不同——后者仅编辑器内可用，**不能**作为本产品插件机制）。
- **分发态**：`ProjectSettings.load_resource_pack("user://plugins/{id}.pck")` 后按清单 entry 加载。注意：仅 GDScript 插件受支持；C#/GDExtension 插件 v1 不支持（调研确认 C# 在 PCK 运行时加载有缺陷）。
- **冲突规避**：PCK 内资源路径必须以 `res://plugins/{id}/` 为根（打包脚本强制），避免覆盖主程序资源。
- **失败隔离**：单个插件加载抛错 → 记日志、UI 提示、跳过，不得拖垮主程序启动。

## 4. 安全模型（v1 务实方案）

GDScript 无真沙箱。v1 采取：安装时向用户展示 permissions 声明 + "插件可执行任意代码，请只安装可信来源"警告；插件目录与官方插件市场（远期）签名校验留作 v2。**任务卡中禁止实现"伪沙箱"给用户虚假安全感。**

## 5. 内置插件的特殊性

`plugins/` 目录下的出厂插件随主程序打包（res:// 内），跳过 PCK 加载但走完全相同的 `_enter_app(api)` 流程。CI 中有测试保证：把任一内置插件移出后主程序仍能启动（验证解耦真实性）。
