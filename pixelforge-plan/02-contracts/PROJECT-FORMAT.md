# PROJECT-FORMAT.md — .pxproj 项目文件格式契约

> 版本：format_version = 1。任何改动需新增迁移函数并升版本号（**预发布期例外见 §6**）。

## 1. 容器

`.pxproj` 是标准 ZIP 文件（不加密，压缩级别 6），便于用户手动检查与 git LFS 管理。

```
my_project.pxproj (ZIP)
├── manifest.json          # 清单（必须，UTF-8）
├── canvas/
│   └── canvas.json        # 无限画布元素布局（含节点引用，仅布局）
├── graphs/
│   └── {graph_id}.json    # 节点图（每图一文件，逻辑唯一事实来源，schema 见 GRAPH-SCHEMA.md）
├── assets/
│   ├── {asset_id}.png     # 素材位图（RGBA PNG，1:1 真像素，禁止预放大）
│   └── {asset_id}.meta.json
├── palettes/
│   └── {palette_id}.json  # 用户导入的自定义调色板（可选，schema 见 STYLE-PRESETS.md §3）
├── boards/
│   └── {board_id}.json    # 地图拼接画板（M5 定义详细 schema）
├── anim/
│   └── {anim_id}.anim.json   # 动画数据（帧序列、时长；M5 定义）
└── thumbs/                # 缩略图缓存（可丢弃，加载时可重建）
```

> **逻辑/视图分离（方案 A）**：`graphs/` 存逻辑（节点类型/参数/连线 `edges`，唯一事实来源仍是 GRAPH-SCHEMA）；`canvas/canvas.json` 存布局（含 `node` 引用元素）。加载时按 `node_id` 对账，引用不上则标幽灵节点（§5 引用完整性已有兜底）。连线在画布上**从 graphs 渲染**，不写进 canvas.json。

## 2. manifest.json

```json
{
  "format_version": 1,
  "app_version": "0.1.0",
  "name": "My Farm Assets",
  "created_at": "2026-06-11T10:00:00Z",
  "modified_at": "2026-06-11T12:34:56Z",
  "style_preset": { "...": "内嵌 StylePreset 对象，见 STYLE-PRESETS.md" },
  "custom_palettes": [
    {
      "id": "custom_farm_12",
      "name": "Farm 12",
      "path": "palettes/custom_farm_12.json"
    }
  ],
  "entries": {
    "canvases": ["canvas"],
    "graphs": ["graph_main"],
    "boards": [],
    "asset_count": 42
  }
}
```

规则：
- `style_preset` 内嵌而非引用，保证项目文件自包含、可分享。
- `custom_palettes` 可缺省；存在时每项 `path` 必须指向 ZIP 内 `palettes/{palette_id}.json`。打开项目时先注册这些调色板，再解析清洗参数或素材 provenance 中的 `palette_ref`。
- 所有 id 用 `crypto.generate_uuid()` 风格的 UUIDv4 字符串（小写连字符）。
- 时间一律 UTC ISO8601。

## 3. assets/{id}.meta.json

```json
{
  "id": "a1b2c3d4-...",
  "name": "scarecrow_01",
  "tags": ["prop", "farm", "generated"],
  "size": [32, 48],
  "origin": "generated",          // generated | imported | edited | sliced
  "provenance": {                  // 溯源（AI 合规 + 可重现）
    "provider": "retrodiffusion",
    "model": "rd_flux",
    "prompt": "...",
    "seed": 12345,
    "parent_asset": null,          // 切分/编辑的来源素材 id
    "graph_id": "graph_main",      // 由哪张图产出（可空；菜单处理路径下为空，见 GRAPH-SCHEMA §4.7）
    "reference_asset_id": null,    // 执行时使用的参考素材 id（history 引用）
    "reference_content_sha256": null, // 规范化 RGBA8 像素及尺寸的 SHA-256
    "reference_asset_ids": [],     // 新生成写有序复数 history 引用
    "reference_content_sha256s": [],
    "generation_snapshot": {       // 生成当时的安全、不可变设置摘要
      "provider_id": "retrodiffusion", "model_id": "rd_plus",
      "prompt": "...", "negative_prompt": "", "style": {},
      "width": 32, "height": 32, "seed": 123,
      "reference_asset_ids": [], "reference_content_sha256s": [],
      "source_generate_node_id": "generate", "run_id": "run_uuid"
    },
    "created_at": "...",
    "cleanup": {                   // 可选；M1 清洗产物写入，旧项目可缺省
      "source_asset": "parent-id",
      "params": { "...": "JSON-safe PFCleanupParams" },
      "report": { "...": "JSON-safe pipeline report" }
    }
  },
  "palette_ref": "db32",          // 素材实际使用的调色板（可为内嵌色表）
  "anim": null                     // 有动画时指向 anim/{id}.anim.json
}
```

## 4. canvas/canvas.json

```json
{
  "camera": { "center": [0, 0], "zoom": 1.0 },
  "items": [
    {
      "id": "uuid",
      "type": "sprite",            // sprite | batch_card(M2.1 temp) | node | frame | note | graph_anchor(legacy)
      "asset_id": "a1b2c3d4-...",  // type=sprite 时必填
      "position": [128, -64],      // 画布世界坐标，整数（像素对齐）
      "scale_factor": 1,           // 旧图片预览倍率；Beta 0.6 保留兼容，见 §4.1
      "display_title": "Scarecrow", // 可选；独立图片卡显示标题
      "size": [320, 380],          // 可选；独立图片卡请求的外框尺寸
      "z_index": 0,
      "locked": false,
      "frame_id": null             // 所属编组框
    },
    {
      "id": "batch-temp-uuid",
      "type": "batch_card",        // M2.1 临时批次卡；M3 后升级为 type=node + graphs batch
      "asset_ids": ["uuid-a", "uuid-b"],
      "selected_asset_ids": [],
      "review_states": { "uuid-a": "keep" },
      "review_filter": "all",
      "focus_asset_id": "uuid-a",
      "compare_asset_ids": ["uuid-a-before", "uuid-b-before"],
      "compare_mode": "current",     // current | previous | split
      "review_layout": "contact",    // contact | focus
      "label": "Batch",
      "display_title": "Farm props", // 可选；只覆盖画布显示标题
      "size": [600, 240],             // 可选；用户请求的展开尺寸
      "position": [320, 64],
      "z_index": 1,
      "locked": false
    },
    {
      "id": "uuid2",
      "type": "node",              // 画布上的图节点引用（含 batch 批次内容节点）
      "node_id": "n7",             // 指向 graphs/{graph_id}.json 中的节点
      "graph_id": "graph_main",
      "position": [256, -32],
      "z_index": 0,
      "display_title": "Forest props", // 可选；不进入 Graph 或执行
      "size": [400, 520],             // 可选；画布世界整数，请求的展开尺寸
      "review_layout": "contact",    // 仅 batch 节点使用：contact | focus
      "collapsed": false,          // LOD/折叠态（仅显示，不影响逻辑）
      "locked": false,             // 锁定时禁止移动、改名和缩放
      "frame_id": null             // 所属显式阶段组；缺省表示未分组
    },
    {
      "id": "frame_uuid",
      "type": "frame",
      "graph_id": "graph_main",   // frame 只容纳同一 graph 的节点
      "title": "Reference pass",
      "color": "4f6f8fff",        // 8 位 RGBA hex
      "position": [64, -96],
      "size": [1180, 520],         // 正整数世界尺寸
      "z_index": -1
    }
  ]
}
```

规则：
- 画布元素 position 强制整数（像素网格对齐，体验原则1）。
- `node` 元素是画布上一切图节点（style/prompt/generate/batch/process…）的统一引用形态：只存布局与显示状态（位置、层级、显示标题、请求尺寸、折叠），以及 batch 这类画布驻留节点的审阅视图状态；节点的类型/参数/连线全在 `graphs/`。连线在画布上从 graphs 渲染，不写进本文件。
- `frame` 是显式阶段组。最小字段为 `id / type / graph_id / title / color / position / size / z_index`；不保存 `member_ids`。成员归属的唯一真相是 `node` 画布项的 `frame_id`。
- `frame.title` 使用与 `display_title` 相同的单行清理和 80 code point 计数；空白时回退本地化“阶段”。`frame.size` 是实际世界边界，读取为整数并钳制到 `320×240` 至 `32768×32768`；它不是成员自动包围盒，也不使用 batch 的请求/有效双尺寸。
- 一个 frame 只能容纳同一 `graph_id` 的节点。成组或移入组遇到跨 graph 节点时必须拒绝并返回结构化原因；空间重叠或拖过边界不会自动改变成员。
- `frame_id` 只由“成组 / 移入组 / 移出组 / 解组”显式动作修改。旧项目缺少该字段时按 `null` 读取；引用不存在或 graph 不匹配时按未分组显示，产生 `frame_reference_not_found` 或 `frame_graph_mismatch` 结构化警告，同时原始 `frame_id` 必须在保存重开中保留。
- frame 不嵌套、不折叠、不锁定、不自动布局。删除 frame 等同解组：保留节点和内部连线，并清除有效成员的 `frame_id`。
- `batch` 是 `type:"node"` 的一种（其 graphs 节点 `type=batch`），渲染为容器卡（队列网格 + 边框菜单）；物化的 `asset_id` 队列存在 graphs 节点 params 中。这就是「一等节点 + 画布卡」双身份的落地方式（见 GRAPH-SCHEMA §5a）。
- **M2.1 临时例外**：M3 前尚无正式 graph 持久化，alpha 清洗台先允许 `type:"batch_card"` 直接在 canvas.json 中保存 `asset_ids` 队列、卡片位置和卡内勾选状态。它不含端口、不含连线、不写 graphs；M3 实施正式 batch 节点时，应把该形态迁入 `type:"node"` + `graphs/{graph_id}.json` 的 `type=batch` params。
- `graph_anchor` 标记为 **legacy**：统一画布后整张图直接长在画布上，锚点退化；保留仅为读取早期数据，不再新写。

### 4.1 Beta 0.6 卡片显示标题与请求尺寸

`display_title` 与 `size` 适用于正式 `type:"node"`、兼容读取的旧 `type:"batch_card"` 和独立图片卡 `type:"sprite"`。它们不写入 graph params。`frame` 继续使用已有 `title / size`，不新增同义字段。

#### `display_title`

- 只改变画布显示，不影响节点类型、端口、执行、缓存、provenance 或模板参数；
- 是用户数据，不随界面语言翻译；字段缺失或清除后，系统默认标题随界面语言翻译；
- graph batch 的回退顺序为 `display_title` → `node.params.label` → 本地化“结果”；`image_input` 和 `sprite` 为 `display_title` → 可解析素材名 → 本地化“图片”；其他节点为 `display_title` → 本地化节点类型；旧 batch_card 为 `display_title` → `label` → 本地化“结果”；
- 提交时把换行和 Tab 转为空格、去首尾空白，最多 80 个 Unicode code point；按 Godot `String.length()` 计数并在 code point 边界截断，不按 UTF-8 字节计数，组合符号分别计数；全空白等于删除字段；
- 非字符串值按无覆盖标题渲染，保存时移除无效值；未知的其他 canvas 字段仍须原样往返。

#### `size`

- 表示用户请求的**展开尺寸**，格式为 `[width, height]`，单位是画布世界整数；不乘 UI scale，也不得通过 `Node2D.scale` 拉伸文字或控件；
- 缺失是合法旧数据，使用节点类型默认值；形态错误时使用默认值；数值读取后四舍五入，再按类型最小值与用户请求上限 `1600×1200` 钳制；下一次保存写规范化整数；
- 折叠只把有效高度改为 56，不覆盖请求的展开高度；展开后恢复并重新计算；
- 普通节点的有效尺寸等于规范化请求尺寸；batch 的有效高度还要容纳全部当前结果；
- 只有请求尺寸写项目、剪贴板和模板；派生的有效高度禁止持久化。

| 节点 | 缺省尺寸 | 最小尺寸 |
|---|---:|---:|
| `text_prompt` | 360×300 | 320×240 |
| `object_list` | 400×520 | 360×360 |
| `style_preset` | 320×280 | 280×220 |
| `size_spec` | 320×260 | 280×220 |
| `image_input` | 320×380 | 280×300 |
| `sprite` 独立图片卡 | 见下方旧数据公式；素材不可解析时 320×380 | 200×188 |
| `reference_set` | 400×480 | 360×320 |
| `ai_generate` | 400×520 | 360×400 |
| graph `batch` / 旧 `batch_card` | 600×240 | 360×240 |
| 幽灵、未知和其他轻节点 | 320×180 | 240×144 |

`sprite` 缺少 `size` 时，按旧图片尺寸得到确定默认值，再在下次保存写成显式尺寸：

```text
legacy_preview_width = image_width * max(1, scale_factor)
legacy_preview_height = image_height * max(1, scale_factor)
default_width = clamp(legacy_preview_width + 32, 200, 1600)
default_height = clamp(legacy_preview_height + 60, 188, 1200)
```

宽度的 32 是左右各 16 内边距；高度的 60 是 32 标题轨 + 28 元数据栏。图片缺失/不可解码时使用 320×380。`scale_factor` 继续原样往返，只用于缺少 `size` 的旧数据推导；一旦存在 `size`，外框与预览布局以 `size` 为准，图片按比例、最近邻、居中显示，不拉伸。旧 sprite 的左上 position 保持不变，不自动重排其他元素；不得删除旧 `scale_factor`。

Batch 的规范计算如下：

```text
header = 44
padding = 16
thumbnail = 128
gap = 12
action_row = 40
focus_preview_height = clamp(round((width - 2*padding) * 9/16), 240, 480)

columns = max(1, floor((width - 2*padding + gap) / (thumbnail + gap)))
rows = ceil(slot_count / columns)
grid_height = rows*thumbnail + max(0, rows-1)*gap
focus_active = review_layout == "focus" and focus_asset_id resolves to a visible slot
action_y = header + padding
preview_y = action_y + action_row + gap
grid_y = preview_y + (focus_preview_height + gap if focus_active else 0)
required_content_height = max(
  240,
  grid_y + grid_height + padding
)

effective_width = requested_width
effective_height = max(requested_height, required_content_height)
```

- `review_filter == "all"` 时，已完成任务的 `slot_count` 等于全部实际结果数；任务未完成时为 `max(asset_ids.size, expected_count)`，不足部分显示占位格；
- 其他筛选下，`slot_count` 等于当前筛选可见项，界面必须同时显示可见数/总数与清除筛选入口；
- 垂直顺序固定为 `Header → 16 padding → Action row → 12 gap → Focus/Compare preview（仅有效 focus）→ 12 gap → 完整网格 → 16 padding`；不得把 Action row 放到几千像素高的网格底部；
- Contact、Focus 与 Compare 都必须保留完整候选网格；有效 Focus/Compare 在网格上方增加同一个 `focus_preview_height` 主预览区，Compare 在区内并排显示 A/B；focus 引用失效或不在当前可见筛选时回退 Contact 并显示可修复说明；不得分页、使用卡内纵向滚动、截断尾项或只创建前 N 个 slot；
- 用户宽度改变会改变列数与派生高度；素材减少时自动增长部分可收回，但不能低于请求高度；
- 派生高度变化不单独进入 Undo，也不得修改 frame size 或 `frame_id`；
- 选框、命中、剔除、小地图、端口、连线和 Fit All 一律使用有效尺寸。

#### 编辑、复制与兼容

- 一次标题提交或一次缩放拖拽各是一条 Undo；鼠标移动只预览，Esc 取消且不入栈；rename/resize/collapse 前后 Graph 必须不变；
- Graph clipboard v1 对 node 原样携带 `display_title / size / collapsed`；粘贴只重映射 ID 和位置，不保存派生高度、不自动加“副本”后缀；独立 sprite 不进入 Graph clipboard，但现有 Duplicate/Undo 必须保留其 `display_title / size / scale_factor`；
- 工作流模板的相同规则见 `WORKFLOW-TEMPLATE.md`；
- 10%/25%/50% 等 LOD 只改变绘制详略，不改变请求尺寸、有效尺寸、世界边界、端口或连线；
- 项目仍保持 `format_version = 1`，属于首个公开分发前已批准的可选字段补全。

## 4a. boards/{board_id}.json（M5）

```json
{
  "id": "board_uuid", "name": "farm_scene",
  "grid": {"tile_size": 16, "cols": 60, "rows": 40},
  "layers": [
    {"id": "layer_uuid", "name": "terrain", "kind": "tile", "visible": true,
     "opacity": 1.0, "blend": "normal", "cells": {"12,7": {"asset_id": "...", "variant": 0}}},
    {"id": "layer_uuid", "name": "props", "kind": "free", "visible": true,
     "opacity": 1.0, "blend": "normal", "items": [
       {"id": "item_uuid", "asset_id": "...", "anim_id": null, "pos": [192,112],
        "z": 0, "flip_h": false, "anim_offset_ms": 0}
     ]}
  ]
}
```

规则：grid 的 tile_size/cols/rows 均为正整数；layer kind 仅 `tile|free`，blend 仅
`normal|add|multiply`；tile cell key 固定为 `x,y` 且必须在边界内；free item 至少引用
`asset_id` 或 `anim_id` 之一。未知字段往返保留，引用缺失时显示警告而不丢弃数据。

## 4b. anim/{anim_id}.anim.json（M5）

```json
{
  "id": "anim_uuid", "name": "torch",
  "frames": ["asset_uuid_1", "asset_uuid_2"],
  "durations_ms": [100, 100], "loop": true,
  "tags": [{"name": "idle", "from": 0, "to": 1}]
}
```

规则：frames 与 durations_ms 等长且非空，duration 最小 1ms；tags 可选且使用含首尾帧索引；帧是独立素材引用。删除被
board/animation 引用的素材必须拒绝或先由用户解除引用。

## 5. 读写规则

- **原子写**：先写临时文件 `.pxproj.tmp`，成功后 rename 替换。崩溃恢复靠 `user://autosave/` 周期快照（默认 3 分钟，保留最近 5 份）。
- **延迟加载**：打开项目只读 manifest + canvas + 视口内素材；其余素材按需加载（asset_library 负责 LRU 缓存）。
- **坏素材降级**：单个素材 PNG 缺失或解码失败不得阻止项目打开。保留元数据；存在但损坏的 PNG 字节原样保留，缺失 PNG 不伪造空白图。项目可在保留失效引用的情况下另存修复副本。
- **结构化警告**：ProjectService 在打开后和每次保存校验后刷新 `get_validation_warnings() -> Array[Dictionary]`。条目至少为 `{code, path, asset_id, strength}`；code 区分 `asset_reference_not_found|asset_bitmap_missing|asset_decode_failed`，strength 为 `live|history`。服务层不返回最终展示文案。
- **node 引用**：canvas 的 `node` 元素引用不到 graph/node 时标幽灵节点并保留原文。
- **frame 引用**：canvas 的 `node.frame_id` 引用不到同 graph frame 时以未分组方式渲染，保留原文，并通过 `get_validation_warnings()` 返回结构化警告。frame 自身不得保存成员数组。

### 5a. 素材引用强度与完整性

引用扫描只识别下表明确字段，不递归猜测任意 JSON 字符串：

| 项目路径 | 强度 | 删除语义 |
|---|---|---|
| `canvas.items[type=sprite].asset_id` | live | 阻止删除 |
| 过渡 `batch_card` 的 `asset_ids[]`、`selected_asset_ids[]`、`focus_asset_id`、`compare_asset_ids[]`、`review_states` 键 | live | 阻止删除 |
| `graphs/*` 的 `image_input.params.asset_id` | live | 阻止删除 |
| `graphs/*` 的 `reference_set.params.asset_ids[]` | live | 阻止删除 |
| `graphs/*` 的 `batch.params.asset_ids[]`、`focus_asset_id`、`compare_asset_ids[]`、`review_states` 键 | live | 阻止删除 |
| boards tile/free item 的明确 `asset_id` | live | 阻止删除 |
| animations `frames[]` | live | 阻止删除 |
| provenance `parent_asset`、`cleanup.source_asset`、`reference_asset_id`、`reference_asset_ids[]` | history | 只警告，不阻止删除 |

`generation_snapshot.reference_asset_ids[]` 与 provenance 顶层复数字段表达同一批实际输入，扫描器只从 provenance 顶层计一次 history 引用；快照用于详情/复制设置，不作为第二套引用真相。旧单数字段继续保留和扫描，新生成同时写复数字段但不要求回填旧字段。

- 保存扫描 live 与 history 引用；失效引用原文保留并产生结构化警告，成功写出的可恢复项目不因此变成保存错误。
- 素材只要仍有 live 引用或运行时占用，显式删除返回 `ERR_BUSY`；只有 history 引用时允许删除，历史 id 与内容哈希继续保留并在后续校验中警告。
- 引用扫描由 ProjectService/AssetLibrary 的单一服务边界实现。卡片不得维护独立真相；插件私有引用须显式注册或自行拥有删除策略。

## 6. 迁移

`project_service.gd` 维护 `MIGRATIONS: Array[Callable]`，索引 i 把 version i 升到 i+1。打开旧文件时依次执行，全部成功才进入内存模型。每个迁移函数配 `tests/fixtures/projects/v{i}_sample.pxproj` 回归样本。

> **预发布期约定**：首个公开分发或项目所有者明确冻结项目格式之前，未发布工程候选可经项目所有者逐次批准，在 `format_version = 1` 内补全定义而不写迁移函数；受影响测试夹具随之更新。首个公开分发或格式冻结后恢复“升版 + 迁移”纪律。本次引用完整性与坏素材降级补全已获项目所有者批准。
