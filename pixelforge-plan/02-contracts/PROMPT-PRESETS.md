# PROMPT-PRESETS.md — PromptPreset v1 契约

> `prompt_preset_version=1`。PromptPreset 只提供正向提示词前缀；不携带 negative
> prompt、palette、尺寸、描边、抖动、透视、Provider 映射、编辑器或地图设置。

## 1. Schema

```json
{
  "prompt_preset_version":1,
  "id":"prompt-hibit",
  "name_key":"PROMPT_PRESET_HIBIT",
  "prefix":"high detail pixel art, controlled palette, modern hi-bit game asset"
}
```

id 必须非空且唯一。内置 preset 必须只有 name_key；用户 preset 必须只有 name；
两者同时有或同时无均失败。prefix 是普通 String，不解释 `{subject}`、
`{style_tags}`、`{size_hint}` 或其他占位符。用户名称和 prefix 按用户文本保存；内置
名称只由集中 i18n catalog 解析。

Preset registry 注册时必须调用唯一 SchemaTextResolver.validate_schema；name_key 在
English/简中必须存在且非空。普通 UI 不得动态直取 catalog key。

选择时把完整 preset snapshot 写入 prompt_preset node.params.preset。生成协调器只
读取 snapshot.prefix 并按 Graph 规则拼接最终 prompt；Provider 不读取 preset。
新节点默认嵌入 prompt-16bit-db32，但项目没有全局默认字段。

## 2. 用户库与卡片编辑

预设列表必须标明 builtin、plugin、user 三类来源。builtin 与 plugin 永远只读；
用户点击编辑时先创建具有新 id 的 user 副本，再允许改名或改 prefix。user 预设保存在
本地用户设置中，不写入项目 manifest；支持新建、复制、重命名、编辑、保存和删除。

切换预设时若编辑器存在未保存内容，必须提供保存、放弃和取消三种结果。保存后再切换
只把目标预设作为一次节点参数提交；放弃不改用户库；取消保留焦点和草稿。删除用户库
条目不得改写任何已存在节点，节点继续以完整 snapshot 重放，并可再次复制为用户预设。
卡片必须提供 prefix 文本复制动作。

运行时只读取节点 snapshot：非空 prefix 在自由提示词之前注入一次，空 prefix 完全省略。
视觉自动换行不得修改 prefix 字符串。

## 3. 六个内置完整资源

每个 JSON 必须逐字保存自己的完整对象，不使用 based_on、继承或运行时拼接：

| id | name_key | prefix |
|---|---|---|
| prompt-hibit | PROMPT_PRESET_HIBIT | high detail pixel art, controlled palette, modern hi-bit game asset |
| prompt-gb | PROMPT_PRESET_GB | Game Boy pixel art, four color palette, monochrome handheld sprite |
| prompt-hd2d-prop | PROMPT_PRESET_HD2D_PROP | HD-2D pixel prop, crisp sprite, high resolution pixel prop |
| prompt-1bit | PROMPT_PRESET_1BIT | 1-bit pixel art, black and white, binary monochrome sprite |
| prompt-nes | PROMPT_PRESET_NES | NES pixel art sprite, limited hardware palette, 8-bit console sprite |
| prompt-16bit-db32 | PROMPT_PRESET_16BIT_DB32 | pixel art, 16-bit style, limited palette, clean pixel grid, retro game asset, DawnBringer palette |

卡片用户可见名固定为中文“风格提示词”、English “Style Prompt”。尺寸和通用画布
行为见 GRAPH-SCHEMA/PROJECT-FORMAT。
