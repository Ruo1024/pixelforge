# PixelForge 本地工作流模板契约

> schema: `pixelforge.workflow-template`
>
> version: `1`

## 1. 边界

工作流模板是用户显式保存到本机用户数据目录的无素材图片段。它不是项目、剪贴板、插件包、ComfyUI 工作流或版本历史，不同步、不分享、不携带凭据和图片。

模板只保存一个显式 frame 的成员、成员间内部连线、相对布局与 frame 外观。指向 frame 外部的边不保存。插入时所有 node、frame 与 canvas item ID 必须重映射，并以一次 Undo 放到指定锚点。

## 2. 顶层结构

```json
{
  "schema": "pixelforge.workflow-template",
  "version": 1,
  "id": "uuid",
  "name": "Reference batch",
  "description": "Optional short purpose",
  "created_at": "RFC3339 UTC",
  "nodes": [],
  "edges": [],
  "frame": {"label": "Stage", "position": [0, 0], "size": [1200, 700]},
  "requirements": {"model_ids": [], "reference_slots": 0}
}
```

`nodes[].position` 相对 `frame.position`。`edges[]` 沿用 `GRAPH-SCHEMA.md` 的 `from/to` 二元组，但端点只能引用模板内节点。

## 3. Fail-closed 白名单

允许节点与参数：

| 节点 | 允许参数 |
|---|---|
| `text_prompt` | `text` |
| `object_list` | `items`, `rows` |
| `style_preset` | `preset_ref`, `preset` |
| `image_input` | `asset_id`，保存时强制清空 |
| `reference_set` | `asset_ids`，保存时强制清空 |
| `size_spec` | `width`, `height`, `per_subject` |
| `ai_generate` | `provider_id`, `model_id`, `batch_size`, `seed` |
| `batch` | `label`；结果、审阅和运行状态强制清空 |

节点类型、参数键或边端口不在白名单时拒绝保存并返回结构化问题。幽灵、插件节点、历史 Comfy 节点一律拒绝。自定义 StylePreset 必须是 `STYLE-PRESETS.md` 可验证的完整内嵌数据。

所有字典递归禁止键名包含：`api_key`、`authorization`、`credential`、`header`、`password`、`response`、`secret`、`token`。同时禁止绝对路径、`run_state`、结果 `asset_ids`、审阅状态、完整 Provider 响应和未知字段。

## 4. 结构化输入

`object_list.params.rows` 是可选稳定行数组：

```json
{"id": "uuid", "text": "small tower", "count": 4, "enabled": true}
```

- `rows` 存在后是执行真相；旧 `items` 仅在无 rows 时按非空行转换；
- `count >= 1`，由该行唯一决定候选总数；
- Provider `max_batch` 只拆请求，不改变总数；
- `ai_generate.batch_size` 只服务单条 prompt 或旧 items；`size_spec.per_subject` 仅兼容旧项目；
- 运行记录 `source_node_id` 与稳定 `source_row_id`，不得依赖行索引。

## 5. 存储与恢复

模板文件名使用模板 UUID，JSON 原子写入 `user://workflow_templates/`。读取时逐文件验证；损坏或未来版本文件跳过并返回警告，不阻止其他模板。重命名原子改写同一模板；另存为生成新 ID；删除模板不影响已插入实例。

模型 ID 允许保留。当前环境缺失模型时实例仍可插入，但生成节点必须显示可修复警告，禁止静默替换模型。
