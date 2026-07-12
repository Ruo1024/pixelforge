# `image_input` 最小契约修订提案

> 状态：**待项目所有者批准，尚未写入契约唯一事实来源，尚未授权实现**
>
> 适用范围：Beta 0.2 的参考图内容模块、离线示例、保存重开与素材引用完整性
>
> 拟修订文件：`02-contracts/GRAPH-SCHEMA.md`、`02-contracts/PROJECT-FORMAT.md`

## 1. 需要决策的缺口

`GRAPH-SCHEMA.md §5` 已把 `image_input` 列为 v1 内置节点，但没有定义参数、素材解析、失效引用和错误语义；`PROJECT-FORMAT.md §5` 也尚未把图节点参数中的素材引用纳入保存与删除检查。直接实现会迫使 UI 或运行器自行发明第二份逻辑真相，因此必须先批准契约。

## 2. 建议批准的规范文本

### 2.1 节点参数与端口

`image_input` 的稳定图数据只有一个素材引用：

```json
{
  "id": "reference_1",
  "type": "image_input",
  "position": [280, 0],
  "params": { "asset_id": "uuid-of-imported-asset" }
}
```

- 输入端口：无。
- 输出端口：`image`，类型为 `image`。
- 参数 schema：`asset_id`，字符串，默认 `""`，在检查器中使用素材选择/替换控件。
- 文件名、显示名、来源、尺寸和预览不复制进节点参数；它们统一从 AssetLibrary 的素材元数据和位图读取。
- 文件导入必须先把位图注册进 AssetLibrary，再以一次原子 Undo/Redo 操作写入 `params.asset_id`。
- 替换参考图只更新该参数；旧素材是否删除由引用完整性规则决定，不随替换隐式删除。

### 2.2 执行上下文与输出

- 节点不得直接依赖全局 autoload，也不得保存本地绝对路径。
- 图运行器通过受控 `PFGraphContext` 提供素材解析能力；最小接口为 `has_asset(asset_id)` 和 `get_asset_image(asset_id)`。
- 成功时 `image_input.execute()` 输出 `{"image": Image}`；返回的 Image 是调用方可安全使用的副本。
- `ai_generate.image` 继续是可选端口。连接参考图时，离线 mock 与真实 Provider 都沿同一图输入路径接收该 Image；Provider 是否支持参考图仍由既有 capability/请求适配层判定，不在 UI 旁路上传文件。
- 运行状态、进度和瞬态错误不写项目文件；`asset_id`、图连线和成功物化的批次/provenance 按既有规则持久化。

### 2.3 可恢复错误

运行器把以下错误归属到 `image_input` 节点并允许用户替换后重跑：

| code | 条件 | 用户可见语义 |
|---|---|---|
| `missing_asset_reference` | `asset_id` 为空 | 选择或导入一张参考图 |
| `asset_not_found` | 项目素材库不存在该 id | 参考图已失效，请替换 |
| `asset_decode_failed` | 有元数据但位图缺失或无法解码 | 参考图无法读取，请替换 |

错误不得删除节点、连线、旧批次结果或原素材。卡片显示失效占位、素材 id 的短前缀和替换入口，不伪造预览。

### 2.4 保存与删除引用完整性

`PROJECT-FORMAT.md §5` 的素材引用集合扩展为：

- `canvas.items[type=sprite].asset_id`；
- `graphs/*` 中 `image_input.params.asset_id`；
- `graphs/*` 中 `batch.params.asset_ids`、`focus_asset_id`、`compare_asset_ids` 和 `review_states` 的键；
- boards、animations 与 provenance 中既有明确引用字段。

规则：

1. 保存时校验稳定引用。失效引用保留原文并产生结构化警告，禁止静默删除或改写；现有幽灵/失效素材项目仍可打开和“另存为”修复副本。
2. 交互式删除素材时，只要上述任一稳定引用仍存在就返回 `ERR_BUSY`，UI 提示先替换或解除引用。
3. 引用扫描在 ProjectService/AssetLibrary 的单一服务边界实现；各卡片不得维护独立引用计数真相。
4. 自动化至少覆盖 `image_input`、批次、sprite、board、animation 五类引用的删除拒绝，以及失效引用保存重开的原文保留。

### 2.5 版本与兼容

- 当前分支仍是未合并、未发布的 `0.2.0-beta.1` 工程候选；按两个契约的预发布例外，在 `graph_version = 1`、`format_version = 1` 内补全定义，不升版、不新增迁移函数。
- 未包含 `image_input` 的既有项目不受影响。
- 已经存在但未知的 `image_input` 原始参数继续按幽灵节点规则保留；本节点注册后，仅规范读取 `asset_id`，不猜测或迁移本地路径字段。

## 3. 批准后的实现与验证边界

批准后才实施以下切片：

1. 新增并注册 `image_input` 节点及 `PFGraphContext` 素材解析接口；
2. 新增参考图内容卡：真实预览、名称/来源、导入/替换、失效占位；
3. 空白入口与离线示例改为创建真实 `image_input → ai_generate.image` 连线；
4. 引用扫描覆盖图参数与现有稳定素材引用；
5. 覆盖编辑、Undo/Redo、输入路由、失效资源、保存重开、删除拒绝、离线运行与 provenance；
6. 复跑定向测试、全量 GUT、lint/i18n/UI scaling、内屏真实窗口冒烟并重建候选。

外接显示器矩阵和项目所有者人工验收仍是独立出口，不会因契约批准自动视为通过。

## 4. 项目所有者决策

请在以下三种结论中明确选择一种：

- **批准**：按本文规范修订两个契约并实施完整切片；
- **修改后批准**：指出需要修改的条款，修订提案后再实施；
- **否决**：参考图模块登记为 Beta 0.2 未通过项，Beta 0.2 不能按当前计划称为完成。
