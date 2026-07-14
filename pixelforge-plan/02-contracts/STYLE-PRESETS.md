# STYLE-PRESETS.md — StylePreset 退役说明

> Beta 0.7 不再定义或注册跨模块 StylePreset。旧 `style_version=1` 资源不是
> Project/Graph/Provider/Plugin v2 的合法输入，也不提供迁移、别名或运行时 adapter。

旧 StylePreset 把提示词、Provider hints、清洗、编辑器和地图默认值绑成一个全局
对象，造成多份优先级。v2 拆为：

- 生成正向前缀：`PROMPT-PRESETS.md`；
- 清洗完整设置：`CLEANUP-PRESETS.md`；
- 调色板：现有 PaletteRegistry 和项目 palette 资源；
- Pixel Editor：模块默认 `base_size=32`、palette `db32`；
- Board/Map Editor：模块默认 `tile_size=16`、palette `db32`。

项目删除 manifest.style_preset；Graph 删除 style_preset 节点、style 端口、
prompt_template/provider_hints 消费；插件删除 register_style_preset。旧 profile 只用于
重新制作六组内置新资源，不解析或迁移用户旧 JSON。

Project resource catalog/browser 把旧 style_preset kind 拆成 prompt_preset 与
cleanup_preset，palette kind 保留。onboarding 删除全局“Project style preset”步骤，
不写 manifest.style，也不新增替代弹窗。Pixel Editor 与 Board/Map Editor 的入口和
功能保留，只分别使用模块默认 32/db32 与 16/db32，不再读取项目全局 Style。

这次退役不授权删除、重设计或弱化调色板、Pixel Editor、Board/Map Editor、抠图、
切片、描边与其他独立工具。内置 palette JSON `{id,name,colors,source,license}`、颜色
校验、用户导入/删除和引用规则继续有效；相应唯一事实来源迁入 PaletteRegistry、
PROJECT-FORMAT 与 CLEANUP-PRESETS。
