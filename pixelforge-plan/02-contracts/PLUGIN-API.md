# PLUGIN-API.md — 插件系统 v2 契约

> manifest/API `api_version=2`。版本含义是注册面、Provider 与 Graph schema 的
> breaking revision，不是签名或信任等级。v1 返回 unsupported_plugin_api_version
> 并隔离；不提供 adapter、别名或按方法存在性猜版本。

## 1. 插件形态与 manifest

插件仍是开发目录或 `.pck`：

```text
my_plugin/plugin.json
my_plugin/main.gd
```

```json
{
  "id":"example_plugin", "name":"Example", "version":"1.0.0",
  "api_version":2, "min_app_version":"0.7.0", "entry":"main.gd",
  "permissions":["network"], "description":"", "author":""
}
```

id 为唯一 snake_case 前缀。api_version!=2 的插件在入口执行前隔离，不得注册任何
节点、Provider、资源或菜单。未知/坏清单结构化报错，不能拖垮应用启动。

## 2. PFPlugin 与注册面

```gdscript
class_name MyPlugin extends PFPlugin

func _enter_app(api: PFPluginAPI) -> void:
    api.register_node_type("example.node", ExampleNode)
    api.register_provider(ExampleProvider.new())

func _exit_app() -> void:
    pass
```

PFPluginAPI v2 的完整注册面：

```text
register_node_type
register_provider
register_pipeline_step
register_palette
register_prompt_preset
register_cleanup_preset
register_menu_item
register_exporter
```

删除 register_style_preset。除该替换外，v1 的无关能力和卸载自动反注册行为原样
保留。PromptPreset/CleanupPreset 必须分别通过对应契约校验；Graph 节点遵守
graph_version=2；Provider 还必须独立通过 PROVIDER-API 的 api_version=2 门，插件
版本合格不代表 Provider 自动合格。

所有插件提供的 node/provider/preset schema 都必须先经唯一
SchemaTextResolver.validate_schema 双语验证；插件 UI 只保存 `*_key`，不得用 raw
label/help/description 或绕过 resolver 动态访问 catalog。

Beta 0.7 只迁移默认旅程实际加载的内置 OpenAI Image 与 RetroDiffusion。ComfyUI
和其他实验后端保持禁用/不注册；不得为了通过门禁扩建、伪迁移或改变验收范围。

## 3. 加载、冲突与失败隔离

- 开发态从 `user://plugins/{id}/` 加载 GDScript；
- 分发态先 `ProjectSettings.load_resource_pack` 再按 entry 加载；
- PCK 路径必须以 `res://plugins/{id}/` 为根，不能覆盖主程序；
- 本版只支持 GDScript；C#/GDExtension 不支持；
- 单插件加载、注册或退出失败要安全记录和提示，其他插件与主程序继续；
- 内置插件从 res:// 加载，但走相同 `_enter_app(api)` 和注册账本；CI 必须证明移除
  任一内置插件后主程序仍能启动。

## 4. 安全模型

GDScript 没有真沙箱。安装第三方插件必须展示 permissions 与本地化警告“插件可执行
任意代码，只安装可信来源”。声明只是告知，不冒充强制隔离；日志不得泄露插件获得
的用户数据或凭据。

签名、官方市场和真正沙箱都是未排期的未来能力。Beta 0.7 不实现签名、不声称
api_version=2 插件可信，也不做“伪沙箱”。API 版本不能因未实现签名而降回 1。
