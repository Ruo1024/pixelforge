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
│   └── {asset_id}.anim.json  # 动画数据（帧序列、时长；M6 定义）
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
      "collapsed": false           // LOD/折叠态（仅显示，不影响逻辑）
    }
  ]
}
```

规则：
- 画布元素 position 强制整数（像素网格对齐，体验原则1）。
- `node` 元素是画布上一切图节点（style/prompt/generate/batch/process…）的统一引用形态：只存"画在哪、第几层、是否折叠"，节点的类型/参数/连线全在 `graphs/`。连线在画布上从 graphs 渲染，不写进本文件。
- `batch` 是 `type:"node"` 的一种（其 graphs 节点 `type=batch`），渲染为容器卡（队列网格 + 边框菜单）；物化的 `asset_id` 队列存在 graphs 节点 params 中。这就是「一等节点 + 画布卡」双身份的落地方式（见 GRAPH-SCHEMA §5a）。
- **M2.1 临时例外**：M3 前尚无正式 graph 持久化，alpha 清洗台先允许 `type:"batch_card"` 直接在 canvas.json 中保存 `asset_ids` 队列、卡片位置和卡内勾选状态。它不含端口、不含连线、不写 graphs；M3 实施正式 batch 节点时，应把该形态迁入 `type:"node"` + `graphs/{graph_id}.json` 的 `type=batch` params。
- `graph_anchor` 标记为 **legacy**：统一画布后整张图直接长在画布上，锚点退化；保留仅为读取早期数据，不再新写。

## 5. 读写规则

- **原子写**：先写临时文件 `.pxproj.tmp`，成功后 rename 替换。崩溃恢复靠 `user://autosave/` 周期快照（默认 3 分钟，保留最近 5 份）。
- **延迟加载**：打开项目只读 manifest + canvas + 视口内素材；其余素材按需加载（asset_library 负责 LRU 缓存）。
- **引用完整性**：保存时校验 canvas/boards 引用的 asset_id、canvas 的 `node` 元素引用的 node_id 都存在；删除素材时若被引用，UI 必须警告；node_id 对账失败标幽灵节点（不丢数据）。

## 6. 迁移

`project_service.gd` 维护 `MIGRATIONS: Array[Callable]`，索引 i 把 version i 升到 i+1。打开旧文件时依次执行，全部成功才进入内存模型。每个迁移函数配 `tests/fixtures/projects/v{i}_sample.pxproj` 回归样本。

> **预发布期约定（M3 之前）**：本软件在 M3 前无可持久使用的真实项目（仅测试夹具），故格式变更（如本轮新增 `node` 元素类型）**直接在 format_version = 1 定义内就地修订，不写迁移函数**；受影响的测试夹具随之重生成。升版 + 迁移纪律自**首个公开版本**起启用。
