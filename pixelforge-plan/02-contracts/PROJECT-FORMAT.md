# PROJECT-FORMAT.md — .pxproj 项目文件格式契约

> 版本：format_version = 1。任何改动需新增迁移函数并升版本号。

## 1. 容器

`.pxproj` 是标准 ZIP 文件（不加密，压缩级别 6），便于用户手动检查与 git LFS 管理。

```
my_project.pxproj (ZIP)
├── manifest.json          # 清单（必须，UTF-8）
├── canvas/
│   └── canvas.json        # 无限画布元素布局
├── graphs/
│   └── {graph_id}.json    # 节点图（每图一文件，schema 见 GRAPH-SCHEMA.md）
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
    "graph_id": "graph_main",      // 由哪张图产出（可空）
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
      "type": "sprite",            // sprite | batch_card(M2.1 temp) | frame | note | graph_anchor
      "asset_id": "a1b2c3d4-...",  // type=sprite 时必填
      "position": [128, -64],      // 画布世界坐标，整数（像素对齐）
      "scale_factor": 1,           // 仅允许正整数倍预览缩放
      "z_index": 0,
      "locked": false,
      "frame_id": null             // 所属编组框
    },
    {
      "id": "batch-temp-uuid",
      "type": "batch_card",        // M2.1 临时批次卡；M3 后升级为正式 batch 节点
      "asset_ids": ["uuid-a", "uuid-b"],
      "selected_asset_ids": [],
      "label": "Batch",
      "position": [320, 64],
      "z_index": 1,
      "locked": false
    }
  ]
}
```

规则：
- 画布元素 position 强制整数（像素网格对齐，体验原则1）。
- `graph_anchor` 类型把节点图锚定在画布某区域（节点图输出物默认铺在锚点附近）。
- **M2.1 临时例外**：M3 前尚无正式 graph 持久化，alpha 清洗台先允许 `type:"batch_card"` 直接在 canvas.json 中保存 `asset_ids` 队列、卡片位置和卡内勾选状态；M3 实施正式 batch 节点时，应迁入 graph schema。

## 5. 读写规则

- **原子写**：先写临时文件 `.pxproj.tmp`，成功后 rename 替换。崩溃恢复靠 `user://autosave/` 周期快照（默认 3 分钟，保留最近 5 份）。
- **延迟加载**：打开项目只读 manifest + canvas + 视口内素材；其余素材按需加载（asset_library 负责 LRU 缓存）。
- **引用完整性**：保存时校验 canvas/boards 引用的 asset_id 都存在；删除素材时若被引用，UI 必须警告。

## 6. 迁移

`project_service.gd` 维护 `MIGRATIONS: Array[Callable]`，索引 i 把 version i 升到 i+1。打开旧文件时依次执行，全部成功才进入内存模型。每个迁移函数配 `tests/fixtures/projects/v{i}_sample.pxproj` 回归样本。
