# GRAPH-SCHEMA.md — 节点图数据契约与执行语义

> 版本：graph_version = 1。本文件是节点系统（功能3）的唯一事实来源。
> 设计哲学：**够用的简单**。线性链 + 少量扇出，不做循环、不做子图（v1 范围外）。

## 1. 图 JSON

```json
{
  "graph_version": 1,
  "id": "graph_main",
  "name": "场景物体批量生成",
  "nodes": [
    {
      "id": "n1",
      "type": "style_preset",        // 注册表中的类型名
      "position": [0, 0],            // GraphEdit 画布坐标（仅 UI 用）
      "params": { "preset_ref": "embedded", "preset": { "...": "..." } }
    },
    {
      "id": "n4",
      "type": "ai_generate",
      "position": [900, 0],
      "params": { "provider_id": "retrodiffusion", "batch_size": 4, "seed_mode": "random" }
    }
  ],
  "edges": [
    { "from": ["n1", "style"], "to": ["n4", "style"] }
  ]
}
```

- 边 `from/to` 为 `[node_id, port_name]`。
- 端口在节点类型定义中声明，不在图 JSON 里重复。

## 2. 端口类型系统

| 类型 | 颜色(UI) | 载荷 (Variant) | 说明 |
|---|---|---|---|
| `style` | 紫 | StylePreset | 风格预设 |
| `text` | 灰 | String | 提示词片段 |
| `text_list` | 灰条纹 | PackedStringArray | 批量描述（一行一物体）|
| `spec` | 蓝 | Dictionary | 尺寸/比例/数量规格 |
| `image` | 绿 | Image | 单张图 |
| `image_list` | 绿条纹 | Array[Image] | 图列表（批量主干）|
| `asset_list` | 金 | Array[String] (asset ids) | 已入库素材引用 |

**连接规则**：同类型可连；`image → image_list` 自动包装；`image_list → image` 禁止（必须经"选择/拆分"节点）。类型校验在 `pf_graph.gd::can_connect()` 单点实现，GraphEdit UI 只调用它。

## 3. 节点基类契约

```gdscript
# core/graph/pf_node.gd
class_name PFNode extends RefCounted
# —— 静态描述（子类覆写）——
func get_type() -> String                  # 唯一类型名，snake_case
func get_display_name() -> String
func get_category() -> String              # style|input|generate|process|output
func get_input_ports() -> Array[Dictionary]   # [{name, type, required}]
func get_output_ports() -> Array[Dictionary]  # [{name, type}]
func get_param_schema() -> Array[Dictionary]  # 检查器自动生成 UI 的依据
# —— 执行（子类覆写）——
# inputs: {port_name: Variant}; ctx 见 §4
# 返回 {port_name: Variant}；失败返回 {"__error": PFError}
func execute(inputs: Dictionary, params: Dictionary, ctx: PFGraphContext) -> Dictionary
# 长任务子类覆写：返回 true 表示 execute 内部会用 ctx.report_progress
func is_async() -> bool
```

`get_param_schema()` 条目：`{key, label, kind(enum: int|float|bool|text|text_multiline|enum|palette|provider|seed), default, min, max, options}` —— 检查器据此自动渲染参数面板，新节点零 UI 代码。

## 4. 执行语义（executor.gd）

1. **校验**：无环（Kahn 拓扑排序）、必填端口已连或参数有默认。失败返回结构化错误列表（UI 红框标节点）。
2. **调度**：拓扑序执行；无依赖关系的节点可并行（受 task_queue 并发上限约束）。
3. **批量语义（核心！）**：当节点收到 `image_list`/`text_list` 而自身按单项处理时，executor 自动 map 展开（对列表每项调用一次 execute，结果重组为列表）。节点声明 `handles_list() -> bool` 可接管整列表（如"拼接 spritesheet"节点）。
4. **进度与取消**：executor 包装为一个 PFTask；ctx.report_progress(node_id, ratio)；取消时正在跑的 AI 请求调 provider.cancel()，未开始节点不再启动。
5. **缓存**：节点输出按 `(node_id, params_hash, input_hashes)` 记忆化缓存于内存；重跑只算脏节点。`ai_generate` 默认不缓存（除非 seed 固定）。
6. **结果落地**：`output_to_canvas` / `output_to_library` 节点把 Image 写入素材库（生成 provenance 元数据）并在画布锚点附近排布。

## 5. v1 内置节点清单（M3/M4 任务卡逐一实现）

| 类型名 | 类别 | 输入 | 输出 | 说明 |
|---|---|---|---|---|
| `style_preset` | style | – | style | 选择/内嵌风格预设 |
| `text_prompt` | input | – | text | 自由提示词 |
| `object_list` | input | – | text_list | 多行物体描述 |
| `size_spec` | input | – | spec | 目标尺寸/比例/每物体数量 |
| `image_input` | input | – | image | 从画布/文件/素材库取图 |
| `ai_generate` | generate | style, text/text_list, spec, image(可选参考) | image_list | 调 Provider 生成（M4 接通，M3 用 mock）|
| `pixel_cleanup` | process | image_list, style(可选) | image_list | 功能1 管线节点化 |
| `matting` | process | image_list | image_list | 功能2 抠图节点化 |
| `slice` | process | image_list | image_list | 功能2 连通域切分 |
| `outline` | process | image_list, style(可选) | image_list | 描边添加/移除 |
| `palette_map` | process | image_list, style | image_list | 调色板重映射 |
| `select` | process | image_list | image_list | 人工勾选子集（执行暂停待交互）|
| `output_to_canvas` | output | image_list | – | 铺到画布 |
| `output_to_library` | output | image_list | asset_list | 入素材库 |

## 6. 版本迁移

同 PROJECT-FORMAT §6 机制：`graph_version` + 迁移链。节点类型缺失（插件未装）时图仍可加载，缺失节点渲染为"幽灵节点"（保留参数原文，禁止执行），**不丢用户数据**。

## 7. 插件扩展点

插件通过 `node_registry.register(type_name, script)` 注入新节点类型（校验 type_name 带插件前缀防冲突，如 `comfyui.run_workflow`）。UI 的节点添加菜单自动按 category 分组列出注册表全部条目。
