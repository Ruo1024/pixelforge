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
      "scale_factor": 1,           // 仅允许正整数倍预览缩放
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
      "review_layout": "contact",    // 仅 batch 节点使用：contact | focus
      "collapsed": false,          // LOD/折叠态（仅显示，不影响逻辑）
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
- `node` 元素是画布上一切图节点（style/prompt/generate/batch/process…）的统一引用形态：只存"画在哪、第几层、是否折叠"，以及 batch 这类画布驻留节点的审阅视图状态；节点的类型/参数/连线全在 `graphs/`。连线在画布上从 graphs 渲染，不写进本文件。
- `frame` 是显式阶段组。最小字段为 `id / type / graph_id / title / color / position / size / z_index`；不保存 `member_ids`。成员归属的唯一真相是 `node` 画布项的 `frame_id`。
- 一个 frame 只能容纳同一 `graph_id` 的节点。成组或移入组遇到跨 graph 节点时必须拒绝并返回结构化原因；空间重叠或拖过边界不会自动改变成员。
- `frame_id` 只由“成组 / 移入组 / 移出组 / 解组”显式动作修改。旧项目缺少该字段时按 `null` 读取；引用不存在或 graph 不匹配时按未分组显示，产生 `frame_reference_not_found` 或 `frame_graph_mismatch` 结构化警告，同时原始 `frame_id` 必须在保存重开中保留。
- frame 不嵌套、不折叠、不锁定、不自动布局。删除 frame 等同解组：保留节点和内部连线，并清除有效成员的 `frame_id`。
- `batch` 是 `type:"node"` 的一种（其 graphs 节点 `type=batch`），渲染为容器卡（队列网格 + 边框菜单）；物化的 `asset_id` 队列存在 graphs 节点 params 中。这就是「一等节点 + 画布卡」双身份的落地方式（见 GRAPH-SCHEMA §5a）。
- **M2.1 临时例外**：M3 前尚无正式 graph 持久化，alpha 清洗台先允许 `type:"batch_card"` 直接在 canvas.json 中保存 `asset_ids` 队列、卡片位置和卡内勾选状态。它不含端口、不含连线、不写 graphs；M3 实施正式 batch 节点时，应把该形态迁入 `type:"node"` + `graphs/{graph_id}.json` 的 `type=batch` params。
- `graph_anchor` 标记为 **legacy**：统一画布后整张图直接长在画布上，锚点退化；保留仅为读取早期数据，不再新写。

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
