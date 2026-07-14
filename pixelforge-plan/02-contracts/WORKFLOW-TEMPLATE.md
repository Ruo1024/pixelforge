# WORKFLOW-TEMPLATE.md — 本地工作流模板 v2 契约

> schema=`pixelforge.workflow-template`，version=2。v1 返回
> `unsupported_template_version`，不迁移、不猜字段。

## 1. 边界与结构

模板是用户显式保存到 `user://workflow_templates/` 的无图片 Graph 片段。它不是
项目、Clipboard、插件、ComfyUI workflow 或历史；不携带凭据、运行记录和素材。

```json
{
  "schema":"pixelforge.workflow-template", "version":2,
  "id":"uuid", "name":"Reference continuation", "description":"",
  "created_at":"RFC3339 UTC",
  "nodes":[], "edges":[],
  "frame":{"label":"Stage","position":[0,0],"size":[1200,700]},
  "requirements":{"model_ids":[],"reference_slots":0},
  "palette_requirements":[]
}
```

只保存一个显式 frame 的成员、内部边、相对布局与 frame 外观。外部边不保存。
nodes.position 相对 frame.position；端点必须属于模板。插入时所有 node/frame/
canvas item id 重映射，以一次 Undo 放到锚点。display_title/size/collapsed 沿用
PROJECT-FORMAT；locked 不保存，新实例默认未锁。未知字段 fail closed。

## 2. 节点与参数白名单

只允许 Beta 0.7 主路径八种节点：

| type | 允许 params |
|---|---|
| text_prompt | text |
| object_list | rows |
| prompt_preset | preset |
| image_input | asset_id；保存时清空 |
| reference_set | asset_ids；保存时清空 |
| ai_generate | provider_id, model_id, target_width, target_height, batch_size, seed, extra |
| pixel_cleanup | preset_id, settings |
| batch | label |

`size_spec/style_preset`、幽灵、插件和实验节点全部拒绝。object_list rows 严格沿用
Graph v2，不读 items。pixel_cleanup 不保存 target_size 或 palette colors。
ai_generate.extra 只保留当前 model descriptor 中 `template_safe=true` 的键。

所有字典递归禁止键名含 api_key/authorization/credential/header/password/response/
secret/token；禁止绝对路径、run/task/request/progress/error、result_slots、input
snapshots、provider response 和未知参数。失败返回结构化问题，模板不写盘。

模板中的 batch 即使输入对象含旧运行字段，规范输出也必须固定为：

```json
{
  "label":"原规范化 label", "role":"standalone", "source_node_id":"",
  "source_run_id":"", "input_snapshots":{},
  "request_records":[], "result_slots":[]
}
```

普通模板不预建历史、结果或 Retry 输入；实际运行再创建 Output。

## 3. Palette requirements

顶层始终保存 palette_requirements，按 palette_id 升序；无需求时写 `[]`：

```json
[{"palette_id":"custom_farm_12","content_sha256":"64-char-lowercase-hex"}]
```

只扫描 `pixel_cleanup.settings.quantize.enabled=true && mode=fixed_palette`。每个不同
palette id 恰一项。hash 使用 CLEANUP-PRESETS 定义的规范 RGBA8 颜色算法。保存时
palette 缺失返回 missing_template_palette；同 id 内容冲突属于内部校验失败。

插入前在目标 PaletteRegistry 原子验证：缺失返回 missing_template_palette；hash
不同返回 template_palette_mismatch；任一失败不得部分插入。模板不保存 colors、
不导入或覆盖 palette、不 fallback db32；用户须先通过现有导入入口添加资源。

## 4. 四个内置模板

内置模板直接以 v2 完整资源保存，显式 size 和 palette_requirements：

1. 基础生成：`text_prompt → ai_generate`，运行时创建 Output；
2. 批量对象生成：`object_list → ai_generate`，不是默认入口；
3. Reference continuation：`text_prompt → ai_generate`，并有
   `image_input.assets → ai_generate.references`；text/asset 初始为空且显示本地化提示；
4. 生成并清洗：`text_prompt → ai_generate`，另放一个输入未连接的 pixel_cleanup，
   显示本地化说明“生成完成后连接 Output，再点击开始清洗”。

任何内置模板都不预建 Output、不自动连接运行时 Output、不自动清洗。

## 5. 存储与恢复

文件名使用模板 UUID，JSON 原子改写。损坏、v1 或未来版本逐文件跳过并返回安全
警告，不阻止其他模板。重命名改同一 id；另存为生成新 id；删除不影响已插入实例。
模型 id 可保留；目标环境缺模型时允许插入，但生成卡显示可修复警告，禁止替换模型。

frame.label、frame.size、标题和尺寸按 PROJECT-FORMAT 校验。非法标题返回
invalid_template_node_title，非法尺寸返回 invalid_template_node_size。ID/位置重映射
后仍只有一条 Undo；标题不自动追加“副本”。
