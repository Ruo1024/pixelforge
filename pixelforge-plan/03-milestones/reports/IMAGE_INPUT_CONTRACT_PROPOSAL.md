# `image_input` 最小契约修订提案（评审修订版）

> 状态：**项目所有者已批准；规范文本已进入契约唯一事实来源，授权实施**
>
> 本版已吸收契约评审建议；核心建议仍是以 `asset_id` 作为唯一稳定引用，并补清素材控件、坏图降级、引用强弱、provenance、可选执行、Undo/Redo 和预发布版本例外。
>
> 适用范围：Beta 0.2 的参考图内容模块、离线示例、保存重开与素材引用完整性
>
> 拟修订文件：`02-contracts/GRAPH-SCHEMA.md`、`02-contracts/PROJECT-FORMAT.md`

## 1. 需要决策的缺口

`GRAPH-SCHEMA.md §5` 已把 `image_input` 列为 v1 内置节点，但没有定义参数 schema、素材解析、执行范围、失效引用和错误语义；`PFNode.execute(..., ctx)` 已存在，`PFGraphContext` 本身却尚未形成契约。

`PROJECT-FORMAT.md §5` 也尚未把图节点参数、正式/过渡批次、animation 和素材 provenance 纳入一份完整的引用集合，没有区分“当前内容必须存在的引用”和“只记录历史来源的引用”，也没有定义坏素材如何降级打开、保存警告如何返回。

这直接阻断 Beta 0.2 的以下用户旅程：

> 导入一张参考图 → 通过真实图连线交给离线 mock 或 Provider → 结果进入批次 → 替换或修复失效参考 → 保存、关闭并重新打开后保持引用、结果与来源记录。

直接实现会迫使 UI、图运行器、ProjectService 或 AssetLibrary 各自发明一部分规则，形成第二份逻辑真相。因此必须先由项目所有者批准完整的最小契约，再实施代码。

## 2. 建议批准的规范文本

### 2.1 节点参数、端口与素材控件

`image_input` 的稳定图数据只有一个项目内素材引用：

```json
{
  "id": "5d52db26-3ce9-48ec-b414-6e546ddf852d",
  "type": "image_input",
  "position": [280, 0],
  "params": { "asset_id": "uuid-of-imported-asset" }
}
```

- 输入端口：无。
- 输出端口：`image`，类型为 `image`。
- 参数 schema 新增通用 `kind = "asset_ref"`：

  ```json
  {
    "key": "asset_id",
    "label_key": "GRAPH_PARAM_REFERENCE_ASSET",
    "kind": "asset_ref",
    "default": ""
  }
  ```

- `asset_ref` 在通用检查器中渲染为项目素材选择/替换控件，并可调用统一导入入口；不得把 `asset_id` 当作普通自由文本，也不得由检查器按节点类型或字段名另写特例。
- 文件名、显示名、`origin` 来源类别、尺寸和预览不复制进节点参数；它们统一从 AssetLibrary 的素材元数据和位图读取。“来源”不表示或持久化用户机器上的原始绝对路径。
- 文件导入必须先把位图注册进 AssetLibrary，再以一个用户可见的 Undo/Redo 动作创建或更新 `params.asset_id` 及同一入口产生的必要画布/图状态。导入失败时不得留下半更新节点。
- Undo 恢复原节点参数、连线和卡片状态；已经成功注册的素材继续留在素材库，Redo 重新引用同一 `asset_id`。Undo、替换和解除引用均不得隐式删除素材；孤立素材清理不属于本切片。
- 替换参考图只更新 `params.asset_id`；旧素材能否由用户显式删除，按 §2.5 的引用完整性规则决定。

### 2.2 执行上下文、可选输入与输出

- 节点不得直接依赖全局 autoload，也不得保存或读取本地绝对路径。
- core 侧新增受控的 `PFGraphContext`（`RefCounted` 或等价接口适配器），图运行器通过它提供素材解析能力；节点不得直接接收 AssetLibrary Node。最小接口为：

  ```gdscript
  func has_asset(asset_id: String) -> bool
  func get_asset_image(asset_id: String) -> Image
  ```

- `has_asset(asset_id)` 表示项目素材库存在该 id 的元数据；`get_asset_image(asset_id)` 成功时返回规范化 RGBA8 Image 的安全副本，位图缺失或无法解码时返回 `null`。
- 成功时 `image_input.execute()` 输出 `{"image": Image}`。下游修改返回值不得污染 AssetLibrary 中的原图。
- `ai_generate.image` 继续是可选端口。未连接参考图时，文本生成必须正常运行；未连接、未进入本次目标上游依赖闭包的空 `image_input` 不得阻断其他生成链。
- 已连接进本次执行路径的 `image_input` 才参与执行和错误归属。它为空、失效或无法解码时，错误归属 `image_input`；素材解析成功但 Provider 不支持参考图时，错误归属 `ai_generate`，由既有 capability/请求适配层给出用户可见说明。
- 连接参考图时，离线 mock 与真实 Provider 都沿同一图输入路径接收该 Image；UI 不得旁路上传文件。离线 mock 至少应把规范化参考图内容哈希确定性地纳入输出或输出元数据，使自动化和用户都能证明参考图没有被静默忽略；这不承诺 mock 具备真实 img2img 质量。
- 运行状态、进度和瞬态错误不写项目文件；`asset_id`、图连线、成功物化的批次及 §2.3 的 provenance 持久化。

### 2.3 生成结果 provenance

生成结果的 provenance 必须记录执行当时实际使用的参考素材，而不能只记录可被后续修改的 `graph_id`：

```json
{
  "graph_id": "graph_main",
  "reference_asset_id": "uuid-of-imported-asset",
  "reference_content_sha256": "sha256-of-normalized-rgba8-pixels"
}
```

- 未连接参考图时，两个字段可缺省或为 `null`；连接并成功生成时必须写入。
- `reference_content_sha256` 基于执行时规范化 RGBA8 像素内容及尺寸计算，保证节点后来替换素材后，旧批次仍能证明当时实际使用的输入内容。
- `reference_asset_id` 属于 §2.5 定义的历史引用：保留来源关系和失效警告，但不单独阻止素材删除。
- provenance 不复制参考图位图，不保存原始绝对路径，也不递归猜测 `provider_meta` 中的任意字符串是否为素材引用。

### 2.4 可恢复错误、坏素材降级与结构化警告

运行器把以下错误归属到 `image_input` 节点，并允许用户替换后重跑：

| code | 条件 | 用户可见语义 |
|---|---|---|
| `missing_asset_reference` | `asset_id` 为空且节点进入本次执行路径 | 选择或导入一张参考图 |
| `asset_not_found` | 项目素材库不存在该 id 的元数据 | 参考图已失效，请替换 |
| `asset_decode_failed` | 有元数据，但位图缺失或无法解码 | 参考图无法读取，请替换 |

- 错误不得删除节点、连线、旧批次结果、原引用文本或仍存在的素材数据。卡片显示失效占位、素材 id 的短前缀和替换入口，不伪造预览。
- 单个素材 PNG 缺失或解码失败不得阻止整个项目打开。AssetLibrary 仍加载其元数据并标记位图不可用；存在但损坏的原始 PNG 字节必须原样保留，直到用户替换或显式删除该素材。
- 对“元数据存在但 PNG 缺失”的素材，不伪造空白 PNG。项目允许在保留元数据和失效引用的情况下“另存为”修复副本，并产生结构化警告。
- 保存前校验引用，但失效引用是可恢复警告，不把一次成功写出的项目保存改成错误。禁止静默删除、重写 id 或用其他素材顶替。
- ProjectService 提供单一 `get_validation_warnings() -> Array[Dictionary]` 访问层；打开后和每次保存校验后刷新。最小 warning 结构为：

  ```json
  {
    "code": "asset_reference_not_found",
    "path": "graphs/graph_main/nodes/5d52db26-3ce9-48ec-b414-6e546ddf852d/params/asset_id",
    "asset_id": "missing-asset-id",
    "strength": "live"
  }
  ```

- `code` 至少区分 `asset_reference_not_found`、`asset_bitmap_missing` 和 `asset_decode_failed`；`path` 是稳定的项目逻辑路径；`strength` 为 `live|history`。用户可见文案统一走 i18n，服务层不得返回散落的最终展示字符串。

### 2.5 保存与删除引用完整性

素材引用分为两类：

- **live 引用**：当前画布、节点、批次、board 或 animation 实际使用该素材；删除会直接破坏当前内容。
- **history 引用**：只记录派生或生成历史；来源缺失会降低追溯/复现能力，但不会使现有结果本身无法显示或使用。

`PROJECT-FORMAT.md §5` 的引用集合明确扩展为：

| 项目路径 | 强度 | 删除语义 |
|---|---|---|
| `canvas.items[type=sprite].asset_id` | live | 阻止删除 |
| 过渡形态 `canvas.items[type=batch_card].asset_ids[]` | live | 阻止删除 |
| 过渡形态 `selected_asset_ids[]`、`focus_asset_id`、`compare_asset_ids[]`、`review_states` 的键 | live | 阻止删除 |
| `graphs/*` 中 `image_input.params.asset_id` | live | 阻止删除 |
| `graphs/*` 中 `batch.params.asset_ids[]`、`focus_asset_id`、`compare_asset_ids[]`、`review_states` 的键 | live | 阻止删除 |
| `boards/*` 中 tile cell 与 free item 的明确 `asset_id` | live | 阻止删除 |
| `anim/*.anim.json.frames[]` | live | 阻止删除 |
| `assets/*.meta.json.provenance.parent_asset` | history | 不阻止删除，失效时警告 |
| `assets/*.meta.json.provenance.cleanup.source_asset` | history | 不阻止删除，失效时警告 |
| `assets/*.meta.json.provenance.reference_asset_id` | history | 不阻止删除，失效时警告 |

规则：

1. 保存时扫描 live 与 history 引用。失效引用保留原文并产生 §2.4 的结构化警告；现有幽灵节点、失效素材项目仍可打开和“另存为”修复副本。
2. 交互式删除素材时，只要任一 live 引用或既有运行时占用仍存在就返回 `ERR_BUSY`。UI 使用扫描结果提示引用位置，并引导用户先替换或解除引用。
3. 只有 history 引用时允许显式删除；历史字段继续保留原 id 和内容哈希，并在后续校验中报告 `strength = "history"` 的警告。
4. 引用扫描在 ProjectService/AssetLibrary 的单一服务边界实现；各卡片不得维护独立引用计数真相。扫描只识别契约列出的字段，不递归猜测任意 JSON 字符串。
5. 新增稳定素材引用字段时必须先更新此集合和自动化；插件私有引用需由插件契约显式注册或自行拥有删除策略，不得被核心递归误判。

### 2.6 版本与兼容

- 项目所有者若批准本提案，同时批准把两个契约中含糊的“`M3` 之前”预发布例外改为：**首个公开分发或项目所有者明确冻结项目格式之前，未发布工程候选可经所有者逐次批准，在 `graph_version = 1`、`format_version = 1` 内补全定义。**
- 当前分支仍是未合并、未发布的 `0.2.0-beta.1` 工程候选；本次按上述明确后的例外就地补全 v1，不新增迁移函数。受影响测试夹具随实现更新，并在报告中记录内部候选的兼容风险。
- 不含 `image_input` 的既有项目无需迁移且可继续读取，但删除保护和保存警告会覆盖更多既有引用，行为会比旧候选更严格；不得再表述为“完全不受影响”。
- 类型尚未注册时，未知 `image_input` 继续按幽灵节点规则往返保留原文。类型注册后，它不再是幽灵节点；PFGraph 对已知节点的未知参数字段仍须往返保留，执行只规范读取 `asset_id`。
- 对旧参数中的 `path`、`file_path` 或其他本地路径字段不猜测、不自动导入、不迁移；保留原文并要求用户显式选择或导入素材。
- 不含参考图的现有文本生成链继续有效；`ai_generate.image` 的可选端口语义不改变。

### 2.7 本切片主动放弃的优势

本提案选择数据安全、项目可携带、规则统一和错误可恢复，明确暂不选择以下能力：

- 不支持外部链接素材，因此放弃“项目更小、外部文件修改后自动刷新、多个项目共享同一原文件”的优势。
- 节点不复制名称、来源路径、尺寸和预览快照，因此素材元数据也丢失时只能显示 id 前缀，放弃更丰富的自动找回体验。
- 每个 `image_input` 只引用一张图，不在 Beta 0.2 增加多参考图、权重、裁剪、遮罩或 Provider 专属构图参数。
- 不允许 UI 旁路上传，不优先获得单一 Provider 的专属接入速度；换取离线、在线、保存和重跑的一致路径。
- 返回 Image 副本会产生少量内存和复制成本；换取下游不能意外修改素材库原图。
- 替换、Undo 和解除引用不自动删除旧素材，可能产生孤立素材；自动垃圾回收和素材清理器另立后续任务。
- 允许带失效引用的项目打开和另存，放弃“每个成功保存的项目必然完全有效”的强不变量；换取受损项目可恢复且不静默丢数据。
- provenance 采用 history 弱引用，允许用户显式删除来源图；换取素材可清理，但来源图删除后只能依靠 id 与内容哈希追溯，不能完整重现像素内容。
- v1 原地补全放弃显式新版本号和迁移链带来的内部候选隔离；该取舍只适用于尚未公开、经项目所有者批准的预发布候选。

## 3. 批准后的实现与验证边界

批准后才实施以下完整切片：

1. 先把本文批准文本写入 `GRAPH-SCHEMA.md` 与 `PROJECT-FORMAT.md`，包括 `asset_ref`、PFGraphContext、provenance、warning schema、引用强弱和预发布例外；
2. 新增并注册 `image_input` 节点及受控 PFGraphContext 素材解析适配器；
3. 新增参考图内容卡：真实预览、名称/`origin` 来源类别、选择、导入、替换和失效占位；所有用户文案进入集中 i18n；
4. 空白入口与离线示例创建真实 `image_input → ai_generate.image` 连线；离线 mock 确定性消费参考图，真实 Provider 继续沿同一请求路径；
5. 物化结果记录 `reference_asset_id` 与 `reference_content_sha256`，保存重开后保持原文；
6. 引用扫描覆盖正式图参数、sprite、过渡 batch_card、正式 batch、board、animation 和明确 provenance 字段；删除按 live/history 规则执行；
7. AssetLibrary/ProjectService 支持单素材损坏时降级打开、保留损坏字节、结构化 warning 与可修复另存；
8. 覆盖编辑、导入/替换、Undo/Redo、输入路由、未连接可选参考、三类失效资源、Provider capability、保存重开、删除拒绝/允许、离线运行与 provenance；
9. 自动化至少包含：五类正式 live 引用与过渡 batch_card 的删除拒绝、history-only 删除允许、provenance 与未知参数往返、坏 PNG 打开/另存、warning 结构、不同参考图影响 mock、失效引用原文保留；
10. 复跑定向测试、全量 GUT、lint/format、i18n、UI scaling、`git diff --check`、内屏真实窗口冒烟并重建候选。

外接显示器矩阵和项目所有者人工验收仍是独立出口，不会因契约批准、工程自动化或 agent 冒烟自动视为通过。

## 4. 项目所有者决策

本版需要项目所有者特别确认两项产品取舍：

1. 当前内容引用为 live 强引用；provenance 为 history 弱引用，不单独阻止显式删除来源素材。
2. 当前未公开候选经逐次批准可在 v1 内就地补全，首个公开分发或所有者格式冻结后恢复“升版 + 迁移”纪律。

请在以下三种结论中明确选择一种：

- **批准**：接受上述两项取舍，按本文规范修订两个契约并实施完整切片；
- **修改后批准**：指出需要修改的条款，修订提案后再实施；
- **否决**：参考图模块登记为 Beta 0.2 未通过项，Beta 0.2 不能按当前计划称为完成。
