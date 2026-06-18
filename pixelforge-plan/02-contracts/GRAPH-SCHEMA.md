# GRAPH-SCHEMA.md — 节点图数据契约与执行语义

> 版本：graph_version = 1。本文件是节点系统（功能3）的唯一事实来源。
> 设计哲学：**够用的简单**。线性链 + 少量扇出，不做循环、不做子图（v1 范围外）。
> 节点轻量化：除生成节点与批次容器外，process 类节点为「预设工具节点」，默认收进扩展分组。
> 处理有两条等价路径——**菜单一键（默认、不入图）** 与 **接处理节点（可复现、入图）**，二者共用同一份 core 算法（见 §4.7）。
>
> 统一画布：节点、参考卡、批次容器同住一张 PFInfiniteCanvas，端口/连线自绘（不用 GraphEdit 的 GraphNode）。本契约只管「图的逻辑」；「图画在画布哪里」见 PROJECT-FORMAT §4。

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
      "position": [0, 0],            // 画布世界坐标（视图用；权威布局见 canvas.json）
      "params": { "preset_ref": "embedded", "preset": { "...": "..." } }
    },
    {
      "id": "n4",
      "type": "ai_generate",
      "position": [900, 0],
      "params": { "provider_id": "retrodiffusion", "batch_size": 4, "seed_mode": "random" }
    },
    {
      "id": "b1",
      "type": "batch",               // 批次内容节点（见 §5a），持久物化
      "position": [1400, 0],
      "params": { "asset_ids": ["uuid-a", "uuid-b"], "label": "稻草人候选" }
    }
  ],
  "edges": [
    { "from": ["n1", "style"], "to": ["n4", "style"] },
    { "from": ["n4", "images"], "to": ["b1", "in"] }
  ]
}
```

- 边 `from/to` 为 `[node_id, port_name]`。
- 端口在节点类型定义中声明，不在图 JSON 里重复。
- 连线在画布上从本文件（graphs）渲染，不写进 canvas.json（逻辑/视图分离，见 PROJECT-FORMAT §4）。

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

**连接规则**：同类型可连；`image → image_list` 自动包装；`image_list → image` 禁止（必须经"选择/拆分"节点）。类型校验在 `pf_graph.gd::can_connect()` 单点实现，画布连线 UI 只调用它。

`batch` 节点输入 `image_list`、输出 `image_list`（持久化已物化批次）；它既是图的输出落点，又能继续向下游供图（详见 §5a）。

## 3. 节点基类契约

```gdscript
# core/graph/pf_node.gd
class_name PFNode extends RefCounted
# —— 静态描述（子类覆写）——
func get_type() -> String                  # 唯一类型名，snake_case
func get_display_name() -> String
func get_category() -> String              # style|input|generate|process|output|container
func get_input_ports() -> Array[Dictionary]   # [{name, type, required}]
func get_output_ports() -> Array[Dictionary]  # [{name, type}]
func get_param_schema() -> Array[Dictionary]  # 检查器自动生成 UI 的依据
# —— 执行（子类覆写）——
# inputs: {port_name: Variant}; ctx 见 §4
# 返回 {port_name: Variant}；失败返回 {"__error": PFError}
func execute(inputs: Dictionary, params: Dictionary, ctx: PFGraphContext) -> Dictionary
# 长任务子类覆写：返回 true 表示 execute 内部会用 ctx.report_progress
func is_async() -> bool
# 画布常驻节点（如 batch）返回 true：其输出被物化持久保存，
# 重算整图时不重生成，除非显式重跑该节点。默认 false。
func is_canvas_resident() -> bool
# 画布卡菜单动作（批次节点用）。返回 [{id, label, core_op, params_schema}]，
# 每项映射到一个 core 算法；菜单执行 = 即时 + undo + provenance，不修改图结构（见 §4.7）。
# 默认返回空数组。
func get_canvas_actions() -> Array[Dictionary]
```

`get_param_schema()` 条目：`{key, label, kind(enum: int|float|bool|text|text_multiline|enum|palette|provider|seed), default, min, max, options}` —— 检查器据此自动渲染参数面板，新节点零 UI 代码。

## 4. 执行语义（executor.gd）

1. **校验**：无环（Kahn 拓扑排序）、必填端口已连或参数有默认。失败返回结构化错误列表（UI 红框标节点）。
2. **调度**：拓扑序执行；无依赖关系的节点可并行（受 task_queue 并发上限约束）。
3. **批量语义（核心！）**：当节点收到 `image_list`/`text_list` 而自身按单项处理时，executor 自动 map 展开（对列表每项调用一次 execute，结果重组为列表）。节点声明 `handles_list() -> bool` 可接管整列表（如"拼接 spritesheet"节点）。
4. **进度与取消**：executor 包装为一个 PFTask；ctx.report_progress(node_id, ratio)；取消时正在跑的 AI 请求调 provider.cancel()，未开始节点不再启动。
5. **缓存**：节点输出按 `(node_id, params_hash, input_hashes)` 记忆化缓存于内存；重跑只算脏节点。`ai_generate` 默认不缓存（除非 seed 固定）。`batch` 等 `is_canvas_resident()` 节点的物化输出持久保存，重算整图不重生成。
6. **结果落地**：生成/处理结果默认流入一个**批次内容节点**（§5a）——它在画布上持久呈现该批次队列，并作为下游供图源。`output_to_library` 仍可把批次入库得到 `asset_list`。（旧的"在锚点附近散铺"退化为批次卡内的网格排布。）
7. **菜单处理路径（both-and）**：批次节点 `get_canvas_actions()` 声明的动作直接对批内每张图调 core 算法（与对应 process 节点**同一函数**），结果作为新素材版本写回批次（provenance.origin="edited"/"cleaned"，parent_asset 链，graph_id 可空），并进 undo 栈。**不**向图中插入节点。需要可复现、可重跑的流水线时，改用 process 节点（入图、参与拓扑执行）。

## 5. v1 内置节点清单（M3/M4 任务卡逐一实现）

| 类型名 | 类别 | 输入 | 输出 | 说明 |
|---|---|---|---|---|
| `style_preset` | style | – | style | 选择/内嵌风格预设 |
| `text_prompt` | input | – | text | 自由提示词 |
| `object_list` | input | – | text_list | 多行物体描述 |
| `size_spec` | input | – | spec | 目标尺寸/比例/每物体数量 |
| `image_input` | input | – | image | 从画布/文件/素材库取图 |
| `ai_generate` | generate | style, text/text_list, spec, image(可选参考) | image_list | 调 Provider 生成（M4 接通，M3 用 mock）|
| `batch` | container | image_list | image_list / asset_list | **批次内容节点**：装一批图、持久驻留画布、整批菜单处理、可拆小批次（is_canvas_resident=true，见 §5a）|
| `pixel_cleanup` | process | image_list, style(可选) | image_list | 功能1 管线节点化（预设工具节点）|
| `matting` | process | image_list | image_list | 功能2 抠图节点化（预设工具节点）|
| `slice` | process | image_list | image_list | 功能2 连通域切分（预设工具节点）|
| `outline` | process | image_list, style(可选) | image_list | 描边添加/移除（预设工具节点）|
| `palette_map` | process | image_list, style | image_list | 调色板重映射（预设工具节点）|
| `select` | process | image_list | image_list | 人工勾选子集 = **拆小批次**：输出独立子批次（执行暂停待交互；批次卡内"拆小批次"菜单是其即时版）|
| `output_to_canvas` | output | image_list | – | 铺到批次内容节点（见 §4.6）|
| `output_to_library` | output | image_list | asset_list | 入素材库 |

**预设工具节点**：`pixel_cleanup / matting / slice / outline / palette_map` 保留在注册表，供"可复现流水线"与未来扩展，但**默认不是主路径**——日常处理走批次节点菜单（§4.7）。节点添加菜单中它们归入「扩展/进阶」分组（PRODUCT 体验原则：渐进暴露复杂度）。

## 5a. 批次内容节点（batch）

新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。

- **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
- **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
- **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
- **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
- **下游**：`batch` 的 `image_list` 输出可继续接预设工具节点或另一个 `batch`，因此既是"输出"又是"来源"。

## 6. 版本与迁移

机制：`graph_version` + 迁移链（同 PROJECT-FORMAT §6）。节点类型缺失（插件未装）时图仍可加载，缺失节点渲染为"幽灵节点"（保留参数原文，禁止执行），**不丢用户数据**。

> **预发布期约定（M3 之前）**：本软件在 M3 前无可持久使用的真实项目（仅测试夹具），故 schema 变更**直接在 graph_version = 1 定义内就地修订，不写迁移函数**；受影响的测试夹具随之重生成。升版 + 迁移纪律自**首个公开版本**起启用。

## 7. 插件扩展点

插件通过 `node_registry.register(type_name, script)` 注入新节点类型（校验 type_name 带插件前缀防冲突，如 `comfyui.run_workflow`）。预设工具节点与未来第三方处理节点同走此入口。批次节点的菜单动作亦可由插件用 `register_canvas_action(type_name, action)` 注入（同样带插件前缀防冲突）。UI 的节点添加菜单自动按 category 分组列出注册表全部条目；process 类默认折叠在「扩展」。

## 8. 画布呈现（LOD）

语义缩放仅控制**显示详略**（缩略卡 ↔ 看清图 ↔ 像素网格），**不**承载"放大进入编辑"。精修统一跳转独立编辑视图（M6）+ 共享元素过渡动画；画布只触发动画，不在画布坐标系内做像素编辑（见 PRODUCT 体验原则、M6-1 入口契约）。
